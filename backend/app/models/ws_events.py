"""Pydantic models for WebSocket event validation."""

from typing import Optional
from pydantic import BaseModel

VALID_EVENT_TYPES = [
    "voice_query", "voice_audio", "barge_in", "step_complete",
    "process_complete", "process_delegate", "conflict_choice",
    "vision_check", "context_update", "add_timer",
    "browse_start", "browse_frame", "browse_stop",
    "ambient_toggle", "resume_interrupted", "session_resume",
    "ping", "auth",
]


class IncomingWsEvent(BaseModel):
    type: str
    text: Optional[str] = None
    audio: Optional[str] = None
    step: Optional[int] = None
    process_id: Optional[str] = None
    chosen_process_id: Optional[str] = None
    frame_uri: Optional[str] = None
    context: Optional[dict] = None
    name: Optional[str] = None
    duration_minutes: Optional[float] = None
    enabled: Optional[bool] = None
    source: Optional[str] = None
    token: Optional[str] = None

    def model_post_init(self, __context):
        if self.type not in VALID_EVENT_TYPES:
            raise ValueError(f"Invalid event type: {self.type}")
