"""Adaptive calibration engine — adjusts guidance verbosity per technique (Epic 4)."""

from typing import Optional


class CalibrationEngine:
    """Tracks user signals and adjusts guidance level per technique."""

    LEVELS = ["detailed", "standard", "compressed"]

    def __init__(self):
        self.global_level = "standard"
        self.technique_levels: dict = {}  # technique_tag -> level
        self.signal_counts: dict = {
            "clarification_asks": 0,
            "skips": 0,
            "i_know_signals": 0,
            "errors": 0,
            "why_questions": 0,
        }

    def process_signal(self, signal_type: str, technique: Optional[str] = None):
        """Process a calibration signal and adjust levels."""
        self.signal_counts[signal_type] = self.signal_counts.get(signal_type, 0) + 1

        target_technique = technique or "__global__"

        if signal_type in ("skips", "i_know_signals"):
            self._adjust(target_technique, direction="compress")
        elif signal_type in ("clarification_asks", "why_questions"):
            self._adjust(target_technique, direction="expand")
        elif signal_type == "errors":
            self._adjust(target_technique, direction="expand")

    def _adjust(self, technique: str, direction: str):
        current = self.technique_levels.get(technique, self.global_level)
        idx = self.LEVELS.index(current)
        if direction == "compress" and idx < len(self.LEVELS) - 1:
            self.technique_levels[technique] = self.LEVELS[idx + 1]
        elif direction == "expand" and idx > 0:
            self.technique_levels[technique] = self.LEVELS[idx - 1]

        # Update global level if the global key was adjusted
        if technique == "__global__":
            self.global_level = self.technique_levels.get("__global__", self.global_level)

    def get_level(self, technique: Optional[str] = None) -> str:
        """Get current calibration level for a technique (or global)."""
        if technique and technique in self.technique_levels:
            return self.technique_levels[technique]
        return self.global_level

    def get_instruction_modifier(self, technique: Optional[str] = None) -> str:
        """Get an instruction string modifier based on current calibration level."""
        level = self.get_level(technique)
        if level == "detailed":
            return "Explain this step thoroughly with technique tips and common mistakes."
        elif level == "compressed":
            return "Keep it brief — just the key action and timing."
        return "Standard detail level."

    def detect_signal_from_text(self, text: str) -> Optional[str]:
        """Detect calibration signals from natural language input."""
        text_lower = text.lower()

        # Skip / "I know" signals → compress
        skip_signals = ["skip", "i know", "next", "already know", "got it", "yeah yeah"]
        if any(s in text_lower for s in skip_signals):
            return "i_know_signals"

        # Why questions → expand
        if text_lower.startswith("why") or "why do" in text_lower or "why should" in text_lower:
            return "why_questions"

        # Clarification asks → expand
        clarification_signals = [
            "what do you mean", "i don't understand", "explain",
            "how do i", "what's that", "could you clarify",
            "say that again", "repeat that",
        ]
        if any(s in text_lower for s in clarification_signals):
            return "clarification_asks"

        # Error reports → expand
        error_signals = [
            "i messed up", "it burned", "too much", "wrong",
            "mistake", "overcooked", "undercooked", "ruined",
        ]
        if any(s in text_lower for s in error_signals):
            return "errors"

        return None

    def is_critical_moment(self, step: dict) -> bool:
        """Check if the current step is a critical moment requiring detailed guidance."""
        critical_tags = ["frying", "deep-fry", "flambé", "caramel", "tempering", "searing"]
        step_tags = step.get("technique_tags", [])
        instruction = step.get("instruction", "").lower()

        if any(tag in step_tags for tag in critical_tags):
            return True
        if any(word in instruction for word in ["careful", "burn", "hot oil", "flame"]):
            return True
        return False

    def to_dict(self) -> dict:
        """Serialize calibration state for persistence."""
        return {
            "global_level": self.global_level,
            "technique_levels": self.technique_levels,
            "signal_counts": self.signal_counts,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "CalibrationEngine":
        """Restore calibration state from persisted data."""
        engine = cls()
        engine.global_level = data.get("global_level", "standard")
        engine.technique_levels = data.get("technique_levels", {})
        engine.signal_counts = data.get("signal_counts", engine.signal_counts)
        return engine
