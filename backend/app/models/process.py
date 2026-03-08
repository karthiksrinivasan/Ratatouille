from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field
import uuid


class ProcessCreate(BaseModel):
    name: str                          # e.g., "Boil pasta water"
    step_number: int                   # Which recipe step this belongs to
    duration_minutes: Optional[float] = None
    is_parallel: bool = False          # Can run alongside other processes


class Process(BaseModel):
    """Firestore: sessions/{session_id}/processes/{process_id}"""

    process_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    session_id: str
    name: str
    step_number: int
    priority: str = "P2"              # P0 (critical) to P4 (background)
    state: str = "pending"            # pending | in_progress | countdown | needs_attention | complete | passive
    started_at: Optional[datetime] = None
    due_at: Optional[datetime] = None  # When timer expires
    duration_minutes: Optional[float] = None
    buddy_managed: bool = False        # Buddy is monitoring this in background
    is_parallel: bool = False


class ProcessBarState(BaseModel):
    """Full state of the Active Process Bar, pushed to client."""

    processes: List[Process]
    active_count: int
    attention_needed: List[str]        # process_ids needing user action
    next_due: Optional[Process] = None  # Soonest timer expiring
