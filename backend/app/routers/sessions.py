"""Session management endpoints (Epic 4 + Epic 7 post-session)."""

import uuid

from fastapi import APIRouter, Depends, HTTPException
from google.cloud import firestore

from app.auth.firebase import get_current_user
from app.models.session import FreestyleContext, ModeSettings, SessionCreate
from app.services.firestore import db
from app.services.gemini import gemini_client, MODEL_FLASH
from app.services.sessions import create_session_record, log_session_event

router = APIRouter()


@router.post("/sessions")
async def create_session(
    body: SessionCreate,
    user: dict = Depends(get_current_user),
):
    """Create a session — supports both recipe_guided and freestyle modes."""
    uid = user["uid"]

    if body.session_mode == "recipe_guided":
        if not body.recipe_id:
            raise HTTPException(422, "recipe_id required for recipe_guided mode")
        recipe_doc = await db.collection("recipes").document(body.recipe_id).get()
        if not recipe_doc.exists:
            raise HTTPException(404, "Recipe not found")
    elif body.session_mode != "freestyle":
        raise HTTPException(422, f"Invalid session_mode: {body.session_mode}")

    mode = (body.mode_settings or ModeSettings()).model_dump()
    freestyle_ctx = (
        body.freestyle_context.model_dump() if body.freestyle_context else {}
    )

    session_data = await create_session_record(
        uid=uid,
        session_mode=body.session_mode,
        interaction_mode=body.interaction_mode,
        allow_text_input=body.allow_text_input,
        recipe_id=body.recipe_id,
        mode_settings=mode,
        freestyle_context=freestyle_ctx,
    )

    return {
        "session_id": session_data["session_id"],
        "status": session_data["status"],
        "session_mode": body.session_mode,
        "interaction_mode": body.interaction_mode,
        "allow_text_input": body.allow_text_input,
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

    # Load recipe for session context (optional in freestyle mode)
    recipe = None
    if session.get("recipe_id"):
        recipe_doc = await db.collection("recipes").document(session["recipe_id"]).get()
        recipe = recipe_doc.to_dict() if recipe_doc.exists else None

    # Freestyle activation: generate initial plan
    initial_plan = None
    session_mode = session.get("session_mode", "recipe_guided")
    if session_mode == "freestyle":
        initial_plan = await _generate_freestyle_plan(
            session.get("freestyle_context", {})
        )

    # Activate session and set first step
    await db.collection("sessions").document(session_id).update({
        "status": "active",
        "started_at": firestore.SERVER_TIMESTAMP,
        "current_step": 1,
    })

    response = {
        "session_id": session_id,
        "status": "active",
        "session_mode": session_mode,
        "recipe": recipe,
        "message": "Session activated. Connect to WebSocket for live interaction.",
        "ws_url": f"/v1/live/{session_id}",
    }
    if initial_plan:
        response["initial_plan"] = initial_plan
    return response


async def _generate_freestyle_plan(freestyle_context: dict) -> dict:
    """Generate a short initial plan (2-4 steps) for freestyle sessions."""
    dish_goal = freestyle_context.get("dish_goal", "")
    ingredients = freestyle_context.get("available_ingredients", [])
    time_budget = freestyle_context.get("time_budget_minutes")
    equipment = freestyle_context.get("equipment", [])

    context_parts = []
    if dish_goal:
        context_parts.append(f"Goal: {dish_goal}")
    if ingredients:
        context_parts.append(f"Available ingredients: {', '.join(ingredients)}")
    if time_budget:
        context_parts.append(f"Time budget: {time_budget} minutes")
    if equipment:
        context_parts.append(f"Equipment: {', '.join(equipment)}")

    context_str = "\n".join(context_parts) if context_parts else "No specific context provided."

    try:
        response = await gemini_client.aio.models.generate_content(
            model=MODEL_FLASH,
            contents=f"""You are a cooking buddy. Generate a short initial cooking plan (2-4 concrete steps).
Keep each step to one sentence. Be actionable and practical.

User context:
{context_str}

Respond as JSON: {{"steps": ["step1", "step2", ...], "first_instruction": "what to do right now"}}""",
        )
        import json
        text = response.text.strip()
        # Handle markdown code blocks
        if text.startswith("```"):
            text = text.split("\n", 1)[1].rsplit("```", 1)[0].strip()
        plan = json.loads(text)
        return {
            "steps": plan.get("steps", ["Let's start cooking!"]),
            "first_instruction": plan.get("first_instruction", "Tell me what you'd like to make!"),
        }
    except Exception:
        # Fallback plan when Gemini is unavailable
        return {
            "steps": [
                "Tell me what you'd like to cook or what ingredients you have",
                "I'll help you prep and get started",
                "We'll cook together step by step",
            ],
            "first_instruction": "Hey! What are we cooking today?",
        }


# --- Epic 7: Post-Session ---


async def generate_completion_message(recipe_title: str) -> str:
    """Generate a warm, brief completion message for finishing cooking."""
    try:
        response = await gemini_client.aio.models.generate_content(
            model=MODEL_FLASH,
            contents=f"""Generate a warm, brief completion message for finishing cooking "{recipe_title}".
One short sentence of congratulations + one sentence about enjoying the meal.
Be warm but not over-the-top. Max 2 sentences total.""",
        )
        return response.text
    except Exception:
        return f"Great job finishing {recipe_title}! Enjoy every bite."


@router.post("/sessions/{session_id}/complete")
async def complete_session(
    session_id: str,
    user: dict = Depends(get_current_user),
):
    """Complete a cooking session with warm send-off and wind-down options (PS-01)."""
    session_doc = await db.collection("sessions").document(session_id).get()
    if not session_doc.exists:
        raise HTTPException(404, "Session not found")
    session = session_doc.to_dict()
    if session["uid"] != user["uid"]:
        raise HTTPException(403, "Access denied")
    if session["status"] != "active":
        raise HTTPException(400, "Session is not active")

    recipe = None
    recipe_title = "your freestyle creation"
    if session.get("recipe_id"):
        recipe_doc = await db.collection("recipes").document(session["recipe_id"]).get()
        recipe = recipe_doc.to_dict() if recipe_doc.exists else None
        if recipe:
            recipe_title = recipe.get("title", recipe_title)

    completion_message = await generate_completion_message(recipe_title)

    await db.collection("sessions").document(session_id).update({
        "status": "completed",
        "ended_at": firestore.SERVER_TIMESTAMP,
    })

    # Clean up guide image generators from vision router
    from app.routers.vision import _guide_generators
    if session_id in _guide_generators:
        del _guide_generators[session_id]

    await log_session_event(session_id, "session_completed", {
        "recipe_title": recipe_title,
    })

    return {
        "type": "session_complete",
        "message": completion_message,
        "wind_down": {
            "max_interactions": 3,
            "options": [
                {"id": "difficulty", "prompt": "How did that feel?", "type": "emoji_scale"},
                {"id": "memory", "prompt": "Anything I should remember for next time?", "type": "memory_confirm"},
                {"id": "photo", "prompt": "Want to snap a photo of your creation?", "type": "photo_capture"},
            ],
        },
    }


@router.post("/sessions/{session_id}/wind-down/{interaction_id}")
async def wind_down_interaction(
    session_id: str,
    interaction_id: str,
    payload: dict,
    user: dict = Depends(get_current_user),
):
    """Handle post-session wind-down interactions (PS-02, PS-03)."""
    session_doc = await db.collection("sessions").document(session_id).get()
    if not session_doc.exists:
        raise HTTPException(404, "Session not found")
    session = session_doc.to_dict()
    if session["uid"] != user["uid"]:
        raise HTTPException(403, "Access denied")

    if interaction_id == "difficulty":
        emoji = payload.get("rating")
        await log_session_event(session_id, "difficulty_rating", {"rating": emoji})
        return {"message": "Got it! Thanks for the feedback."}

    elif interaction_id == "memory":
        observations = payload.get("observations", [])
        confirmed = payload.get("confirmed", False)

        if confirmed and observations:
            for obs in observations:
                memory_id = str(uuid.uuid4())
                await db.collection("users").document(user["uid"]) \
                    .collection("memories").document(memory_id).set({
                        "observation": obs,
                        "confirmed": True,
                        "confidence": 1.0,
                        "source_session_id": session_id,
                        "created_at": firestore.SERVER_TIMESTAMP,
                    })
            return {"message": f"I'll remember {len(observations)} thing(s) for next time!"}
        return {"message": "No worries, we'll figure it out together next time."}

    elif interaction_id == "photo":
        return {"message": "Nice! Enjoy your meal."}

    raise HTTPException(400, f"Unknown interaction: {interaction_id}")


async def schedule_deferred_winddown(session_id: str, uid: str):
    """Schedule a follow-up notification for incomplete wind-down (PS-04)."""
    await db.collection("users").document(uid).collection("notifications").add({
        "type": "deferred_wind_down",
        "session_id": session_id,
        "message": "How was your cooking session? Tap to share quick feedback.",
        "created_at": firestore.SERVER_TIMESTAMP,
        "read": False,
    })
