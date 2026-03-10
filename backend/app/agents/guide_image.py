"""Guide image generator — target-state visual guides via Gemini Image Gen (Epic 6, Task 6.4)."""

import asyncio
import uuid

from google.genai import types

from app.services.firestore import db
from app.services.gemini import gemini_client, MODEL_IMAGE_GEN
from app.services.storage import get_signed_url, upload_bytes


class GuideImageGenerator:
    """Generates target-state visual guides with consistent style per session."""

    # Class-level cache: session_id -> Gemini chat session for style consistency (D4.21)
    _chat_cache: dict = {}

    def __init__(self, session_id: str, recipe_title: str):
        self.session_id = session_id
        self.recipe_title = recipe_title
        # Single chat session for style consistency (per tech guide §1)
        self._chat = GuideImageGenerator._chat_cache.get(session_id)

    @classmethod
    def invalidate_cache(cls, session_id: str):
        """Remove a cached chat session (e.g. on session end)."""
        cls._chat_cache.pop(session_id, None)

    def _get_chat(self):
        """Lazily create chat session so constructor doesn't call Gemini."""
        if self._chat is None:
            self._chat = gemini_client.chats.create(
                model=MODEL_IMAGE_GEN,
                config=types.GenerateContentConfig(
                    response_modalities=["IMAGE", "TEXT"],
                    system_instruction=f"""You generate realistic food photography images
showing target cooking states for the recipe "{self.recipe_title}".

Style rules:
- Overhead or 45-degree angle kitchen photography style
- Natural lighting, clean kitchen background
- Focus on the food state described
- Consistent visual style across all images in this session
- Realistic, not stylized or cartoon
""",
                ),
            )
            # Cache for reuse across GuideImageGenerator instances with same session
            GuideImageGenerator._chat_cache[self.session_id] = self._chat
        return self._chat

    async def generate_guide(
        self,
        step: dict,
        stage_label: str,
        source_frame_uri: str = None,
    ) -> dict:
        """Generate a target-state guide image for a specific step/stage."""
        prompt = step.get("guide_image_prompt")
        if not prompt:
            prompt = f"Show the target state for: {step.get('instruction', 'this step')}"

        full_prompt = f"""Generate an image showing: {prompt}

Stage: {stage_label}
This is for step {step.get('step_number', '?')} of {self.recipe_title}.

Also provide 1-2 short text cues (max 8 words each) that describe
the key visual indicators to look for."""

        chat = self._get_chat()
        response = await asyncio.to_thread(chat.send_message, full_prompt)

        # Extract generated image and text cues
        image_bytes = None
        cue_text = ""
        for part in response.candidates[0].content.parts:
            if part.inline_data:
                image_bytes = part.inline_data.data
            elif part.text:
                cue_text = part.text

        if not image_bytes:
            return {"error": "No image generated"}

        # Upload to GCS
        recipe_id = step.get("recipe_id", "unknown")
        guide_path = f"guide-images/{recipe_id}/{step.get('step_number', 0)}/{stage_label}.png"
        guide_uri = upload_bytes(guide_path, image_bytes, "image/png")

        # Parse cues from text
        cue_overlays = [
            line.strip("- •").strip()
            for line in cue_text.split("\n")
            if line.strip()
        ][:2]

        # Persist in Firestore
        guide_id = str(uuid.uuid4())
        guide_data = {
            "guide_id": guide_id,
            "step_number": step.get("step_number"),
            "stage_label": stage_label,
            "source_frame_uri": source_frame_uri,
            "generated_guide_uri": guide_uri,
            "cue_overlays": cue_overlays,
        }

        await db.collection("sessions").document(self.session_id) \
            .collection("guide_images").document(guide_id).set(guide_data)

        # Generate signed URL for mobile display
        display_url = get_signed_url(guide_path)

        return {
            "guide_id": guide_id,
            "image_url": display_url,
            "cue_overlays": cue_overlays,
            "stage_label": stage_label,
        }
