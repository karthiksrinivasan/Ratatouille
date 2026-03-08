"""Shared fixtures for Epic 1 tests."""
import os
import pytest

# Set env vars before importing app modules
os.environ.setdefault("GCP_PROJECT_ID", "test-project")
os.environ.setdefault("GCS_BUCKET_NAME", "test-bucket")
os.environ.setdefault("ENVIRONMENT", "testing")
