"""WebSocket live channel for real-time cooking sessions (Epic 4 + Epic 5)."""

import logging
import uuid as _uuid

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from firebase_admin import auth as firebase_auth

from app.models.ws_events import IncomingWsEvent

logger = logging.getLogger(__name__)

from app.services.firestore import db
from app.services.sessions import persist_session_state, log_session_event
from app.services.timers import TimerSystem
from app.services.processes import (
    initialize_processes_from_recipe,
    create_dynamic_process,
    push_process_bar,
    auto_delegate_stable_processes,
    escalate_passive_process,
    persist_process_state as persist_process,
)
from app.agents.orchestrator import create_session_orchestrator
from app.agents.guide_image import GuideImageGenerator
from app.services.analytics import emit_product_event
from app.services.browse import BrowseSession

router = APIRouter()


async def authenticate_websocket(websocket: WebSocket):
    """Authenticate WS using Firebase ID token (query param or first auth message)."""
    token = websocket.query_params.get("token", "")
    if not token:
        await websocket.send_json({"type": "auth_required", "message": "Send auth token"})
        auth_msg = await websocket.receive_json()
        if auth_msg.get("type") != "auth":
            await websocket.close(code=4401, reason="First message must be auth")
            return None
        token = auth_msg.get("token", "")

    token = token.replace("Bearer ", "").strip()
    if not token:
        await websocket.close(code=4401, reason="Missing auth token")
        return None

    try:
        return firebase_auth.verify_id_token(token)
    except Exception:
        await websocket.close(code=4401, reason="Invalid auth token")
        return None


@router.websocket("/live/{session_id}")
async def live_session(websocket: WebSocket, session_id: str):
    """Bi-directional WebSocket for real-time voice events and cooking guidance."""
    await websocket.accept()

    user = await authenticate_websocket(websocket)
    if not user:
        return

    # Validate session
    session_doc = await db.collection("sessions").document(session_id).get()
    if not session_doc.exists:
        await websocket.close(code=4004, reason="Session not found")
        return
    session = session_doc.to_dict()
    if session["uid"] != user["uid"]:
        await websocket.close(code=4403, reason="Session access denied")
        return
    if session["status"] != "active":
        await websocket.close(code=4000, reason="Session not active")
        return

    # Load recipe (optional in freestyle mode)
    session_mode = session.get("session_mode", "recipe_guided")
    recipe = None
    if session.get("recipe_id"):
        recipe_doc = await db.collection("recipes").document(session["recipe_id"]).get()
        recipe = recipe_doc.to_dict() if recipe_doc.exists else None

    # Initialize orchestrator
    orchestrator = await create_session_orchestrator(session, recipe)

    # --- Epic 4: Initialize guide image generator ---
    guide_gen = GuideImageGenerator(
        session_id=session_id,
        recipe_title=recipe.get("title", "this recipe") if recipe else "freestyle",
    )

    # --- Epic 5: Initialize process tracking ---
    processes = []
    if recipe:
        processes = await initialize_processes_from_recipe(session_id, recipe)
    orchestrator.state["processes"] = processes

    # Timer callbacks that send WS messages + persist state
    async def on_timer_due(process_id: str, process_name: str):
        # Escalate passive processes back to attention
        escalate_passive_process(processes, process_id)
        # Flag as needs_attention for active processes
        for p in processes:
            if p["process_id"] == process_id and p["state"] != "needs_attention":
                p["state"] = "needs_attention"
        await websocket.send_json({
            "type": "timer_alert",
            "process_id": process_id,
            "process_name": process_name,
            "priority": "P0",
            "message": f"{process_name} is done! Time to check.",
        })
        await persist_process(session_id, process_id, {"state": "needs_attention"})
        await push_process_bar(websocket, processes)

    async def on_timer_warning(process_id: str, process_name: str, remaining_seconds: int):
        await websocket.send_json({
            "type": "timer_warning",
            "process_id": process_id,
            "process_name": process_name,
            "remaining_seconds": remaining_seconds,
            "message": f"{process_name} — about 1 minute left.",
        })

    timer_system = TimerSystem(on_timer_due=on_timer_due, on_timer_warning=on_timer_warning)

    try:
        # Send initial greeting
        if session_mode == "freestyle":
            freestyle_ctx = session.get("freestyle_context", {})
            dish_goal = freestyle_ctx.get("dish_goal", "")
            if dish_goal:
                greeting = f"Hey! Let's make {dish_goal}. Tell me what you've got and I'll guide you."
            else:
                greeting = "Hey! I'm your cooking buddy. What are we making today?"
            await websocket.send_json({
                "type": "buddy_message",
                "text": greeting,
                "step": 1,
                "session_mode": "freestyle",
            })
        else:
            await websocket.send_json({
                "type": "buddy_message",
                "text": f"Let's cook {recipe.get('title', 'this recipe')}! "
                        "I'll walk you through it step by step.",
                "step": 1,
            })

        # Push initial process bar state
        if processes:
            await push_process_bar(websocket, processes)

        while True:
            data = await websocket.receive_json()

            # Validate incoming WS event
            try:
                validated = IncomingWsEvent(**data)
            except Exception as e:
                logger.warning(f"WS event validation failed: {e}", extra={"raw_event": data})
                await websocket.send_json({"type": "error", "message": "Invalid event format"})
                continue

            event_type = data.get("type")
            text = data.get("text", "")

            # Classify voice mode (VM-01 through VM-04)
            voice_mode = orchestrator.classify_input(event_type, text)

            if voice_mode == "VM-04" or event_type == "barge_in":
                # Barge-in: buddy was speaking, user interrupted
                response = await orchestrator.handle_barge_in(text)
                for msg in response:
                    await websocket.send_json(msg)

            elif event_type == "voice_query":
                # VM-02: Active query
                response = await orchestrator.handle_voice_query(text)
                await websocket.send_json({
                    "type": "buddy_response",
                    "text": response["text"],
                    "audio_hint": response.get("audio_hint"),
                    "step": response.get("current_step"),
                })

            elif event_type == "voice_audio":
                if voice_mode == "VM-01" and not orchestrator.should_respond_ambient(text):
                    # Ambient mode: non-cooking speech — ignore
                    continue
                audio_data = data.get("audio")
                response = await orchestrator.handle_audio_chunk(audio_data)
                if response and response.get("type") == "audio_response":
                    await websocket.send_json({
                        "type": "buddy_audio",
                        "audio": response["audio"],
                        "mime_type": response.get("mime_type", "audio/pcm"),
                    })
                elif response:
                    await websocket.send_json(response)

            elif event_type == "step_complete":
                response = await orchestrator.advance_step()
                await websocket.send_json(response)

                current_step = orchestrator.state.get("current_step", 1)

                # Auto-delegate stable processes when moving to new step
                auto_delegate_stable_processes(processes, current_step)

                # Start timers for processes matching the new step
                for p in processes:
                    if (
                        p["step_number"] == current_step
                        and p["state"] == "pending"
                        and p.get("duration_minutes")
                    ):
                        p["state"] = "countdown"
                        from datetime import datetime, timedelta
                        p["started_at"] = datetime.utcnow().isoformat()
                        p["due_at"] = (
                            datetime.utcnow() + timedelta(minutes=p["duration_minutes"])
                        ).isoformat()
                        await timer_system.start_timer(
                            p["process_id"], p["duration_minutes"], p["name"],
                        )
                        await persist_process(session_id, p["process_id"], {
                            "state": "countdown",
                            "started_at": p["started_at"],
                            "due_at": p["due_at"],
                        })

                # Push updated process bar
                await push_process_bar(websocket, processes)

                # --- D4.17/D4.22: Buddy-initiated guide image at checkpoint ---
                if recipe:
                    steps = recipe.get("steps", [])
                    step_idx = current_step - 1
                    if 0 <= step_idx < len(steps):
                        step_data = steps[step_idx]
                        if step_data.get("guide_image_prompt"):
                            try:
                                guide_result = await guide_gen.generate_guide(
                                    step=step_data,
                                    stage_label=f"step_{current_step}_target",
                                )
                                if "error" not in guide_result:
                                    await websocket.send_json({
                                        "type": "visual_guide",
                                        "image_url": guide_result["image_url"],
                                        "caption": f"Here's what step {current_step} should look like.",
                                        "visual_cues": guide_result.get("cue_overlays", []),
                                        "step": current_step,
                                    })
                                    # Narrate the guide with buddy audio hint
                                    cues = guide_result.get("cue_overlays", [])
                                    cue_text = " and ".join(cues[:2]) if cues else "the target state"
                                    await websocket.send_json({
                                        "type": "buddy_message",
                                        "text": f"I'm sending you a reference image — look for {cue_text}.",
                                        "step": current_step,
                                    })
                            except Exception as guide_err:
                                logger.warning(f"Guide image generation failed: {guide_err}")

                # Persist step change and calibration state
                await persist_session_state(session_id, {
                    "current_step": current_step,
                    "calibration_state": orchestrator.calibration.to_dict(),
                })

            elif event_type == "process_complete":
                # Client explicitly marks a process as done
                process_id = data.get("process_id")
                if process_id:
                    for p in processes:
                        if p["process_id"] == process_id:
                            p["state"] = "complete"
                            timer_system.cancel_timer(process_id)
                            await persist_process(session_id, process_id, {"state": "complete"})
                            break
                    await push_process_bar(websocket, processes)

            elif event_type == "process_delegate":
                # Client delegates a process to buddy
                process_id = data.get("process_id")
                if process_id:
                    for p in processes:
                        if p["process_id"] == process_id:
                            p["buddy_managed"] = True
                            p["state"] = "passive"
                            await persist_process(session_id, process_id, {
                                "buddy_managed": True, "state": "passive",
                            })
                            break
                    await push_process_bar(websocket, processes)

            elif event_type == "conflict_choice":
                # Client responds to P1 conflict
                chosen_id = data.get("chosen_process_id")
                if chosen_id:
                    await websocket.send_json({
                        "type": "conflict_resolved",
                        "chosen_process_id": chosen_id,
                    })

            elif event_type == "vision_check":
                frame_uri = data.get("frame_uri")
                response = await orchestrator.handle_vision_check(frame_uri)
                await websocket.send_json(response)

            elif event_type == "guide_request":
                # D4.18: User-initiated guide image request
                current_step = orchestrator.state.get("current_step", 1)
                prompt = data.get("prompt")
                step_data = {"step_number": current_step, "instruction": "current step"}
                if recipe:
                    steps = recipe.get("steps", [])
                    step_idx = current_step - 1
                    if 0 <= step_idx < len(steps):
                        step_data = steps[step_idx]
                if prompt:
                    step_data = {**step_data, "guide_image_prompt": prompt}
                try:
                    guide_result = await guide_gen.generate_guide(
                        step=step_data,
                        stage_label=f"step_{current_step}_user_request",
                        source_frame_uri=data.get("frame_uri"),
                    )
                    if "error" not in guide_result:
                        await websocket.send_json({
                            "type": "visual_guide",
                            "image_url": guide_result["image_url"],
                            "caption": f"Here's what step {current_step} should look like.",
                            "visual_cues": guide_result.get("cue_overlays", []),
                            "step": current_step,
                        })
                    else:
                        await websocket.send_json({
                            "type": "buddy_message",
                            "text": "I couldn't generate a guide image right now — try describing what you'd like to see.",
                            "step": current_step,
                        })
                except Exception as guide_err:
                    logger.warning(f"User guide request failed: {guide_err}")
                    await websocket.send_json({
                        "type": "buddy_message",
                        "text": "Guide image is taking too long — let me describe it instead.",
                        "step": current_step,
                    })

            elif event_type == "context_update":
                # In-session context capture: update freestyle context mid-session
                updates = data.get("context", {})
                ctx = orchestrator.state.get("freestyle_context", {})
                for k, v in updates.items():
                    if k == "available_ingredients" and isinstance(v, list):
                        existing = ctx.get("available_ingredients", [])
                        ctx["available_ingredients"] = list(set(existing + v))
                    else:
                        ctx[k] = v
                orchestrator.state["freestyle_context"] = ctx
                # Persist context update
                await persist_session_state(session_id, {
                    "freestyle_context": ctx,
                })
                await websocket.send_json({
                    "type": "context_updated",
                    "freestyle_context": ctx,
                })

            elif event_type == "add_timer":
                # Dynamic process/timer creation for freestyle mode
                timer_name = data.get("name", "Timer")
                duration = data.get("duration_minutes")
                if duration:
                    current_step = orchestrator.state.get("current_step", 1)
                    new_process = await create_dynamic_process(
                        session_id, timer_name, duration, current_step,
                    )
                    processes.append(new_process)
                    # Start timer immediately
                    new_process["state"] = "countdown"
                    from datetime import datetime, timedelta
                    new_process["started_at"] = datetime.utcnow().isoformat()
                    new_process["due_at"] = (
                        datetime.utcnow() + timedelta(minutes=duration)
                    ).isoformat()
                    await timer_system.start_timer(
                        new_process["process_id"], duration, timer_name,
                    )
                    await persist_process(session_id, new_process["process_id"], {
                        "state": "countdown",
                        "started_at": new_process["started_at"],
                        "due_at": new_process["due_at"],
                    })
                    await push_process_bar(websocket, processes)

            elif event_type == "browse_start":
                source = data.get("source", "fridge")  # fridge | pantry
                browse_session = BrowseSession(source=source)
                orchestrator.state["browse_session"] = browse_session
                await emit_product_event("browse_started", user["uid"], {"source": source})
                await websocket.send_json({
                    "type": "buddy_message",
                    "text": f"Great, show me your {source}! I'll tell you what I see.",
                    "browse_active": True,
                    "source": source,
                })

            elif event_type == "browse_frame":
                frame_uri = data.get("frame_uri", "")
                browse_session = orchestrator.state.get("browse_session")
                if browse_session is None:
                    browse_session = BrowseSession(source="fridge")
                    orchestrator.state["browse_session"] = browse_session
                observation = await browse_session.process_frame(frame_uri)
                await websocket.send_json({
                    "type": "browse_observation",
                    "observation": observation["observation"],
                    "confidence": observation["confidence"],
                })
                if observation.get("candidates"):
                    await websocket.send_json({
                        "type": "ingredient_candidates",
                        "candidates": observation["candidates"],
                        "cumulative": browse_session.get_all_candidates(),
                    })
                if observation.get("question"):
                    await websocket.send_json({
                        "type": "browse_question",
                        "text": observation["question"],
                    })

            elif event_type == "browse_stop":
                browse_session = orchestrator.state.get("browse_session")
                candidates = browse_session.get_all_candidates() if browse_session else []
                # Merge into freestyle context
                ctx = orchestrator.state.get("freestyle_context", {})
                existing = ctx.get("available_ingredients", [])
                new_ingredients = [c["name"] for c in candidates if c.get("confidence", 0) >= 0.5]
                ctx["available_ingredients"] = list(set(existing + new_ingredients))
                orchestrator.state["freestyle_context"] = ctx
                orchestrator.state["browse_session"] = None
                await emit_product_event("browse_completed", user["uid"], {
                    "ingredient_count": len(new_ingredients),
                })
                await persist_session_state(session_id, {"freestyle_context": ctx})
                await websocket.send_json({
                    "type": "browse_complete",
                    "ingredients": ctx["available_ingredients"],
                    "text": f"I found {len(new_ingredients)} ingredients. Ready to cook or want to browse more?",
                })

            elif event_type == "ambient_toggle":
                enabled = data.get("enabled", False)
                await orchestrator.set_ambient_mode(enabled)
                await websocket.send_json({
                    "type": "mode_update",
                    "ambient_listen": enabled,
                })
                # Persist mode settings change
                await persist_session_state(session_id, {
                    "mode_settings.ambient_listen": enabled,
                })

            elif event_type == "resume_interrupted":
                response = await orchestrator.handle_resume()
                if response:
                    await websocket.send_json(response)

            elif event_type == "session_resume":
                # Client reconnected — send current session state
                await websocket.send_json({
                    "type": "session_state",
                    "current_step": orchestrator.state.get("current_step", 1),
                    "ambient_listen": orchestrator.state.get("ambient_listen", False),
                    "last_message": f"Welcome back! You're on step {orchestrator.state.get('current_step', 1)}.",
                })
                # Re-push process bar
                if processes:
                    await push_process_bar(websocket, processes)

            elif event_type == "ping":
                await websocket.send_json({"type": "pong"})

            # Log event to Firestore events subcollection with correlation ID
            await log_session_event(session_id, event_type, {
                **data,
                "uid": user["uid"],
                "event_id": str(_uuid.uuid4()),
            })

    except WebSocketDisconnect:
        timer_system.cancel_all()
        # Persist final state for resume capability
        await persist_session_state(session_id, {
            "status": "paused",
            "current_step": orchestrator.state.get("current_step", 1),
            "calibration_state": orchestrator.calibration.to_dict(),
        })
    except Exception:
        timer_system.cancel_all()
        try:
            await websocket.send_json({
                "type": "error",
                "message": "Something went wrong. Let me try to reconnect.",
            })
        except Exception:
            pass
