from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    gcp_project_id: str = ""
    gcp_region: str = "us-central1"
    gcs_bucket_name: str = ""
    firebase_project_id: str = ""
    environment: str = "development"
    enable_internal_metrics: bool = False
    admin_uids: str = ""  # Comma-separated admin UIDs

    class Config:
        env_file = ".env"


settings = Settings()
