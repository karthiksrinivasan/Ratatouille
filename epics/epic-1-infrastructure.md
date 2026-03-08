# Epic 1: Infrastructure & Platform Foundation

## Goal

Stand up the production-ready GCP backbone — auth, compute, storage, database, CI/CD — so all subsequent epics have a working platform to build on.

## Prerequisites

- None (this is the root epic)
- GCP billing account and project creation access
- Team agreement on mobile stack (Flutter recommended)

## PRD References

- §9 Google Cloud Architecture
- §10 Data Model (Firestore)
- §15 Security, Privacy, and Trust
- NFR-05 Security

## Tech Guide References

- §5 Firestore — AsyncClient setup
- §7 Cloud Storage — bucket creation
- §8 Firebase Auth — server-side verification
- §10 Cloud Run — Dockerfile, deployment
- §11 Cloud Build & Artifact Registry
- §12 IAM & Service Accounts

---

## Tasks

### 1.1 GCP Project Setup & API Enablement

**What:** Create GCP project (or use existing), enable all required APIs.

**Implementation:**
```bash
PROJECT_ID="ratatouille-hackathon"
gcloud config set project $PROJECT_ID

gcloud services enable \
    aiplatform.googleapis.com \
    run.googleapis.com \
    firestore.googleapis.com \
    storage.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com
```

**Acceptance Criteria:**
- [ ] All 6 APIs enabled and verified via `gcloud services list --enabled`

---

### 1.2 IAM & Service Account Setup

**What:** Create a dedicated service account for Cloud Run with least-privilege roles. Never use default compute SA.

**Implementation:**
```bash
SA_NAME="ratatouille-runner"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud iam service-accounts create $SA_NAME \
    --display-name="Ratatouille Cloud Run Runner" --quiet

ROLES=(
    "roles/aiplatform.user"
    "roles/datastore.user"
    "roles/storage.objectAdmin"
    "roles/run.invoker"
)

for ROLE in "${ROLES[@]}"; do
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="$ROLE" --quiet
done
```

**Notes:**
- `datastore.user` covers Firestore read/write
- `storage.objectAdmin` allows GCS upload + read (needed for session artifacts)
- Do NOT grant `roles/owner` or `roles/editor`

**Acceptance Criteria:**
- [ ] Service account created with exactly the 4 roles listed
- [ ] Default compute SA is NOT used by any deployed service

---

### 1.3 Firestore Database Initialization

**What:** Create Firestore database in Native mode. Set up the initial collection structure.

**Implementation:**
```bash
gcloud firestore databases create --location=us-central1 --type=firestore-native
```

Collections to initialize (documents are created on first write, but define the schema in code):
- `users/{uid}` — profile, preferences, calibration_summary, created_at
- `recipes/{recipe_id}` — source_type, parsed_steps, technique_tags, ingredients_normalized, reference_image_uris, guide_image_prompts
- `inventory_scans/{scan_id}` — uid, source, image_uris, detected_ingredients, confidence_map, confirmed_ingredients, created_at
- `inventory_scans/{scan_id}/suggestions/{suggestion_id}` — source_type, recipe_id, title, match_score, missing_ingredients, estimated_time_min, difficulty
- `sessions/{session_id}` — uid, recipe_id, status, started_at, ended_at, mode_settings
- `sessions/{session_id}/processes/{process_id}` — name, priority, state, due_at, buddy_managed
- `sessions/{session_id}/events/{event_id}` — type, timestamp, payload
- `sessions/{session_id}/guide_images/{guide_id}` — step_id, stage_label, source_frame_uri, generated_guide_uri, cue_overlays
- `users/{uid}/memories/{memory_id}` — observation, confirmed, confidence, source_session_id

**Deliverable:** Create `app/services/firestore.py` with:
```python
from google.cloud.firestore import AsyncClient
from app.config import settings

db = AsyncClient(project=settings.gcp_project_id)
```

**Acceptance Criteria:**
- [ ] Firestore database created in Native mode, us-central1
- [ ] `AsyncClient` singleton available for import
- [ ] Schema documented as Pydantic models in `app/models/`

---

### 1.4 GCS Bucket Creation

**What:** Create a single GCS bucket with organized path prefixes for all media types.

**Implementation:**
```bash
BUCKET_NAME="${PROJECT_ID}-media"
gcloud storage buckets create gs://$BUCKET_NAME --location=us-central1

# No lifecycle rules needed for hackathon, but set CORS for mobile uploads
gcloud storage buckets update gs://$BUCKET_NAME --cors-file=cors.json
```

`cors.json`:
```json
[{
  "origin": ["*"],
  "method": ["GET", "PUT", "POST"],
  "responseHeader": ["Content-Type"],
  "maxAgeSeconds": 3600
}]
```

**Path structure:**
```
gs://{BUCKET}/
├── reference-crops/{recipe_id}/{step_id}.png
├── session-uploads/{uid}/{session_id}/{timestamp}.jpg
├── session-annotations/{session_id}/{event_id}.png
├── guide-images/{recipe_id}/{step_id}/{stage}.png
└── inventory-scans/{uid}/{scan_id}/{timestamp}.jpg
```

**Deliverable:** Create `app/services/storage.py` with:
```python
from google.cloud import storage
from app.config import settings

gcs_client = storage.Client(project=settings.gcp_project_id)
bucket = gcs_client.bucket(settings.gcs_bucket_name)

def upload_bytes(path: str, data: bytes, content_type: str) -> str:
    blob = bucket.blob(path)
    blob.upload_from_string(data, content_type=content_type)
    return f"gs://{settings.gcs_bucket_name}/{path}"

def get_signed_url(path: str, expiration_minutes: int = 60) -> str:
    from datetime import timedelta
    blob = bucket.blob(path)
    return blob.generate_signed_url(
        version="v4",
        expiration=timedelta(minutes=expiration_minutes),
        method="GET",
    )
```

**Acceptance Criteria:**
- [ ] Bucket created with CORS configured
- [ ] `upload_bytes` and `get_signed_url` helpers available
- [ ] GCS URI format: `gs://{bucket}/{path}` used everywhere, never raw URLs passed to Gemini

---

### 1.5 Firebase Auth Setup

**What:** Initialize Firebase project, enable Auth providers, create server-side token verification middleware.

**Implementation:**

Initialize Firebase Admin SDK (once at app startup):
```python
import firebase_admin
firebase_admin.initialize_app()
```

Create `app/auth/firebase.py`:
```python
from fastapi import Depends, Header, HTTPException
from firebase_admin import auth

async def get_current_user(authorization: str = Header(...)) -> dict:
    """FastAPI dependency — extracts and verifies Firebase ID token."""
    if not authorization.startswith("Bearer "):
        raise HTTPException(401, "Invalid authorization header")
    token = authorization[7:]
    try:
        decoded = auth.verify_id_token(token)
        return decoded  # Contains uid, email, etc.
    except auth.InvalidIdTokenError:
        raise HTTPException(401, "Invalid token")
    except auth.ExpiredIdTokenError:
        raise HTTPException(401, "Token expired")
```

**Acceptance Criteria:**
- [ ] Firebase Auth enabled with at least email/password provider
- [ ] `get_current_user` dependency reusable across all routers
- [ ] Returns decoded token with `uid` for Firestore document scoping
- [ ] 401 returned for missing, invalid, or expired tokens

---

### 1.6 Cloud Run Backend Scaffold

**What:** Create the FastAPI application skeleton with health check, CORS, auth middleware, and router mounts.

**Deliverable:** `app/main.py`:
```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import firebase_admin

app = FastAPI(title="Ratatouille API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Lock down post-hackathon
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize Firebase Admin SDK once
firebase_admin.initialize_app()

@app.get("/health")
async def health():
    return {"status": "ok"}

# Router mounts (added as epics are completed)
# from app.routers import recipes, inventory, sessions, live
# app.include_router(recipes.router, prefix="/v1", tags=["recipes"])
# app.include_router(inventory.router, prefix="/v1", tags=["inventory"])
# app.include_router(sessions.router, prefix="/v1", tags=["sessions"])
```

**Deliverable:** `Dockerfile`:
```dockerfile
FROM python:3.11-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --target=/app/deps -r requirements.txt

FROM python:3.11-slim
WORKDIR /app
COPY --from=builder /app/deps /usr/local/lib/python3.11/site-packages/
COPY . .
RUN adduser --disabled-password --gecos '' appuser
USER appuser
EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

**Deliverable:** `requirements.txt`:
```
fastapi>=0.115.0
uvicorn[standard]>=0.30.0
google-cloud-firestore>=2.19.0
google-cloud-storage>=2.18.0
google-genai>=1.0.0
google-adk>=0.3.0
firebase-admin>=6.5.0
pydantic>=2.9.0
```

**Deliverable:** `app/config.py`:
```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    gcp_project_id: str
    gcp_region: str = "us-central1"
    gcs_bucket_name: str
    environment: str = "development"

    class Config:
        env_file = ".env"

settings = Settings()
```

**Acceptance Criteria:**
- [ ] `GET /health` returns 200
- [ ] Docker image builds successfully
- [ ] App starts with `uvicorn` on port 8080
- [ ] Config loads from environment variables

---

### 1.7 CI/CD Pipeline

**What:** Cloud Build config to build, push, and deploy to Cloud Run on every trigger.

**Deliverable:** `cloudbuild.yaml`:
```yaml
steps:
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO}/${_IMAGE}', './backend']

  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO}/${_IMAGE}']

  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    args:
      - gcloud
      - run
      - deploy
      - ${_SERVICE_NAME}
      - --image=${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO}/${_IMAGE}
      - --region=${_REGION}
      - --platform=managed
      - --service-account=${_SA_EMAIL}
      - --memory=1Gi
      - --min-instances=1
      - --set-env-vars=GCP_PROJECT_ID=${PROJECT_ID},GCP_REGION=${_REGION},GCS_BUCKET_NAME=${PROJECT_ID}-media,ENVIRONMENT=production

substitutions:
  _REGION: us-central1
  _REPO: ratatouille
  _SERVICE_NAME: ratatouille-api
  _IMAGE: ratatouille-backend
  _SA_EMAIL: ratatouille-runner@${PROJECT_ID}.iam.gserviceaccount.com

options:
  logging: CLOUD_LOGGING_ONLY
```

```bash
# Artifact Registry setup (one-time)
gcloud artifacts repositories create ratatouille \
    --repository-format=docker \
    --location=us-central1

# Trigger build
gcloud builds submit --config=cloudbuild.yaml ./backend
```

**Acceptance Criteria:**
- [ ] Artifact Registry repo created
- [ ] `gcloud builds submit` succeeds end-to-end
- [ ] Cloud Run service is live with min-instances=1
- [ ] Health check passes on deployed URL

---

### 1.8 Vertex AI Client Initialization

**What:** Create the shared Gemini client used by all AI agents.

**Deliverable:** `app/services/gemini.py`:
```python
from google import genai
from app.config import settings

# Single client instance — always use Vertex AI backend for production
gemini_client = genai.Client(
    vertexai=True,
    project=settings.gcp_project_id,
    location=settings.gcp_region,
)

# Model constants
MODEL_FLASH = "gemini-2.5-flash"
MODEL_LIVE = "gemini-live-2.5-flash-preview-native-audio"
MODEL_IMAGE_GEN = "gemini-2.0-flash-preview-image-generation"
MODEL_PRO = "gemini-2.5-pro"  # Only for high-complexity reasoning escalation
```

**Acceptance Criteria:**
- [ ] Client initializes with `vertexai=True`
- [ ] Model constants defined — no hardcoded model strings elsewhere in codebase
- [ ] Simple test call (e.g., `generate_content("hello")`) succeeds from Cloud Run

---

### 1.9 Mobile Platform Bootstrap

**What:** Set up the Flutter mobile baseline so UX implementation can proceed in parallel with backend epics.

**Deliverables:**
1. Flutter project structure with feature folders (`scan`, `suggestions`, `live_session`, `vision_guide`, `post_session`)
2. Environment config strategy for backend URL + Firebase project:
   - `dev`, `staging`, `prod` flavors
3. Shared app shell:
   - global theme tokens
   - routing skeleton
   - base error/loading patterns

**Acceptance Criteria:**
- [ ] Mobile project boots on iOS and Android simulators
- [ ] Backend base URL is environment-configured (no hardcoded endpoints)
- [ ] Firebase app initialization works in mobile app shell
- [ ] Feature-module folder scaffolding exists and is committed

---

## Epic Completion Checklist

- [ ] GCP project with all APIs enabled
- [ ] Service account with least-privilege roles
- [ ] Firestore in Native mode with AsyncClient
- [ ] GCS bucket with CORS and organized path prefixes
- [ ] Firebase Auth with server-side token verification
- [ ] FastAPI app running on Cloud Run with health check
- [ ] CI/CD pipeline deploying on build submit
- [ ] Gemini client initialized and tested
- [ ] Mobile platform scaffold ready for Epic 8 implementation
