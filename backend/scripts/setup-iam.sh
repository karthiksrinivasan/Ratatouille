#!/usr/bin/env bash
# Task 1.2 — IAM & Service Account Setup
# Creates a dedicated service account for Cloud Run with least-privilege roles.
# Run this script manually after GCP project setup (Task 1.1).

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-ratatouille-hackathon}"
SA_NAME="ratatouille-runner"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud iam service-accounts create "$SA_NAME" \
    --display-name="Ratatouille Cloud Run Runner" --quiet

ROLES=(
    "roles/aiplatform.user"
    "roles/datastore.user"
    "roles/storage.objectAdmin"
    "roles/run.invoker"
)

for ROLE in "${ROLES[@]}"; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="$ROLE" --quiet
done

echo "Service account created: ${SA_EMAIL}"
echo "Roles assigned: ${ROLES[*]}"
echo ""
echo "IMPORTANT: Do NOT use the default compute service account."
echo "Use --service-account=${SA_EMAIL} when deploying to Cloud Run."
