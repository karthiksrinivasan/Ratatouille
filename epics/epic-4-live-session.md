# Epic 4: Live Cooking Session & Voice Loop

## Goal

The core product experience — a real-time, voice-primary cooking companion. User starts a session, interacts via voice (and optional camera), and receives adaptive step-by-step guidance through a WebSocket connection backed by Gemini Live.

## Prerequisites

- Epic 1 complete (Firestore, GCS, auth, Gemini client, Cloud Run)
- Epic 2 complete (recipe data model, demo recipe available)
- Coordinate with Epic 8 tasks 8.8 and 8.9 for mobile live-session UX + WS integration

## PRD References

- §7.1 Session Lifecycle
- §7.2 Multimodal Input Requirements (MI-01 through MI-04)
- §7.3 Multimodal Output Requirements (MO-01 through MO-03)
- §7.4 Voice Modes Behavior (VM-01, VM-02, VM-03, VM-04 Barge-in)
- §7.6 Calibration and Adaptation (CA-01 through CA-04)
- §10.1 `sessions` collection
- §11 AI Orchestration Design
- §12.1 REST endpoints for sessions
- §13 UX-13 Barge-in interruption handled naturally
- §14.4 Judging criteria: distinct persona, natural interruption handling
- NFR-07 Demo must include at least one barge-in and successful recovery
- §12.2 Realtime Channel
- NFR-01 Voice p95 <= 1.8s
- NFR-02 Graceful degradation to voice-only

## Tech Guide References

- §1 Vertex AI — Gemini Live API (real-time streaming)
- §2 ADK — Agent, tools, state, multi-agent
- §10 Cloud Run — WebSocket support

---

## Data Model

### Pydantic Models — `app/models/session.py`

```python
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
import uuid

class ModeSettings(BaseModel):
    ambient_listen: bool = False      # Opt-in per session
    phone_position: str = "counter"   # "counter" | "mounted" | "held"

class SessionCreate(BaseModel):
    recipe_id: str
    mode_settings: Optional[ModeSettings] = None

class Session(BaseModel):
    session_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    uid: str
    recipe_id: str
    status: str = "created"           # created | active | paused | completed | abandoned
    mode_settings: ModeSettings = ModeSettings()
    current_step: int = 0
    calibration_state: dict = {}      # Per-technique guidance level
    started_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)

class SessionEvent(BaseModel):
    event_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    type: str                          # voice_query | vision_check | step_complete | timer_alert | etc.
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    payload: dict = {}
```

---

## Model Routing Table

| Scenario | Model | Why |
|----------|-------|-----|
| Real-time voice conversation | `gemini-live-2.5-flash-preview-native-audio` | Bidirectional audio streaming |
| Step guidance generation | `gemini-2.5-flash` | Fast text generation |
| Vision assessment | `gemini-2.5-flash` | Image analysis with confidence |
| Guide image generation | `gemini-2.0-flash-preview-image-generation` | Visual target-state output |
| Complex reasoning (optional) | `gemini-2.5-pro` | Only when Flash can't handle it |

---

## Tasks

### 4.1 Session Creation Endpoint

**What:** Create a session record linked to a recipe. Validates recipe exists and user has access.

**Endpoint:** `POST /v1/sessions`

```python
from fastapi import APIRouter, Depends, HTTPException
from app.auth.firebase import get_current_user
from app.services.firestore import db
from app.services.sessions import create_session_record
from google.cloud import firestore
import uuid

router = APIRouter()

@router.post("/sessions")
async def create_session(
    body: SessionCreate,
    user: dict = Depends(get_current_user),
):
    uid = user["uid"]

    # Verify recipe exists
    recipe_doc = await db.collection("recipes").document(body.recipe_id).get()
    if not recipe_doc.exists:
        raise HTTPException(404, "Recipe not found")

    return await create_session_record(
        uid=uid,
        recipe_id=body.recipe_id,
        mode_settings=(body.mode_settings or ModeSettings()).model_dump(),
    )
```

**Shared service contract (`app/services/sessions.py`):**
```python
async def create_session_record(uid: str, recipe_id: str, mode_settings: dict | None = None) -> dict:
    """Create and persist session; reusable by both session router and scan flow."""
    ...
```

**Acceptance Criteria:**
- [ ] Session created in Firestore with status `created`
- [ ] Recipe existence validated
- [ ] Mode settings stored (ambient listen opt-in, phone position)
- [ ] Returns session_id
- [ ] Shared `create_session_record(...)` service callable from Epic 3 start-session bridge

---

### 4.2 Session Activation Endpoint

**What:** Transitions session from `created` to `active`. This is the "Start Cooking" moment. Loads recipe into session context.

**Endpoint:** `POST /v1/sessions/{session_id}/activate`

```python
@router.post("/sessions/{session_id}/activate")
async def activate_session(
    session_id: str,
    user: dict = Depends(get_current_user),
):
    session_doc = await db.collection("sessions").document(session_id).get()
    if not session_doc.exists:
        raise HTTPException(404, "Session not found")
    session = session_doc.to_dict()
    if session["uid"] != user["uid"]:
        raise HTTPException(403)
    if session["status"] != "created":
        raise HTTPException(400, f"Session is already {session['status']}")

    # Load recipe for session context
    recipe_doc = await db.collection("recipes").document(session["recipe_id"]).get()
    recipe = recipe_doc.to_dict()

    # Initialize process entries for each step (Epic 5 populates fully)
    # Set first step as active
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
```

**Acceptance Criteria:**
- [ ] Status transitions from `created` to `active`
- [ ] Recipe data loaded and returned to client
- [ ] WebSocket URL provided for live connection
- [ ] `started_at` timestamp set

---

### 4.3 WebSocket Live Channel

**What:** Bi-directional WebSocket endpoint for real-time voice events, process updates, and buddy outputs.

**Endpoint:** `WS /v1/live/{session_id}`

**Implementation:** `app/routers/live.py`

```python
from fastapi import WebSocket, WebSocketDisconnect
from app.services.firestore import db
from app.agents.orchestrator import create_session_orchestrator
from firebase_admin import auth as firebase_auth
from google.cloud import firestore
import json

async def authenticate_websocket(websocket: WebSocket) -> dict | None:
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

    # Initialize orchestrator with Gemini Live
    orchestrator = await create_session_orchestrator(session, recipe)

    try:
        # Send initial greeting
        await websocket.send_json({
            "type": "buddy_message",
            "text": f"Let's cook {recipe['title']}! I'll walk you through it step by step.",
            "step": 1,
        })

        while True:
            # Receive client events
            data = await websocket.receive_json()
            event_type = data.get("type")

            if event_type == "voice_query":
                # Active Query mode — user asked something
                response = await orchestrator.handle_voice_query(data.get("text", ""))
                await websocket.send_json({
                    "type": "buddy_response",
                    "text": response["text"],
                    "audio_hint": response.get("audio_hint"),
                    "step": response.get("current_step"),
                })

            elif event_type == "voice_audio":
                # Raw audio chunk for Gemini Live
                audio_data = data.get("audio")  # base64 encoded PCM
                response = await orchestrator.handle_audio_chunk(audio_data)
                if response:
                    await websocket.send_json(response)

            elif event_type == "step_complete":
                # User confirmed step done
                response = await orchestrator.advance_step()
                await websocket.send_json(response)

            elif event_type == "vision_check":
                # Handled by Epic 6, routed through orchestrator
                frame_uri = data.get("frame_uri")
                response = await orchestrator.handle_vision_check(frame_uri)
                await websocket.send_json(response)

            elif event_type == "ambient_toggle":
                # Toggle ambient listen mode
                enabled = data.get("enabled", False)
                await orchestrator.set_ambient_mode(enabled)
                await websocket.send_json({
                    "type": "mode_update",
                    "ambient_listen": enabled,
                })

            elif event_type == "ping":
                await websocket.send_json({"type": "pong"})

            # Log event to Firestore
            await db.collection("sessions").document(session_id) \
                .collection("events").add({
                    "type": event_type,
                    "timestamp": firestore.SERVER_TIMESTAMP,
                    "payload": data,
                    "uid": user["uid"],
                })

    except WebSocketDisconnect:
        # Client disconnected — mark session for potential resume
        await db.collection("sessions").document(session_id).update({
            "status": "paused",
        })
    except Exception as e:
        await websocket.send_json({
            "type": "error",
            "message": "Something went wrong. Let me try to reconnect.",
        })
```

**WebSocket Message Protocol:**

Client → Server:
```json
{"type": "voice_query", "text": "How do I know when the garlic is done?"}
{"type": "voice_audio", "audio": "<base64 PCM>"}
{"type": "barge_in", "text": "Wait, actually—"}
{"type": "step_complete", "step": 3}
{"type": "vision_check", "frame_uri": "gs://..."}
{"type": "ambient_toggle", "enabled": true}
{"type": "resume_interrupted"}
{"type": "ping"}
```

Server → Client:
```json
{"type": "buddy_message", "text": "...", "step": 1}
{"type": "buddy_response", "text": "...", "audio_url": "...", "step": 4}
{"type": "buddy_interrupted", "interrupted_text": "...", "resumable": true}
{"type": "process_update", "processes": [...]}
{"type": "timer_alert", "process_id": "...", "priority": "P0"}
{"type": "vision_result", "confidence": "high", "assessment": "..."}
{"type": "guide_image", "image_url": "...", "cues": [...]}
{"type": "mode_update", "ambient_listen": true}
{"type": "error", "message": "..."}
{"type": "pong"}
```

**Acceptance Criteria:**
- [ ] WebSocket connects and maintains persistent connection
- [ ] Firebase auth token required before any event is processed
- [ ] Session ownership validated (`session.uid` must match token `uid`)
- [ ] Handles voice_query, step_complete, vision_check, ambient_toggle events
- [ ] Sends buddy_message, process_update, timer_alert events
- [ ] Disconnection sets session status to `paused`
- [ ] All events logged to Firestore events subcollection
- [ ] Process bar updates push within 500ms (NFR-01)

---

### 4.4 Session Orchestrator Agent (ADK)

**What:** The central AI agent that manages the cooking session. Routes queries, maintains step context, composes responses, and delegates to specialist agents.

**Implementation:** `app/agents/orchestrator.py`

```python
from google.adk.agents import Agent
from google.adk.tools import FunctionTool, ToolContext
from app.services.gemini import MODEL_FLASH

def get_current_step(tool_context: ToolContext) -> str:
    """Get the current cooking step details."""
    recipe = tool_context.state["recipe"]
    current = tool_context.state["current_step"]
    steps = recipe.get("steps", [])
    if 0 < current <= len(steps):
        step = steps[current - 1]
        return json.dumps(step)
    return json.dumps({"error": "No current step"})

def advance_to_next_step(tool_context: ToolContext) -> str:
    """Move to the next cooking step."""
    current = tool_context.state["current_step"]
    recipe = tool_context.state["recipe"]
    total = len(recipe.get("steps", []))
    if current < total:
        tool_context.state["current_step"] = current + 1
        new_step = recipe["steps"][current]
        return json.dumps({"new_step": new_step, "step_number": current + 1})
    return json.dumps({"status": "all_steps_complete"})

def get_recipe_context(tool_context: ToolContext) -> str:
    """Get full recipe context for answering questions."""
    recipe = tool_context.state["recipe"]
    return json.dumps({
        "title": recipe["title"],
        "total_steps": len(recipe.get("steps", [])),
        "current_step": tool_context.state["current_step"],
        "ingredients": recipe.get("ingredients", []),
    })

async def create_session_orchestrator(session: dict, recipe: dict) -> Agent:
    orchestrator = Agent(
        model=MODEL_FLASH,
        name="session_orchestrator",
        instruction="""You are Ratatouille, a warm and knowledgeable cooking buddy.
You are guiding {user_name} through cooking {recipe_title}.

Current step: {current_step} of {total_steps}
Ambient listen: {ambient_listen}

## Your Persona (MAINTAIN CONSISTENTLY — this is judged)
You are an experienced home-cook friend — NOT a professional chef, NOT a
robotic assistant, NOT a recipe-reading machine. Think of the friend who's
cooked this dish fifty times and is hanging out in your kitchen.
- Warm, calm, lightly humorous (dry wit, not corny)
- Uses casual contractions ("you'll", "that's", "don't worry")
- Occasionally uses food-lover language ("oh, that smell is gorgeous")
- NEVER uses corporate/assistant phrasing ("I'd be happy to help", "Certainly!")
- NEVER breaks character into a generic AI assistant
- Calm urgency for safety moments — firm but not panicky
- Encouraging without being patronizing ("nice work" not "great job!")

## Interruption Handling (Barge-in — VM-04)
If the user interrupts you mid-response:
- STOP your current output immediately
- Acknowledge briefly ("Sure—" / "Got it—" / "Yep—")
- Handle their new intent FIRST
- Do NOT repeat the interrupted content unless they ask ("continue", "what were you saying", "repeat quickly")
- If they ask to resume, give a CONCISE summary of what you were saying, not the full repeat

## Guidance Rules
- Give one instruction at a time
- Mention timing explicitly ("about 3 minutes", "until golden")
- If the user seems experienced (skips, says "I know"), compress guidance
- If the user asks "why", expand with brief technique explanation
- For critical moments (burning risk, overcooking), use alert tone
- Always reference sensory cues: sight, sound, smell, touch

Current calibration level: {calibration_level}
- "detailed": full step-by-step with technique tips
- "standard": clear instructions, moderate detail
- "compressed": brief cues, assume familiarity

When the user asks about doneness or "does this look right", suggest using
the vision check feature or generate a guide image for comparison.""",
        tools=[
            FunctionTool(get_current_step),
            FunctionTool(advance_to_next_step),
            FunctionTool(get_recipe_context),
        ],
    )

    # Initialize state
    orchestrator.state = {
        "recipe": recipe,
        "recipe_title": recipe["title"],
        "current_step": session.get("current_step", 1),
        "total_steps": len(recipe.get("steps", [])),
        "ambient_listen": session.get("mode_settings", {}).get("ambient_listen", False),
        "user_name": "there",  # Updated from user profile
        "calibration_level": "standard",
    }

    return orchestrator
```

**Design Notes:**
- Uses ADK `Agent` with state templating (`{recipe_title}`, `{current_step}`, etc.)
- Tools provide structured access to recipe state
- Calibration level adjusts dynamically based on user signals (Task 4.7)
- Sub-agents for vision, taste, recovery are delegated via Epic 5 and 6

**Acceptance Criteria:**
- [ ] Agent initializes with recipe and session context
- [ ] Responds to queries with step-aware guidance
- [ ] Can advance through steps
- [ ] Personality is consistent: warm, casual, experienced friend — never breaks into generic AI assistant
- [ ] Never uses corporate phrasing ("I'd be happy to help", "Certainly!")
- [ ] Barge-in interruptions handled: stops current output, handles new intent first
- [ ] Interrupted responses resumable on "continue" / "repeat quickly"
- [ ] Calibration level affects response verbosity

---

### 4.5 Gemini Live Audio Integration

**What:** Connect the orchestrator to Gemini Live for real-time bidirectional audio streaming.

**Implementation:** `app/agents/live_audio.py`

```python
from google.genai import types
from app.services.gemini import gemini_client, MODEL_LIVE
import asyncio
import base64

class LiveAudioSession:
    """Manages a Gemini Live audio session for a cooking companion."""

    def __init__(self, recipe: dict, session_state: dict):
        self.recipe = recipe
        self.session_state = session_state
        self.live_session = None
        self.response_queue = asyncio.Queue()

    async def connect(self):
        """Establish Gemini Live connection."""
        steps_text = "\n".join(
            f"Step {s['step_number']}: {s['instruction']}"
            for s in self.recipe.get("steps", [])
        )

        self.live_session = await gemini_client.aio.live.connect(
            model=MODEL_LIVE,
            config=types.LiveConnectConfig(
                response_modalities=["AUDIO"],
                system_instruction=f"""You are Ratatouille, a warm cooking buddy — an experienced
home-cook friend, NOT a chef instructor or generic AI assistant.

You're helping cook: {self.recipe['title']}

Recipe steps:
{steps_text}

Current step: {self.session_state.get('current_step', 1)}

PERSONA (maintain consistently):
- Casual, warm, lightly witty. Use contractions ("you'll", "that's").
- NEVER say "I'd be happy to help", "Certainly!", or any corporate assistant phrasing.
- Think: friend who's cooked this fifty times, hanging out in your kitchen.

BARGE-IN: If the user interrupts you, stop immediately. Acknowledge briefly
("Sure—", "Got it—"), then handle their new question. Only resume your
previous point if they ask ("continue", "go on", "what were you saying").

Keep responses SHORT (1-2 sentences). This is a noisy kitchen.
Be warm but efficient. Use sensory cues (look for golden color, listen for sizzle).
If something sounds urgent (smoke, burning smell mentioned), respond with calm urgency.""",
                tools=[],  # Tool use via orchestrator, not Live directly
            ),
        )

    async def send_audio(self, audio_base64: str):
        """Send audio chunk to Gemini Live."""
        if not self.live_session:
            return

        audio_bytes = base64.b64decode(audio_base64)
        await self.live_session.send(input=types.LiveClientContent(
            turns=[types.Content(parts=[
                types.Part(inline_data=types.Blob(
                    data=audio_bytes,
                    mime_type="audio/pcm",
                )),
            ])]
        ))

    async def receive_responses(self):
        """Generator that yields audio responses from Gemini Live."""
        if not self.live_session:
            return

        async for msg in self.live_session.receive():
            if msg.server_content and msg.server_content.model_turn:
                for part in msg.server_content.model_turn.parts:
                    if part.inline_data:
                        yield {
                            "type": "audio_response",
                            "audio": base64.b64encode(part.inline_data.data).decode(),
                            "mime_type": part.inline_data.mime_type,
                        }
                    elif part.text:
                        yield {
                            "type": "text_response",
                            "text": part.text,
                        }

    async def close(self):
        """Close the Live session."""
        if self.live_session:
            await self.live_session.send(
                input=types.LiveClientContent(turn_complete=True)
            )
```

**Acceptance Criteria:**
- [ ] Gemini Live session establishes with recipe-aware system instruction
- [ ] Audio chunks sent and responses received bidirectionally
- [ ] Responses streamed back to WebSocket client
- [ ] Session closes cleanly on disconnect
- [ ] p95 voice response start <= 1.8s

---

### 4.6 Voice Modes & Barge-in Implementation

**What:** Implement the four voice modes defined in PRD §7.4, including VM-04 barge-in interruption handling.

**Mode behaviors:**

| Mode | Trigger | Behavior |
|------|---------|----------|
| VM-01 Ambient Listen | Session opt-in toggle | Passively listens, responds to cooking-related speech. Visible indicator required. No ambient audio persisted. |
| VM-02 Active Query | Tap or wake word | Direct question → fast response. Highest priority. |
| VM-03 Vision Check | "Look at this" or tap | Captures frame, sends to VisionAssessor, returns confidence-based response. |
| VM-04 Barge-in | User speaks while buddy is responding | Buddy stops current output, acknowledges, handles new intent first. Interrupted content resumable on request. |

**Implementation in orchestrator:**

```python
class VoiceModeManager:
    def __init__(self):
        self.ambient_enabled = False
        self.active_query_in_progress = False
        self.buddy_speaking = False
        self.last_interrupted_response: str | None = None  # Stash for resume

    def classify_input(self, event_type: str, text: str = "") -> str:
        """Determine which voice mode to handle the input with."""
        # VM-04: If buddy is currently speaking and user sends input, it's a barge-in
        if self.buddy_speaking and event_type in ("voice_query", "voice_audio", "barge_in"):
            return "VM-04"
        if event_type == "vision_check":
            return "VM-03"
        if event_type == "voice_query":
            return "VM-02"
        if event_type == "voice_audio" and self.ambient_enabled:
            return "VM-01"
        return "VM-02"  # Default to active query

    def should_respond_ambient(self, transcript: str) -> bool:
        """In ambient mode, only respond to cooking-relevant speech."""
        cooking_signals = [
            "how long", "is it done", "what next", "help",
            "too hot", "burning", "ready", "timer", "step",
            "look", "check", "taste", "adjust",
        ]
        transcript_lower = transcript.lower()
        return any(signal in transcript_lower for signal in cooking_signals)

    def is_resume_request(self, text: str) -> bool:
        """Check if user is asking to resume an interrupted response."""
        resume_signals = [
            "continue", "go on", "what were you saying",
            "repeat", "repeat quickly", "you were saying",
            "finish what you", "keep going",
        ]
        return any(signal in text.lower() for signal in resume_signals)
```

**Barge-in handling in WebSocket loop:**

```python
elif event_type == "barge_in" or (
    voice_mode_manager.classify_input(event_type, data.get("text", "")) == "VM-04"
):
    # VM-04: User interrupted buddy mid-speech
    # 1. Cancel current audio/text stream
    voice_mode_manager.buddy_speaking = False

    # 2. Stash interrupted content for potential resume
    voice_mode_manager.last_interrupted_response = current_response_text

    # 3. Notify client to stop playback
    await websocket.send_json({
        "type": "buddy_interrupted",
        "interrupted_text": current_response_text[:100],  # Preview of what was interrupted
        "resumable": True,
    })

    # 4. Handle the new user intent
    new_query = data.get("text", "")
    response = await orchestrator.handle_voice_query(new_query)
    await websocket.send_json({
        "type": "buddy_response",
        "text": response["text"],
        "step": response.get("current_step"),
    })

elif event_type == "resume_interrupted":
    # User asked to resume the interrupted response
    if voice_mode_manager.last_interrupted_response:
        # Summarize rather than repeat verbatim
        summary = await orchestrator.handle_voice_query(
            f"Briefly summarize what you were saying: {voice_mode_manager.last_interrupted_response}"
        )
        await websocket.send_json({
            "type": "buddy_response",
            "text": summary["text"],
            "step": summary.get("current_step"),
        })
        voice_mode_manager.last_interrupted_response = None
```

**Acceptance Criteria:**
- [ ] Ambient Listen requires explicit opt-in per session
- [ ] Ambient mode filters non-cooking speech
- [ ] Active Query always responds
- [ ] Vision Check routes to VisionAssessor (Epic 6)
- [ ] No ambient raw media persisted (privacy requirement)
- [ ] Mode state visible to client (for UI indicator)
- [ ] **Barge-in (VM-04):** Buddy stops current output when user interrupts
- [ ] **Barge-in:** Client receives `buddy_interrupted` event to halt audio playback
- [ ] **Barge-in:** New user intent handled immediately after interruption
- [ ] **Resume:** User can say "continue" / "repeat quickly" to get concise summary of interrupted content
- [ ] **Resume:** Resumed content is summarized, not repeated verbatim
- [ ] Barge-in event logged to session events for analytics

---

### 4.7 Adaptive Calibration Engine

**What:** Tracks user skill signals and adjusts guidance verbosity dynamically.

**Implementation:**

```python
class CalibrationEngine:
    """Tracks user signals and adjusts guidance level per technique."""

    LEVELS = ["detailed", "standard", "compressed"]

    def __init__(self):
        self.global_level = "standard"
        self.technique_levels: dict[str, str] = {}  # technique_tag -> level
        self.signal_counts = {
            "clarification_asks": 0,
            "skips": 0,
            "i_know_signals": 0,
            "errors": 0,
            "why_questions": 0,
        }

    def process_signal(self, signal_type: str, technique: str = None):
        """Process a calibration signal and adjust levels."""
        self.signal_counts[signal_type] = self.signal_counts.get(signal_type, 0) + 1

        target_technique = technique or "__global__"

        if signal_type in ("skips", "i_know_signals"):
            # User knows this — compress
            self._adjust(target_technique, direction="compress")
        elif signal_type in ("clarification_asks", "why_questions"):
            # User needs more detail — expand
            self._adjust(target_technique, direction="expand")
        elif signal_type == "errors":
            # Error happened — expand for this technique
            self._adjust(target_technique, direction="expand")

    def _adjust(self, technique: str, direction: str):
        current = self.technique_levels.get(technique, self.global_level)
        idx = self.LEVELS.index(current)
        if direction == "compress" and idx < len(self.LEVELS) - 1:
            self.technique_levels[technique] = self.LEVELS[idx + 1]
        elif direction == "expand" and idx > 0:
            self.technique_levels[technique] = self.LEVELS[idx - 1]

    def get_level(self, technique: str = None) -> str:
        if technique and technique in self.technique_levels:
            return self.technique_levels[technique]
        return self.global_level

    def get_instruction_modifier(self, technique: str = None) -> str:
        level = self.get_level(technique)
        if level == "detailed":
            return "Explain this step thoroughly with technique tips and common mistakes."
        elif level == "compressed":
            return "Keep it brief — just the key action and timing."
        return "Standard detail level."
```

**Calibration signals (detected from user interactions):**
- **Clarification ask:** User says "what do you mean?" or asks follow-up → expand
- **Skip / "I know":** User says "skip", "I know", "next" quickly → compress
- **Error:** User reports mistake or system detects issue → expand for that technique
- **"Why" question:** User asks "why do we..." → expand with explanation
- **Alert override (CA-04):** In critical moments (burning risk), always use detailed mode regardless

**Acceptance Criteria:**
- [ ] Guidance level adjusts per-technique based on user signals
- [ ] Three levels: detailed, standard, compressed
- [ ] Critical moments override calibration with alert-level detail
- [ ] Calibration state persisted in session for resume
- [ ] Signal detection works from natural language input

---

### 4.8 Session State Persistence

**What:** All session state changes persisted to Firestore for resume capability and post-session analysis.

**Key state to persist:**
- `current_step` — on every step change
- `calibration_state` — on every calibration adjustment
- `mode_settings` — on ambient toggle
- `status` — on activation, pause, completion

**Implementation pattern:**
```python
async def persist_session_state(session_id: str, updates: dict):
    """Atomic update of session state fields."""
    await db.collection("sessions").document(session_id).update(updates)
```

**Event logging:**
```python
async def log_session_event(session_id: str, event_type: str, payload: dict):
    """Append event to session events subcollection."""
    await db.collection("sessions").document(session_id) \
        .collection("events").add({
            "type": event_type,
            "timestamp": firestore.SERVER_TIMESTAMP,
            "payload": payload,
        })
```

**Acceptance Criteria:**
- [ ] Session state survives WebSocket disconnection
- [ ] Session can be resumed from last known state
- [ ] All events logged for post-session analysis
- [ ] Step transitions persisted atomically

---

### 4.9 Graceful Degradation

**What:** When vision fails or audio quality is poor, degrade gracefully to voice-only or text-only modes (NFR-02).

**Degradation hierarchy:**
1. **Full multimodal** — voice + vision + process bar
2. **Voice + text** — vision unavailable, sensory fallback language
3. **Text only** — audio unavailable, full text responses via WebSocket

**Implementation:**
```python
class DegradationManager:
    def __init__(self):
        self.vision_available = True
        self.audio_available = True
        self.consecutive_vision_failures = 0
        self.consecutive_audio_failures = 0

    def report_vision_failure(self):
        self.consecutive_vision_failures += 1
        if self.consecutive_vision_failures >= 3:
            self.vision_available = False

    def report_audio_failure(self):
        self.consecutive_audio_failures += 1
        if self.consecutive_audio_failures >= 3:
            self.audio_available = False

    def get_response_modality(self) -> str:
        if self.audio_available and self.vision_available:
            return "full_multimodal"
        elif self.audio_available:
            return "voice_text"
        return "text_only"

    def get_vision_fallback_text(self, step: dict) -> str:
        """Generate sensory fallback when vision is unavailable."""
        return (
            "I can't see clearly right now. Here's what to check: "
            "Listen for a steady sizzle, smell for nuttiness not burning, "
            "and test texture with a utensil."
        )
```

**Acceptance Criteria:**
- [ ] Three consecutive vision failures switches to voice-only mode
- [ ] Three consecutive audio failures switches to text-only mode
- [ ] Degradation communicated clearly to user
- [ ] Session continues functioning in degraded mode
- [ ] Recovery attempted on each new interaction

---

### 4.10 Register Session & Live Routers

**What:** Mount session and live routers in main app.

```python
from app.routers import sessions, live
app.include_router(sessions.router, prefix="/v1", tags=["sessions"])
app.include_router(live.router, prefix="/v1", tags=["live"])
```

**Acceptance Criteria:**
- [ ] `POST /v1/sessions` creates session
- [ ] `POST /v1/sessions/{id}/activate` activates session
- [ ] `WS /v1/live/{session_id}` establishes WebSocket
- [ ] Full voice query → response loop functional
- [ ] Step advancement works through voice or explicit action

---

### 4.11 Mobile UX Implementation (Live Session)

**What:** Build live-session UX mechanics so multimodal behavior is legible and resilient on mobile.

**Required mobile UX components:**
1. Persistent ambient indicator with explicit ON/OFF state and privacy copy.
2. Clear speaking states:
   - `Listening`
   - `Buddy speaking`
   - `Interrupted`
   - `Reconnecting`
3. Barge-in UI behavior:
   - User speech instantly stops buddy playback
   - Show compact chip: `Interrupted — tap to resume summary`
4. Connection resilience UX:
   - Auto-reconnect with exponential backoff
   - Resume from latest session state after reconnect
5. Hands-busy ergonomics:
   - Large tap targets for `Next step`, `Vision check`, `Repeat quickly`
   - Minimal text density, readable at arm's length

**Acceptance Criteria:**
- [ ] Ambient privacy indicator always visible when enabled
- [ ] Barge-in visibly interrupts playback within 200ms on device
- [ ] Reconnect path restores session without forcing app restart
- [ ] Critical controls usable one-handed with wet/occupied-hand context
- [ ] Voice + UI states remain synchronized under poor network conditions

---

## Epic Completion Checklist

- [ ] Session CRUD endpoints functional
- [ ] WebSocket live channel with persistent connection
- [ ] Orchestrator agent initialized with recipe context
- [ ] Gemini Live audio streaming working bidirectionally
- [ ] Four voice modes (ambient, active, vision, barge-in) differentiated
- [ ] Barge-in interruption stops buddy output and handles new intent (VM-04)
- [ ] Interrupted responses resumable in concise form on "continue"/"repeat quickly"
- [ ] Buddy persona is distinct and consistent — never breaks into generic assistant
- [ ] Adaptive calibration adjusting guidance verbosity
- [ ] Session state persisted for resume
- [ ] Graceful degradation to voice-only and text-only
- [ ] Mobile live-session UX behavior verified (indicator, barge-in UI, reconnect/resume)
- [ ] p95 voice response start <= 1.8s
- [ ] All events logged to Firestore
