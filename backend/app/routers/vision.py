"""Vision check, visual guide, taste check, and recovery endpoints (Epic 6)."""

from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile

from app.agents.guide_image import GuideImageGenerator
from app.agents.taste import determine_cooking_stage, get_taste_dimensions
from app.agents.vision import assess_food_image, format_vision_response
from app.auth.firebase import get_current_user
from app.config import settings
from app.services.firestore import db
from app.services.gemini import gemini_client, MODEL_FLASH
from app.services.sessions import log_session_event
from app.services.storage import get_signed_url, upload_bytes

router = APIRouter()


async def _load_session_and_step(session_id: str, uid: str) -> tuple[dict, dict, dict]:
    """Load and validate session, recipe, and current step. Returns (session, recipe, current_step)."""
    session_doc = await db.collection("sessions").document(session_id).get()
    if not session_doc.exists:
        raise HTTPException(404, "Session not found")
    session = session_doc.to_dict()
    if session["uid"] != uid:
        raise HTTPException(403, "Access denied")

    recipe_doc = await db.collection("recipes").document(session["recipe_id"]).get()
    if not recipe_doc.exists:
        raise HTTPException(404, "Recipe not found")
    recipe = recipe_doc.to_dict()

    step_num = session.get("current_step", 1)
    steps = recipe.get("steps", [])
    current_step = steps[step_num - 1] if steps and step_num <= len(steps) else (steps[-1] if steps else {"step_number": 1, "instruction": "Unknown", "technique_tags": []})

    return session, recipe, current_step


@router.post("/sessions/{session_id}/vision-check")
async def vision_check(
    session_id: str,
    frame: UploadFile = File(...),
    user: dict = Depends(get_current_user),
):
    """Assess a food image with confidence-tiered response (PRD §7.5)."""
    session, recipe, current_step = await _load_session_and_step(session_id, user["uid"])

    # Upload frame to GCS
    content = await frame.read()
    timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    path = f"session-uploads/{user['uid']}/{session_id}/{timestamp}.jpg"
    frame_uri = upload_bytes(path, content, "image/jpeg")

    # Assess
    assessment = await assess_food_image(frame_uri, current_step, recipe["title"])
    response = format_vision_response(assessment)

    # Log event
    await log_session_event(session_id, "vision_check", {
        "frame_uri": frame_uri,
        "assessment": assessment,
    })

    return response


# Per-session guide generators (keyed by session_id)
_guide_generators: dict = {}


@router.post("/sessions/{session_id}/visual-guide")
async def generate_visual_guide(
    session_id: str,
    stage_label: str = Form("target"),
    source_frame: UploadFile = File(None),
    user: dict = Depends(get_current_user),
):
    """Generate a target-state guide image for the current step (PRD §7.3 MO-05)."""
    session, recipe, current_step = await _load_session_and_step(session_id, user["uid"])

    step_num = session.get("current_step", 1)
    current_step["recipe_id"] = session["recipe_id"]

    # Get or create guide generator for this session
    if session_id not in _guide_generators:
        _guide_generators[session_id] = GuideImageGenerator(session_id, recipe["title"])
    generator = _guide_generators[session_id]

    # Upload source frame if provided
    source_uri = None
    if source_frame:
        content = await source_frame.read()
        if content:
            path = f"session-uploads/{user['uid']}/{session_id}/guide_source_{step_num}.jpg"
            source_uri = upload_bytes(path, content, "image/jpeg")

    # Generate guide
    result = await generator.generate_guide(current_step, stage_label, source_uri)

    if "error" in result:
        raise HTTPException(500, result["error"])

    # Return with side-by-side data if source frame was provided
    response = {
        "type": "guide_image",
        **result,
    }
    if source_uri:
        response["source_frame_url"] = get_signed_url(
            source_uri.replace(f"gs://{settings.gcs_bucket_name}/", "")
        )

    return response


@router.post("/sessions/{session_id}/taste-check")
async def taste_check(
    session_id: str,
    description: str = Form(""),
    user: dict = Depends(get_current_user),
):
    """Taste diagnostic endpoint (PRD §7.8 TR-01 through TR-03)."""
    session, recipe, current_step = await _load_session_and_step(session_id, user["uid"])

    step_num = session.get("current_step", 1)
    total_steps = len(recipe.get("steps", []))

    # If no description, return a prompted taste check
    if not description:
        return {
            "type": "taste_prompt",
            "message": "Good moment to taste! Take a small spoonful and tell me how it is.",
            "dimensions": [d["name"] for d in get_taste_dimensions()],
        }

    # User provided feedback — run diagnostic via Gemini
    stage = determine_cooking_stage(step_num, total_steps)

    response = await gemini_client.aio.models.generate_content(
        model=MODEL_FLASH,
        contents=f"""The user is cooking {recipe['title']}, currently on step {step_num}:
"{current_step.get('instruction', '')}"

Cooking stage: {stage}
They tasted and said: "{description}"

Provide a taste diagnostic:
1. What dimension likely needs adjustment?
2. What specific ingredient and quantity to add?
3. Any warning about this stage of cooking?

Be specific, warm, and brief.""",
    )

    result = {
        "type": "taste_result",
        "message": response.text,
        "step": step_num,
        "stage": stage,
    }

    await log_session_event(session_id, "taste_check", {
        "description": description,
        "response": response.text,
    })

    return result
