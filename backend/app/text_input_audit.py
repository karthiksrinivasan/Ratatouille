"""Text-Input Audit Matrix (Epic 9, Task 9.12).

Documents all text input controls in session-critical paths and their
classification for the voice/video-first interaction mandate.
"""

TEXT_INPUT_AUDIT = [
    # Session-critical paths — REPLACED or REMOVED
    {
        "file": "mobile/lib/features/live_session/screens/live_session_screen.dart",
        "control": "Type Instead button + TextInputBar",
        "classification": "Replace",
        "action": "Hidden by default; only shown in degraded (voice unavailable) state",
        "rationale": "Voice-first mandate — text fallback only when voice is unavailable",
    },
    {
        "file": "mobile/lib/features/vision_guide/screens/vision_guide_screen.dart",
        "control": "Taste feedback TextField",
        "classification": "Optional",
        "action": "Moved behind ExpansionTile; quick chips are primary interaction",
        "rationale": "Tap-based chips provide voice-free input; text is optional fallback",
    },
    {
        "file": "mobile/lib/features/vision_guide/screens/vision_guide_screen.dart",
        "control": "Recovery error TextField",
        "classification": "Optional",
        "action": "Moved behind ExpansionTile; quick error chips are primary interaction",
        "rationale": "Tap-based chips provide voice-free input; text is optional fallback",
    },
    {
        "file": "mobile/lib/features/live_session/screens/cook_now_screen.dart",
        "control": "Optional context TextField",
        "classification": "Optional",
        "action": "Already hidden behind 'Add optional context' expandable; not required",
        "rationale": "Session starts without text input; context is purely optional",
    },

    # Allowed exceptions — KEEP
    {
        "file": "mobile/lib/features/recipes/screens/recipe_list_screen.dart",
        "control": "Recipe URL import TextField",
        "classification": "Keep",
        "action": "No change — not in session-critical path",
        "rationale": "Non-live authoring flow (recipe import modal). Explicit exception per Epic 9 spec.",
    },
    {
        "file": "mobile/lib/features/recipes/screens/recipe_create_screen.dart",
        "control": "Recipe creation form (title, description, ingredients, steps)",
        "classification": "Keep",
        "action": "No change — not in session-critical path",
        "rationale": "Non-live authoring flow (recipe creation). Explicit exception per Epic 9 spec.",
    },
    {
        "file": "mobile/lib/features/scan/screens/ingredient_review_screen.dart",
        "control": "Manual ingredient add TextField",
        "classification": "Keep",
        "action": "No change — pre-session setup, not live cooking",
        "rationale": "Post-scan ingredient editing. Optional correction path, not in live session.",
    },
]

# Voice/video-first regression checklist
VOICE_FIRST_REGRESSION = [
    "User can launch Cook Now → Start Cooking with zero text input",
    "User can complete full freestyle session using only voice commands",
    "User can browse fridge/pantry with only voice + camera (no typing)",
    "User can use taste check via quick chips (no typing required)",
    "User can trigger error recovery via quick chips (no typing required)",
    "'Type Instead' is only visible in degraded (voice unavailable) state",
    "Cook Now optional context is hidden by default (not required)",
    "All text inputs in live paths are behind expandable/optional controls",
]


def validate_audit():
    """Validate the audit matrix is complete and consistent."""
    classifications = {"Keep", "Replace", "Optional"}
    for entry in TEXT_INPUT_AUDIT:
        assert entry["classification"] in classifications, (
            f"Invalid classification: {entry['classification']}"
        )
        assert entry["action"], f"Missing action for {entry['file']}"
        assert entry["rationale"], f"Missing rationale for {entry['file']}"

    # Count by classification
    counts = {}
    for entry in TEXT_INPUT_AUDIT:
        c = entry["classification"]
        counts[c] = counts.get(c, 0) + 1

    return {
        "total_entries": len(TEXT_INPUT_AUDIT),
        "counts": counts,
        "regression_items": len(VOICE_FIRST_REGRESSION),
        "valid": True,
    }
