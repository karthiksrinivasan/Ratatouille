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
