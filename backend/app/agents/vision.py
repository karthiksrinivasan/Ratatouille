"""Vision assessor agent — confidence-tiered food image analysis (Epic 6, Tasks 6.1–6.2)."""

import json
import re

from google.genai import types

from app.services.gemini import gemini_client, MODEL_FLASH


async def assess_food_image(image_uri: str, current_step: dict, recipe_title: str) -> dict:
    """Analyze a food image and return confidence-tiered assessment."""
    step_context = f"Step {current_step.get('step_number', '?')}: {current_step.get('instruction', '')}"
    technique = ", ".join(current_step.get("technique_tags", []))

    response = await gemini_client.aio.models.generate_content(
        model=MODEL_FLASH,
        contents=[
            types.Part.from_uri(file_uri=image_uri, mime_type="image/jpeg"),
            f"""You are assessing food being cooked for the recipe "{recipe_title}".
Current step: {step_context}
Technique: {technique}

Analyze the image and assess:
1. What food state do you see? (color, texture, doneness level)
2. How confident are you in your assessment? (0.0-1.0)
3. Is this the expected state for this step?
4. What should the user do next?

Return JSON:
{{
  "confidence": float (0.0-1.0),
  "confidence_tier": "high" | "medium" | "low" | "failed",
  "assessment": "description of what you see",
  "is_expected_state": boolean,
  "recommendation": "what to do next",
  "sensory_fallback": "smell/sound/texture cues if vision is uncertain"
}}

Confidence tiers:
- high (>= 0.8): Clear view, confident assessment
- medium (0.5-0.79): Partially visible, qualified answer
- low (0.2-0.49): Obscured/unclear, ask for reposition
- failed (< 0.2): Cannot assess, fall back entirely to non-visual guidance

Return ONLY valid JSON.""",
        ],
    )

    try:
        result = json.loads(response.text)
    except (json.JSONDecodeError, AttributeError):
        text = getattr(response, "text", "") or ""
        match = re.search(r"```(?:json)?\s*([\s\S]*?)```", text)
        if match:
            try:
                result = json.loads(match.group(1))
            except json.JSONDecodeError:
                result = _fallback_result()
        else:
            result = _fallback_result()

    return result


def _fallback_result() -> dict:
    return {
        "confidence": 0.0,
        "confidence_tier": "failed",
        "assessment": "I couldn't process the image.",
        "is_expected_state": None,
        "recommendation": "Try repositioning your camera and ask me to look again.",
        "sensory_fallback": "Check by smell, sound, and touch instead.",
    }


def format_vision_response(assessment: dict) -> dict:
    """Format vision check response based on confidence tier (PRD §7.5)."""
    tier = assessment.get("confidence_tier", "failed")

    if tier == "high":
        # VC-01: Direct confirmation or correction
        return {
            "type": "vision_result",
            "confidence": "high",
            "message": assessment["assessment"],
            "recommendation": assessment["recommendation"],
            "tone": "confident",
        }

    elif tier == "medium":
        # VC-02: Qualified answer + sensory check prompt
        return {
            "type": "vision_result",
            "confidence": "medium",
            "message": f"{assessment['assessment']} — but I'm not 100% sure from this angle.",
            "recommendation": assessment["recommendation"],
            "sensory_check": assessment.get("sensory_fallback", ""),
            "tone": "qualified",
        }

    elif tier == "low":
        # VC-03: Ask for reposition + sensory fallback
        return {
            "type": "vision_result",
            "confidence": "low",
            "message": "I can't see clearly enough to tell. Can you bring the camera closer or tilt the pan toward me?",
            "sensory_check": assessment.get("sensory_fallback", ""),
            "tone": "uncertain",
        }

    else:
        # VC-04: Explicit inability + non-visual guidance
        return {
            "type": "vision_result",
            "confidence": "failed",
            "message": "I can't assess this visually right now. Let's use other senses instead.",
            "sensory_check": assessment.get("sensory_fallback", ""),
            "tone": "fallback",
        }
