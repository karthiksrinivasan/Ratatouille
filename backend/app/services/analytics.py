"""Product analytics events (Epic 7, Task 7.6).

Emits structured product events to Firestore for all PRD §14.1 metrics.
"""
from typing import Optional

import logging

from google.cloud import firestore

from app.services.firestore import db
from app.services.metrics import metrics

logger = logging.getLogger("ratatouille.analytics")

# All product event types and when they fire
PRODUCT_EVENTS = {
    "scan_started": "User initiates fridge/pantry scan",
    "scan_completed": "Ingredients detected from scan",
    "scan_confirmed": "User confirms ingredient list",
    "suggestions_viewed": "Dual-lane suggestions displayed",
    "suggestion_selected": "User picks a recipe suggestion",
    "session_started": "Cooking session activated",
    "session_completed": "Session reaches completion",
    "session_abandoned": "Session abandoned mid-cook",
    "vision_check": "User performs vision check",
    "guide_image_requested": "User requests visual guide",
    "guide_image_feedback": "User gives thumbs up/down on guide",
    "taste_check": "Taste diagnostic performed",
    "error_recovery": "Error recovery triggered",
    "user_override": "User says 'I know' or skips",
    "memory_confirmed": "User confirms preference memory",
    "memory_rejected": "User rejects preference memory",
}


async def emit_product_event(event_type: str, uid: str, metadata: Optional[dict] = None):
    """Emit a product analytics event to Firestore and increment metrics counter."""
    event = {
        "event_type": event_type,
        "uid": uid,
        "timestamp": firestore.SERVER_TIMESTAMP,
        "metadata": metadata or {},
    }

    try:
        await db.collection("analytics_events").add(event)
    except Exception as e:
        logger.warning(f"Failed to emit event {event_type}: {e}")

    await metrics.increment(f"event_{event_type}")
