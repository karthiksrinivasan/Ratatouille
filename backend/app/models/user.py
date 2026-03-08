from datetime import datetime

from pydantic import BaseModel, Field


class UserProfile(BaseModel):
    """Firestore: users/{uid}"""

    uid: str
    display_name: str | None = None
    email: str | None = None
    preferences: dict = Field(default_factory=dict)
    calibration_summary: dict = Field(default_factory=dict)
    created_at: datetime | None = None


class UserMemory(BaseModel):
    """Firestore: users/{uid}/memories/{memory_id}"""

    memory_id: str | None = None
    observation: str
    confirmed: bool = False
    confidence: float = 0.0
    source_session_id: str | None = None
