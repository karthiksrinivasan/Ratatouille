from google.cloud import storage

from app.config import settings

gcs_client = storage.Client(project=settings.gcp_project_id)
bucket = gcs_client.bucket(settings.gcs_bucket_name)


def upload_bytes(path: str, data: bytes, content_type: str) -> str:
    """Upload bytes to GCS and return the gs:// URI."""
    blob = bucket.blob(path)
    blob.upload_from_string(data, content_type=content_type)
    return f"gs://{settings.gcs_bucket_name}/{path}"


def get_signed_url(path: str, expiration_minutes: int = 60) -> str:
    """Generate a v4 signed URL for temporary read access."""
    from datetime import timedelta

    blob = bucket.blob(path)
    return blob.generate_signed_url(
        version="v4",
        expiration=timedelta(minutes=expiration_minutes),
        method="GET",
    )
