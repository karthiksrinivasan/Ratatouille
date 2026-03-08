"""Taste coach agent — taste diagnostics and seasoning recommendations (Epic 6, Task 6.6)."""

import json

TASTE_DIMENSIONS = [
    {"name": "salt", "description": "Overall saltiness level"},
    {"name": "acid", "description": "Brightness/tanginess"},
    {"name": "sweet", "description": "Sweetness level"},
    {"name": "fat", "description": "Richness/mouthfeel"},
    {"name": "umami", "description": "Depth/savory intensity"},
]

DIAGNOSTIC_QUESTIONS = [
    {
        "question": "Does it taste flat or dull?",
        "likely_fix": "Likely needs acid (lemon/vinegar) or salt",
        "dimension": "salt/acid",
    },
    {
        "question": "Does it taste sharp or too bright?",
        "likely_fix": "Likely needs fat (butter/oil) or sweetness",
        "dimension": "fat/sweet",
    },
    {
        "question": "Does it taste one-note?",
        "likely_fix": "Likely needs umami (parmesan/soy) or contrasting element",
        "dimension": "umami",
    },
]

TASTE_COACH_INSTRUCTION = """You are a taste diagnostic specialist for cooking.

Taste trigger order (TR-01):
1. Prompted: You suggest a taste check at appropriate moments
2. User-explicit: User says "it tastes off" or "something's missing"
3. Visual gesture fallback: User brings spoon to mouth on camera

Five dimensions (TR-02): salt, acid, sweet, fat, umami
Always consider the COOKING STAGE when recommending adjustments:
- Early: Bold adjustments are safe, flavors will meld
- Mid: Moderate adjustments, some concentration will occur
- Late/Final: Small adjustments only, what you add is what you get

"Something's missing" diagnostic flow (TR-03) — 3 questions max:
1. "Does it taste flat or dull?" → likely needs acid (lemon/vinegar) or salt
2. "Does it taste sharp or too bright?" → likely needs fat (butter/oil) or sweetness
3. "Does it taste one-note?" → likely needs umami (parmesan/soy) or contrasting element

Keep recommendations specific:
- BAD: "add some acid"
- GOOD: "squeeze half a lemon over it" or "a splash of white wine vinegar"

Always quantify: "about half a teaspoon", "a small pinch", "one tablespoon"."""


def get_taste_dimensions() -> list:
    """Get the 5 taste dimensions for current dish assessment."""
    return TASTE_DIMENSIONS


def get_diagnostic_questions() -> list:
    """Get the 3-question diagnostic flow for 'something's missing'."""
    return DIAGNOSTIC_QUESTIONS


def determine_cooking_stage(step_number: int, total_steps: int) -> str:
    """Determine cooking stage based on step progress."""
    if total_steps == 0:
        return "mid"
    ratio = step_number / total_steps
    if ratio <= 0.33:
        return "early"
    elif ratio <= 0.66:
        return "mid"
    return "late"


def get_stage_advice(stage: str) -> str:
    """Get stage-aware adjustment guidance."""
    if stage == "early":
        return "We're early in cooking — bold adjustments are safe, flavors will meld."
    elif stage == "mid":
        return "We're mid-cook — moderate adjustments, some concentration will still occur."
    return "We're at the final stage — small adjustments only, what you add is what you get."
