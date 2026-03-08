#!/usr/bin/env bash
# Task 1.7 — Artifact Registry setup (one-time)
# Creates the Docker repository for storing container images.

set -euo pipefail

gcloud artifacts repositories create ratatouille \
    --repository-format=docker \
    --location=us-central1

echo "Artifact Registry repo created. Build and deploy with:"
echo "  gcloud builds submit --config=backend/cloudbuild.yaml ./backend"
