from google.cloud.firestore import AsyncClient

from app.config import settings

db = AsyncClient(project=settings.gcp_project_id)
