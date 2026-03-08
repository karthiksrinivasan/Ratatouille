"""Graceful degradation manager — handles fallback when modalities fail (Epic 4)."""


class DegradationManager:
    """Tracks modality failures and manages degradation hierarchy.

    Hierarchy:
    1. Full multimodal — voice + vision + process bar
    2. Voice + text — vision unavailable, sensory fallback language
    3. Text only — audio unavailable, full text responses via WebSocket
    """

    FAILURE_THRESHOLD = 3

    def __init__(self):
        self.vision_available = True
        self.audio_available = True
        self.consecutive_vision_failures = 0
        self.consecutive_audio_failures = 0

    def report_vision_failure(self):
        """Report a vision processing failure."""
        self.consecutive_vision_failures += 1
        if self.consecutive_vision_failures >= self.FAILURE_THRESHOLD:
            self.vision_available = False

    def report_vision_success(self):
        """Report a successful vision check — attempt recovery."""
        self.consecutive_vision_failures = 0
        self.vision_available = True

    def report_audio_failure(self):
        """Report an audio processing failure."""
        self.consecutive_audio_failures += 1
        if self.consecutive_audio_failures >= self.FAILURE_THRESHOLD:
            self.audio_available = False

    def report_audio_success(self):
        """Report a successful audio interaction — attempt recovery."""
        self.consecutive_audio_failures = 0
        self.audio_available = True

    def get_response_modality(self) -> str:
        """Get the current response modality based on degradation state."""
        if self.audio_available and self.vision_available:
            return "full_multimodal"
        elif self.audio_available:
            return "voice_text"
        return "text_only"

    def get_vision_fallback_text(self, step: dict) -> str:
        """Generate sensory fallback text when vision is unavailable."""
        instruction = step.get("instruction", "")
        return (
            "I can't see clearly right now. Here's what to check: "
            "Listen for a steady sizzle, smell for nuttiness not burning, "
            "and test texture with a utensil. "
            f"For this step: {instruction[:100]}"
        )

    def get_degradation_notice(self) -> dict:
        """Build a client notification about current degradation state."""
        modality = self.get_response_modality()
        if modality == "full_multimodal":
            return {}

        messages = {
            "voice_text": "Vision is temporarily unavailable — I'll use descriptive cues instead.",
            "text_only": "Audio is temporarily unavailable — I'll respond with text.",
        }
        return {
            "type": "mode_update",
            "modality": modality,
            "message": messages.get(modality, ""),
            "vision_available": self.vision_available,
            "audio_available": self.audio_available,
        }
