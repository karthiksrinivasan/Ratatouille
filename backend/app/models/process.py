from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class CookingProcess(BaseModel):
    """Firestore: sessions/{session_id}/processes/{process_id}"""

    process_id: Optional[str] = None
    name: str
    priority: int = 0
    state: str = "pending"  # pending | active | attention | completed
    due_at: Optional[datetime] = None
    buddy_managed: bool = False
