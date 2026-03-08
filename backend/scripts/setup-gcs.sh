#!/usr/bin/env bash
# Task 1.4 — GCS Bucket Creation
# Creates the media bucket with CORS configuration.

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-ratatouille-hackathon}"
BUCKET_NAME="${PROJECT_ID}-media"

gcloud storage buckets create "gs://${BUCKET_NAME}" --location=us-central1
gcloud storage buckets update "gs://${BUCKET_NAME}" --cors-file=cors.json

echo "Bucket created: gs://${BUCKET_NAME}"
echo "Path structure:"
echo "  gs://${BUCKET_NAME}/reference-crops/{recipe_id}/{step_id}.png"
echo "  gs://${BUCKET_NAME}/session-uploads/{uid}/{session_id}/{timestamp}.jpg"
echo "  gs://${BUCKET_NAME}/session-annotations/{session_id}/{event_id}.png"
echo "  gs://${BUCKET_NAME}/guide-images/{recipe_id}/{step_id}/{stage}.png"
echo "  gs://${BUCKET_NAME}/inventory-scans/{uid}/{scan_id}/{timestamp}.jpg"
