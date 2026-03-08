from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field
import uuid


class ModeSettings(BaseModel):
    ambient_listen: bool = False      # Opt-in per session
    phone_position: str = "counter"   # "counter" | "mounted" | "held"


class FreestyleContext(BaseModel):
    dish_goal: Optional[str] = None
    available_ingredients: list[str] = []
    equipment: list[str] = []
    time_budget_minutes: Optional[int] = None
    skill_self_rating: Optional[str] = None  # beginner | intermediate | advanced


class SessionCreate(BaseModel):
    session_mode: str = "recipe_guided"  # recipe_guided | freestyle
    recipe_id: Optional[str] = None
    mode_settings: Optional[ModeSettings] = None
    freestyle_context: Optional[FreestyleContext] = None


class Session(BaseModel):
    """Firestore: sessions/{session_id}"""

    session_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    uid: str
    session_mode: str = "recipe_guided"  # recipe_guided | freestyle
    recipe_id: Optional[str] = None
    status: str = "created"  # created | active | paused | completed | abandoned
    mode_settings: ModeSettings = Field(default_factory=ModeSettings)
    freestyle_context: Optional[FreestyleContext] = None
    current_step: int = 0
    calibration_state: dict = Field(default_factory=dict)
    started_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)


class SessionEvent(BaseModel):
    """Firestore: sessions/{session_id}/events/{event_id}"""

    event_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    type: str  # voice_query | vision_check | step_complete | timer_alert | ...
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    payload: dict = Field(default_factory=dict)


class GuideImage(BaseModel):
    """Firestore: sessions/{session_id}/guide_images/{guide_id}"""

    guide_id: Optional[str] = None
    step_id: str
    stage_label: str
    source_frame_uri: Optional[str] = None
    generated_guide_uri: Optional[str] = None
    cue_overlays: List[dict] = Field(default_factory=list)
