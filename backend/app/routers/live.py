"""WebSocket live channel for real-time cooking sessions (Epic 4)."""

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from firebase_admin import auth as firebase_auth
from google.cloud import firestore

from app.services.firestore import db
from app.agents.orchestrator import create_session_orchestrator

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

    # Load recipe
    recipe_doc = await db.collection("recipes").document(session["recipe_id"]).get()
    recipe = recipe_doc.to_dict()

    # Initialize orchestrator
    orchestrator = await create_session_orchestrator(session, recipe)

    try:
        # Send initial greeting
        await websocket.send_json({
            "type": "buddy_message",
            "text": f"Let's cook {recipe.get('title', 'this recipe')}! "
                    "I'll walk you through it step by step.",
            "step": 1,
        })

        while True:
            data = await websocket.receive_json()
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
                if response:
                    await websocket.send_json(response)

            elif event_type == "step_complete":
                response = await orchestrator.advance_step()
                await websocket.send_json(response)

            elif event_type == "vision_check":
                frame_uri = data.get("frame_uri")
                response = await orchestrator.handle_vision_check(frame_uri)
                await websocket.send_json(response)

            elif event_type == "ambient_toggle":
                enabled = data.get("enabled", False)
                await orchestrator.set_ambient_mode(enabled)
                await websocket.send_json({
                    "type": "mode_update",
                    "ambient_listen": enabled,
                })

            elif event_type == "resume_interrupted":
                response = await orchestrator.handle_resume()
                if response:
                    await websocket.send_json(response)

            elif event_type == "ping":
                await websocket.send_json({"type": "pong"})

            # Log event to Firestore events subcollection
            await db.collection("sessions").document(session_id) \
                .collection("events").add({
                    "type": event_type,
                    "timestamp": firestore.SERVER_TIMESTAMP,
                    "payload": data,
                    "uid": user["uid"],
                })

    except WebSocketDisconnect:
        await db.collection("sessions").document(session_id).update({
            "status": "paused",
        })
    except Exception:
        try:
            await websocket.send_json({
                "type": "error",
                "message": "Something went wrong. Let me try to reconnect.",
            })
        except Exception:
            pass
