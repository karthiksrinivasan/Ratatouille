from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field


class SessionModeSettings(BaseModel):
    voice_enabled: bool = True
    camera_enabled: bool = False
    hands_free: bool = True


class Session(BaseModel):
    """Firestore: sessions/{session_id}"""

    session_id: Optional[str] = None
    uid: str
    recipe_id: str
    status: str = "pending"  # pending | active | paused | completed | abandoned
    started_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None
    mode_settings: SessionModeSettings = Field(default_factory=SessionModeSettings)


class SessionEvent(BaseModel):
    """Firestore: sessions/{session_id}/events/{event_id}"""

    event_id: Optional[str] = None
    type: str  # voice_input | vision_frame | timer_alert | step_advance | ...
    timestamp: Optional[datetime] = None
    payload: dict = Field(default_factory=dict)


class GuideImage(BaseModel):
    """Firestore: sessions/{session_id}/guide_images/{guide_id}"""

    guide_id: Optional[str] = None
    step_id: str
    stage_label: str
    source_frame_uri: Optional[str] = None
    generated_guide_uri: Optional[str] = None
    cue_overlays: List[dict] = Field(default_factory=list)
