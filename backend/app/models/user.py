from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class UserProfile(BaseModel):
    """Firestore: users/{uid}"""

    uid: str
    display_name: Optional[str] = None
    email: Optional[str] = None
    preferences: dict = Field(default_factory=dict)
    calibration_summary: dict = Field(default_factory=dict)
    created_at: Optional[datetime] = None


class UserMemory(BaseModel):
    """Firestore: users/{uid}/memories/{memory_id}"""

    memory_id: Optional[str] = None
    observation: str
    confirmed: bool = False
    confidence: float = 0.0
    source_session_id: Optional[str] = None
