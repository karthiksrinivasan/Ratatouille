#!/usr/bin/env bash
# Task 1.1 — GCP Project Setup & API Enablement
# Run this script manually to enable all required APIs.

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-ratatouille-hackathon}"
gcloud config set project "$PROJECT_ID"

gcloud services enable \
    aiplatform.googleapis.com \
    run.googleapis.com \
    firestore.googleapis.com \
    storage.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com

echo "All 6 APIs enabled. Verify with:"
echo "  gcloud services list --enabled"
