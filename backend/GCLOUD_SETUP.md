# GCP Setup Guide

## Prerequisites

- [Google Cloud SDK (gcloud CLI)](https://cloud.google.com/sdk/docs/install) installed
- A GCP project created
- Python 3.11+ with dependencies from `requirements.txt`

## 1. Configure gcloud CLI

```bash
gcloud auth login
gcloud config set project <YOUR_PROJECT_ID>
```

## 2. Enable required APIs

```bash
gcloud services enable \
  firestore.googleapis.com \
  aiplatform.googleapis.com \
  storage.googleapis.com
```

## 3. Create Firestore database

```bash
gcloud firestore databases create \
  --location=us-central1 \
  --type=firestore-native
```

This creates the `(default)` database in Native mode.

## 4. Create GCS bucket

```bash
gcloud storage buckets create gs://<YOUR_BUCKET_NAME> \
  --location=us-central1 \
  --uniform-bucket-level-access
```

## 5. Set up Application Default Credentials

```bash
gcloud auth application-default login
```

This opens a browser for OAuth consent. The resulting credentials are used by Firestore, Vertex AI, and GCS clients at runtime.

## 6. Create the `.env` file

Create `backend/.env` with the following:

```env
GCP_PROJECT_ID=<YOUR_PROJECT_ID>
GCP_REGION=us-central1
GCS_BUCKET_NAME=<YOUR_BUCKET_NAME>
ENVIRONMENT=development
```

> `.env` is already in `.gitignore` — do not commit it.

## 7. Verify

```bash
cd backend
python -c "from app.main import app; print('OK')"
```

If this prints `OK` without credential errors, the setup is complete.
