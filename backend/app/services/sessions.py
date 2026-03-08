"""Session creation helper for Epic 3 -> Epic 4 bridge."""

import uuid

from google.cloud import firestore

from app.services.firestore import db


async def create_session_record(
    uid: str,
    recipe_id: str,
    mode_settings: dict | None = None,
) -> dict:
    """Create a new cooking session record in Firestore.

    Returns the session data dict with session_id and status.
    """
    session_id = str(uuid.uuid4())
    session_data = {
        "session_id": session_id,
        "uid": uid,
        "recipe_id": recipe_id,
        "status": "pending",
        "started_at": None,
        "ended_at": None,
        "mode_settings": mode_settings or {
            "voice_enabled": True,
            "camera_enabled": False,
            "hands_free": True,
        },
        "created_at": firestore.SERVER_TIMESTAMP,
    }
    await db.collection("sessions").document(session_id).set(session_data)
    return session_data
