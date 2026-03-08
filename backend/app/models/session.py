from datetime import datetime

from pydantic import BaseModel, Field


class SessionModeSettings(BaseModel):
    voice_enabled: bool = True
    camera_enabled: bool = False
    hands_free: bool = True


class Session(BaseModel):
    """Firestore: sessions/{session_id}"""

    session_id: str | None = None
    uid: str
    recipe_id: str
    status: str = "pending"  # pending | active | paused | completed | abandoned
    started_at: datetime | None = None
    ended_at: datetime | None = None
    mode_settings: SessionModeSettings = Field(default_factory=SessionModeSettings)


class SessionEvent(BaseModel):
    """Firestore: sessions/{session_id}/events/{event_id}"""

    event_id: str | None = None
    type: str  # voice_input | vision_frame | timer_alert | step_advance | ...
    timestamp: datetime | None = None
    payload: dict = Field(default_factory=dict)


class GuideImage(BaseModel):
    """Firestore: sessions/{session_id}/guide_images/{guide_id}"""

    guide_id: str | None = None
    step_id: str
    stage_label: str
    source_frame_uri: str | None = None
    generated_guide_uri: str | None = None
    cue_overlays: list[dict] = Field(default_factory=list)
