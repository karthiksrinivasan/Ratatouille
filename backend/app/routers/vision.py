"""Vision check, visual guide, taste check, and recovery endpoints (Epic 6)."""

from datetime import datetime

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile

from app.agents.vision import assess_food_image, format_vision_response
from app.auth.firebase import get_current_user
from app.services.firestore import db
from app.services.sessions import log_session_event
from app.services.storage import upload_bytes

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
