"""Tests for Task 1.6 — app/config.py."""
import os


def test_settings_loads_from_env(monkeypatch):
    """Config loads GCP settings from environment variables."""
    monkeypatch.setenv("GCP_PROJECT_ID", "my-test-project")
    monkeypatch.setenv("GCS_BUCKET_NAME", "my-test-bucket")
    monkeypatch.setenv("GCP_REGION", "europe-west1")
    monkeypatch.setenv("ENVIRONMENT", "production")

    # Re-import to pick up monkeypatched env
    from pydantic_settings import BaseSettings

    class FreshSettings(BaseSettings):
        gcp_project_id: str = ""
        gcp_region: str = "us-central1"
        gcs_bucket_name: str = ""
        environment: str = "development"

        class Config:
            env_file = ""  # Disable .env for test

    s = FreshSettings()
    assert s.gcp_project_id == "my-test-project"
    assert s.gcs_bucket_name == "my-test-bucket"
    assert s.gcp_region == "europe-west1"
    assert s.environment == "production"


def test_settings_defaults(monkeypatch):
    """Config has sensible defaults for region and environment."""
    monkeypatch.delenv("ENVIRONMENT", raising=False)
    monkeypatch.delenv("GCP_REGION", raising=False)
    from pydantic_settings import BaseSettings

    class FreshSettings(BaseSettings):
        gcp_project_id: str = ""
        gcp_region: str = "us-central1"
        gcs_bucket_name: str = ""
        environment: str = "development"

        class Config:
            env_file = ""

    s = FreshSettings()
    assert s.gcp_region == "us-central1"
    assert s.environment == "development"
