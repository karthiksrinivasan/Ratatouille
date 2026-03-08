"""Session orchestrator — central AI agent for cooking sessions (Epic 4)."""

import json
from typing import Optional

from google.adk.agents import Agent
from google.adk.tools import FunctionTool, ToolContext

from app.services.gemini import MODEL_FLASH
from app.agents.voice_modes import VoiceModeManager
from app.agents.calibration import CalibrationEngine
from app.agents.degradation import DegradationManager


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
        "title": recipe.get("title", ""),
        "total_steps": len(recipe.get("steps", [])),
        "current_step": tool_context.state["current_step"],
        "ingredients": recipe.get("ingredients", []),
    })


class SessionOrchestrator:
    """Wraps ADK Agent with session-aware methods for the WebSocket loop."""

    def __init__(self, agent: Agent, session_state: dict):
        self.agent = agent
        self.state = session_state
        self.voice_mode = VoiceModeManager()
        self.voice_mode.ambient_enabled = session_state.get("ambient_listen", False)
        # Restore calibration from session state or create new
        cal_data = session_state.get("calibration_state")
        if cal_data and isinstance(cal_data, dict) and cal_data.get("global_level"):
            self.calibration = CalibrationEngine.from_dict(cal_data)
        else:
            self.calibration = CalibrationEngine()
        self.degradation = DegradationManager()

    async def handle_voice_query(self, text: str) -> dict:
        """Handle an active voice query from the user."""
        from google.adk.runners import InMemoryRunner
        from google.genai import types

        # Detect and process calibration signals
        signal = self.calibration.detect_signal_from_text(text)
        if signal:
            current_step_data = self._get_current_step_data()
            technique = None
            if current_step_data:
                tags = current_step_data.get("technique_tags", [])
                technique = tags[0] if tags else None
            self.calibration.process_signal(signal, technique)

        # Update calibration level in state for agent instruction templating
        self.state["calibration_level"] = self.calibration.get_level()

        # Check for critical moment override (CA-04)
        current_step_data = self._get_current_step_data()
        if current_step_data and self.calibration.is_critical_moment(current_step_data):
            self.state["calibration_level"] = "detailed"

        runner = InMemoryRunner(agent=self.agent, app_name="ratatouille")
        session = await runner.session_service.create_session(
            app_name="ratatouille",
            user_id=self.state.get("uid", "user"),
            state=self.state,
        )

        response_text = ""
        async for event in runner.run_async(
            session_id=session.id,
            new_message=types.Content(
                parts=[types.Part(text=text)],
                role="user",
            ),
        ):
            if event.content and event.content.parts:
                for part in event.content.parts:
                    if part.text:
                        response_text += part.text

        self.voice_mode.start_speaking(response_text)
        return {
            "text": response_text or "I'm here — what do you need?",
            "current_step": self.state.get("current_step", 1),
        }

    def _get_current_step_data(self) -> Optional[dict]:
        """Get the current step dict from recipe."""
        recipe = self.state.get("recipe", {})
        steps = recipe.get("steps", [])
        current = self.state.get("current_step", 1)
        if 0 < current <= len(steps):
            return steps[current - 1]
        return None

    async def handle_audio_chunk(self, audio_base64: Optional[str]) -> Optional[dict]:
        """Handle raw audio chunk — delegates to Gemini Live (Epic 4.5)."""
        if not audio_base64:
            return None
        # Placeholder: Gemini Live integration in task 4.5
        return None

    async def advance_step(self) -> dict:
        """Advance to the next cooking step."""
        current = self.state.get("current_step", 1)
        recipe = self.state.get("recipe", {})
        steps = recipe.get("steps", [])
        total = len(steps)

        if current < total:
            self.state["current_step"] = current + 1
            new_step = steps[current]
            return {
                "type": "buddy_message",
                "text": f"Step {current + 1}: {new_step.get('instruction', 'Next step')}",
                "step": current + 1,
            }
        return {
            "type": "buddy_message",
            "text": "That's all the steps — you did it! Time to plate up.",
            "step": current,
        }

    async def handle_vision_check(self, frame_uri: Optional[str]) -> dict:
        """Handle vision check — routed to VisionAssessor (Epic 6)."""
        if not self.degradation.vision_available:
            step_data = self._get_current_step_data() or {}
            return {
                "type": "vision_result",
                "confidence": "unavailable",
                "assessment": self.degradation.get_vision_fallback_text(step_data),
            }
        # Vision assessor will be implemented in Epic 6
        return {
            "type": "vision_result",
            "confidence": "pending",
            "assessment": "Vision assessment will be available in a future update.",
        }

    async def set_ambient_mode(self, enabled: bool):
        """Toggle ambient listening mode."""
        self.state["ambient_listen"] = enabled
        self.voice_mode.ambient_enabled = enabled

    def classify_input(self, event_type: str, text: str = "") -> str:
        """Classify input into voice mode (VM-01 through VM-04)."""
        return self.voice_mode.classify_input(event_type, text)

    def should_respond_ambient(self, transcript: str) -> bool:
        """Check if ambient input is cooking-relevant and warrants a response."""
        return self.voice_mode.should_respond_ambient(transcript)

    async def handle_barge_in(self, text: str) -> list:
        """Handle barge-in interruption (VM-04)."""
        interrupted_preview = self.voice_mode.interrupt()
        messages = []

        # Notify client to stop playback
        messages.append({
            "type": "buddy_interrupted",
            "interrupted_text": interrupted_preview or "",
            "resumable": interrupted_preview is not None,
        })

        # Handle the new user intent
        response = await self.handle_voice_query(text)
        messages.append({
            "type": "buddy_response",
            "text": response["text"],
            "step": response.get("current_step"),
        })
        return messages

    async def handle_resume(self) -> Optional[dict]:
        """Resume interrupted response with concise summary."""
        interrupted = self.voice_mode.consume_interrupted()
        if not interrupted:
            return {
                "type": "buddy_response",
                "text": "Nothing to resume — what do you need?",
                "step": self.state.get("current_step", 1),
            }
        summary = await self.handle_voice_query(
            f"Briefly summarize what you were saying: {interrupted}"
        )
        return summary

    def get_mode_state(self) -> dict:
        """Return current mode state for client UI."""
        return self.voice_mode.get_mode_state()


ORCHESTRATOR_INSTRUCTION = """You are Ratatouille, a warm and knowledgeable cooking buddy.
You are guiding the user through cooking {recipe_title}.

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
- Do NOT repeat the interrupted content unless they ask
- If they ask to resume, give a CONCISE summary, not the full repeat

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
the vision check feature or generate a guide image for comparison."""


async def create_session_orchestrator(session: dict, recipe: dict) -> SessionOrchestrator:
    """Create and initialize the session orchestrator agent."""
    session_state = {
        "recipe": recipe,
        "recipe_title": recipe.get("title", "this recipe"),
        "current_step": session.get("current_step", 1),
        "total_steps": len(recipe.get("steps", [])),
        "ambient_listen": session.get("mode_settings", {}).get("ambient_listen", False),
        "calibration_level": "standard",
        "uid": session.get("uid", ""),
        "session_id": session.get("session_id", ""),
    }

    agent = Agent(
        model=MODEL_FLASH,
        name="session_orchestrator",
        instruction=ORCHESTRATOR_INSTRUCTION,
        tools=[
            FunctionTool(get_current_step),
            FunctionTool(advance_to_next_step),
            FunctionTool(get_recipe_context),
        ],
    )

    return SessionOrchestrator(agent=agent, session_state=session_state)
