"""Gemini Live audio session for real-time bidirectional audio streaming (Epic 4)."""

import asyncio
import base64
from typing import Optional

from google.genai import types

from app.services.gemini import gemini_client, MODEL_LIVE


class LiveAudioSession:
    """Manages a Gemini Live audio session for a cooking companion."""

    def __init__(self, recipe: dict, session_state: dict):
        self.recipe = recipe
        self.session_state = session_state
        self.live_session = None
        self.response_queue: asyncio.Queue = asyncio.Queue()

    async def connect(self):
        """Establish Gemini Live connection with recipe-aware system instruction."""
        steps_text = "\n".join(
            f"Step {s.get('step_number', i+1)}: {s.get('instruction', '')}"
            for i, s in enumerate(self.recipe.get("steps", []))
        )

        self.live_session = await gemini_client.aio.live.connect(
            model=MODEL_LIVE,
            config=types.LiveConnectConfig(
                response_modalities=["AUDIO"],
                system_instruction=f"""You are Ratatouille, a warm cooking buddy — an experienced
home-cook friend, NOT a chef instructor or generic AI assistant.

You're helping cook: {self.recipe.get('title', 'a recipe')}

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
                tools=[],
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
        """Close the Live session cleanly."""
        if self.live_session:
            try:
                await self.live_session.send(
                    input=types.LiveClientContent(turn_complete=True)
                )
            except Exception:
                pass
            self.live_session = None
