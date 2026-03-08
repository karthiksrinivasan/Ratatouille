#!/usr/bin/env bash
# deploy.sh — Deploy Ratatouille backend to Google Cloud Run
#
# Usage:
#   ./deploy.sh                          # interactive — prompts for PROJECT_ID
#   ./deploy.sh --project my-gcp-project # non-interactive
#   DRY_RUN=1 ./deploy.sh               # print commands without executing
#
# Prerequisites:
#   - gcloud CLI installed and authenticated (`gcloud auth login`)
#   - Sufficient IAM permissions on the GCP project

set -euo pipefail

# ─── Configuration (override via env or flags) ───────────────────────────────

REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-ratatouille-api}"
SA_NAME="${SA_NAME:-ratatouille-runner}"
MEMORY="${MEMORY:-1Gi}"
MIN_INSTANCES="${MIN_INSTANCES:-0}"
MAX_INSTANCES="${MAX_INSTANCES:-10}"
TIMEOUT="${TIMEOUT:-300}"
CONCURRENCY="${CONCURRENCY:-80}"
DRY_RUN="${DRY_RUN:-0}"

# ─── Parse flags ──────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case $1 in
    --project)  PROJECT_ID="$2"; shift 2 ;;
    --region)   REGION="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=1; shift ;;
    --min)      MIN_INSTANCES="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--project PROJECT_ID] [--region REGION] [--dry-run] [--min N]"
      exit 0 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

# ─── Resolve project ─────────────────────────────────────────────────────────

if [[ -z "${PROJECT_ID:-}" ]]; then
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
  if [[ -z "$PROJECT_ID" ]]; then
    echo "No GCP project set. Pass --project or run: gcloud config set project <id>"
    exit 1
  fi
  echo "Using project from gcloud config: $PROJECT_ID"
  read -rp "Continue? [Y/n] " confirm
  if [[ "${confirm,,}" == "n" ]]; then exit 0; fi
fi

SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)' 2>/dev/null || true)"

# ─── Helpers ──────────────────────────────────────────────────────────────────

run() {
  echo "+ $*"
  if [[ "$DRY_RUN" == "1" ]]; then return 0; fi
  "$@"
}

check_command() {
  if ! command -v "$1" &>/dev/null; then
    echo "ERROR: $1 is required but not installed."
    exit 1
  fi
}

# ─── Pre-flight checks ───────────────────────────────────────────────────────

check_command gcloud

echo ""
echo "======================================================"
echo "  Ratatouille Backend -- Cloud Run Deploy"
echo "======================================================"
echo "  Project:   ${PROJECT_ID} (#${PROJECT_NUMBER:-?})"
echo "  Region:    ${REGION}"
echo "  Service:   ${SERVICE_NAME}"
echo "  SA:        ${SA_EMAIL}"
echo "  Memory:    ${MEMORY}"
echo "  Instances: ${MIN_INSTANCES}-${MAX_INSTANCES}"
echo "======================================================"
echo ""

# ─── Step 1: Enable required APIs ────────────────────────────────────────────

echo "[1/5] Enabling required APIs..."
run gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  firestore.googleapis.com \
  storage.googleapis.com \
  aiplatform.googleapis.com \
  --project="$PROJECT_ID" --quiet

# ─── Step 2: Fix Cloud Build IAM permissions ─────────────────────────────────

echo "[2/5] Granting Cloud Build storage permissions..."
if [[ -n "$PROJECT_NUMBER" ]]; then
  COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
  CB_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

  # The default Compute Engine SA needs storage access for Cloud Build
  for sa in "$COMPUTE_SA" "$CB_SA"; do
    for role in roles/storage.admin roles/artifactregistry.writer roles/cloudbuild.builds.builder; do
      run gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${sa}" \
        --role="$role" \
        --condition=None \
        --quiet 2>/dev/null || true
    done
  done
  echo "  Permissions granted."
else
  echo "  WARNING: Could not resolve project number. Skipping IAM fix."
  echo "  If Cloud Build fails, manually run:"
  echo "    gcloud projects add-iam-policy-binding $PROJECT_ID \\"
  echo "      --member='serviceAccount:<PROJECT_NUMBER>-compute@developer.gserviceaccount.com' \\"
  echo "      --role='roles/storage.admin'"
fi

# ─── Step 3: Create Cloud Run service account (idempotent) ───────────────────

echo "[3/5] Ensuring service account exists..."
if ! gcloud iam service-accounts describe "$SA_EMAIL" \
    --project="$PROJECT_ID" &>/dev/null 2>&1; then
  run gcloud iam service-accounts create "$SA_NAME" \
    --display-name="Ratatouille Cloud Run runner" \
    --project="$PROJECT_ID"

  for role in \
    roles/datastore.user \
    roles/storage.objectAdmin \
    roles/aiplatform.user; do
    run gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="serviceAccount:$SA_EMAIL" \
      --role="$role" \
      --condition=None \
      --quiet
  done
else
  echo "  (already exists)"
fi

# ─── Step 4: Create GCS media bucket (idempotent) ────────────────────────────

BUCKET_NAME="${PROJECT_ID}-media"
echo "[4/5] Ensuring GCS bucket gs://${BUCKET_NAME} exists..."
if ! gcloud storage buckets describe "gs://${BUCKET_NAME}" --project="$PROJECT_ID" &>/dev/null 2>&1; then
  run gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --uniform-bucket-level-access
else
  echo "  (already exists)"
fi

# ─── Step 5: Build + Deploy to Cloud Run (source-based) ─────────────────────

BACKEND_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[5/5] Building and deploying to Cloud Run (source deploy)..."
# `gcloud run deploy --source` handles: Cloud Build, Artifact Registry, and deploy
# in one command, avoiding manual image tagging and push permissions issues.
run gcloud run deploy "$SERVICE_NAME" \
  --source="$BACKEND_DIR" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --platform=managed \
  --service-account="$SA_EMAIL" \
  --memory="$MEMORY" \
  --timeout="$TIMEOUT" \
  --concurrency="$CONCURRENCY" \
  --min-instances="$MIN_INSTANCES" \
  --max-instances="$MAX_INSTANCES" \
  --allow-unauthenticated \
  --set-env-vars="\
GCP_PROJECT_ID=${PROJECT_ID},\
GCP_REGION=${REGION},\
GCS_BUCKET_NAME=${BUCKET_NAME},\
FIREBASE_PROJECT_ID=${PROJECT_ID},\
ENVIRONMENT=production" \
  --quiet

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "Fetching service URL..."
SERVICE_URL="$(gcloud run services describe "$SERVICE_NAME" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --format='value(status.url)' 2>/dev/null || echo '(unknown)')"

echo ""
echo "======================================================"
echo "  Deploy complete!"
echo "  URL: ${SERVICE_URL}"
echo "  Health: ${SERVICE_URL}/health"
echo "======================================================"
echo ""
echo "Next steps:"
echo "  1. Update mobile .env: BACKEND_URL=${SERVICE_URL}"
echo "  2. Test: curl ${SERVICE_URL}/health"
echo "  3. Logs: gcloud run logs read ${SERVICE_NAME} --region=${REGION} --project=${PROJECT_ID}"
