from google.cloud.firestore import AsyncClient

from app.config import settings

_db = None


def get_db() -> AsyncClient:
    global _db
    if _db is None:
        _db = AsyncClient(project=settings.gcp_project_id)
    return _db


# For backward compatibility — lazy proxy
class _LazyDB:
    def __getattr__(self, name):
        return getattr(get_db(), name)

db = _LazyDB()
