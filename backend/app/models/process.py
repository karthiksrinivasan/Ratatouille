from datetime import datetime

from pydantic import BaseModel


class CookingProcess(BaseModel):
    """Firestore: sessions/{session_id}/processes/{process_id}"""

    process_id: str | None = None
    name: str
    priority: int = 0
    state: str = "pending"  # pending | active | attention | completed
    due_at: datetime | None = None
    buddy_managed: bool = False
