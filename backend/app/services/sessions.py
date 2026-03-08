"""Session service — shared by session router and scan flow (Epic 3 bridge)."""

import uuid
from typing import Optional

from google.cloud import firestore

from app.services.firestore import db


async def create_session_record(
    uid: str,
    recipe_id: str,
    mode_settings: Optional[dict] = None,
) -> dict:
    """Create and persist a session; reusable by both session router and scan flow.

    Returns the session data dict with session_id and status.
    """
    session_id = str(uuid.uuid4())
    session_data = {
        "session_id": session_id,
        "uid": uid,
        "recipe_id": recipe_id,
        "status": "created",
        "current_step": 0,
        "calibration_state": {},
        "mode_settings": mode_settings or {
            "ambient_listen": False,
            "phone_position": "counter",
        },
        "started_at": None,
        "ended_at": None,
        "created_at": firestore.SERVER_TIMESTAMP,
    }
    await db.collection("sessions").document(session_id).set(session_data)
    return session_data


async def persist_session_state(session_id: str, updates: dict):
    """Atomic update of session state fields."""
    await db.collection("sessions").document(session_id).update(updates)


async def log_session_event(session_id: str, event_type: str, payload: dict):
    """Append event to session events subcollection."""
    await db.collection("sessions").document(session_id) \
        .collection("events").add({
            "type": event_type,
            "timestamp": firestore.SERVER_TIMESTAMP,
            "payload": payload,
        })
