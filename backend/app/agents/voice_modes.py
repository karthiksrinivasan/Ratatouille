"""Voice mode manager — implements VM-01 through VM-04 (Epic 4)."""

from typing import Optional


class VoiceModeManager:
    """Manages the four voice modes and barge-in state."""

    def __init__(self):
        self.ambient_enabled = False
        self.active_query_in_progress = False
        self.buddy_speaking = False
        self.last_interrupted_response: Optional[str] = None

    def classify_input(self, event_type: str, text: str = "") -> str:
        """Determine which voice mode to handle the input with.

        Returns: "VM-01" | "VM-02" | "VM-03" | "VM-04"
        """
        # VM-04: If buddy is currently speaking and user sends input, it's a barge-in
        if self.buddy_speaking and event_type in ("voice_query", "voice_audio", "barge_in"):
            return "VM-04"
        if event_type == "vision_check":
            return "VM-03"
        if event_type == "voice_query":
            return "VM-02"
        if event_type == "voice_audio" and self.ambient_enabled:
            return "VM-01"
        return "VM-02"  # Default to active query

    def should_respond_ambient(self, transcript: str) -> bool:
        """In ambient mode, only respond to cooking-relevant speech."""
        cooking_signals = [
            "how long", "is it done", "what next", "help",
            "too hot", "burning", "ready", "timer", "step",
            "look", "check", "taste", "adjust", "smoke",
            "boiling", "sizzle", "done", "overcook",
        ]
        transcript_lower = transcript.lower()
        return any(signal in transcript_lower for signal in cooking_signals)

    def is_resume_request(self, text: str) -> bool:
        """Check if user is asking to resume an interrupted response."""
        resume_signals = [
            "continue", "go on", "what were you saying",
            "repeat", "repeat quickly", "you were saying",
            "finish what you", "keep going",
        ]
        return any(signal in text.lower() for signal in resume_signals)

    def start_speaking(self, response_text: str):
        """Mark buddy as speaking and stash response for potential barge-in."""
        self.buddy_speaking = True
        self.last_interrupted_response = response_text

    def stop_speaking(self):
        """Mark buddy as done speaking."""
        self.buddy_speaking = False

    def interrupt(self) -> Optional[str]:
        """Handle barge-in — stop speaking and return interrupted text preview."""
        self.buddy_speaking = False
        interrupted = self.last_interrupted_response
        return (interrupted or "")[:100] if interrupted else None

    def consume_interrupted(self) -> Optional[str]:
        """Get and clear the full interrupted response for resume."""
        text = self.last_interrupted_response
        self.last_interrupted_response = None
        return text

    def get_mode_state(self) -> dict:
        """Return current mode state for client UI indicators."""
        return {
            "ambient_listen": self.ambient_enabled,
            "buddy_speaking": self.buddy_speaking,
            "has_interrupted_content": self.last_interrupted_response is not None,
        }
