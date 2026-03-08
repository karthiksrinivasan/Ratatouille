"""Session management endpoints (Epic 4)."""

from fastapi import APIRouter, Depends, HTTPException
from google.cloud import firestore

from app.auth.firebase import get_current_user
from app.models.session import ModeSettings, SessionCreate
from app.services.firestore import db
from app.services.sessions import create_session_record

router = APIRouter()


@router.post("/sessions")
async def create_session(
    body: SessionCreate,
    user: dict = Depends(get_current_user),
):
    """Create a session linked to a recipe."""
    uid = user["uid"]

    # Verify recipe exists
    recipe_doc = await db.collection("recipes").document(body.recipe_id).get()
    if not recipe_doc.exists:
        raise HTTPException(404, "Recipe not found")

    mode = (body.mode_settings or ModeSettings()).model_dump()

    session_data = await create_session_record(
        uid=uid,
        recipe_id=body.recipe_id,
        mode_settings=mode,
    )

    return {
        "session_id": session_data["session_id"],
        "status": session_data["status"],
        "recipe_id": body.recipe_id,
        "mode_settings": mode,
    }


@router.post("/sessions/{session_id}/activate")
async def activate_session(
    session_id: str,
    user: dict = Depends(get_current_user),
):
    """Transition session from 'created' to 'active' — the 'Start Cooking' moment."""
    session_doc = await db.collection("sessions").document(session_id).get()
    if not session_doc.exists:
        raise HTTPException(404, "Session not found")

    session = session_doc.to_dict()
    if session["uid"] != user["uid"]:
        raise HTTPException(403, "Access denied")
    if session["status"] != "created":
        raise HTTPException(400, f"Session is already {session['status']}")

    # Load recipe for session context
    recipe_doc = await db.collection("recipes").document(session["recipe_id"]).get()
    recipe = recipe_doc.to_dict()

    # Activate session and set first step
    await db.collection("sessions").document(session_id).update({
        "status": "active",
        "started_at": firestore.SERVER_TIMESTAMP,
        "current_step": 1,
    })

    return {
        "session_id": session_id,
        "status": "active",
        "recipe": recipe,
        "message": "Session activated. Connect to WebSocket for live interaction.",
        "ws_url": f"/v1/live/{session_id}",
    }
