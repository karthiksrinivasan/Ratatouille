"""Live browse service for fridge/pantry ingredient discovery (Epic 9, Task 9.11).

Processes video frames during a live browse session, detecting ingredients
incrementally and building a candidate list.
"""

import json
import logging
from typing import Optional

from app.services.gemini import gemini_client, MODEL_FLASH

logger = logging.getLogger("ratatouille.browse")


class BrowseSession:
    """Tracks state for a single fridge/pantry live browse session."""

    def __init__(self, source: str = "fridge"):
        self.source = source  # fridge | pantry
        self.frame_count = 0
        self.candidates: list[dict] = []
        self._seen_names: set[str] = set()

    async def process_frame(self, frame_uri: str) -> dict:
        """Process a single frame and return observation + new candidates.

        Returns dict with keys: observation, confidence, candidates (new only), question.
        """
        self.frame_count += 1

        try:
            response = await gemini_client.aio.models.generate_content(
                model=MODEL_FLASH,
                contents=[
                    {
                        "role": "user",
                        "parts": [
                            {"text": (
                                f"You are scanning a {self.source}. "
                                "List every food item you can identify. "
                                "Return JSON: {\"observation\": \"...\", "
                                "\"items\": [{\"name\": \"...\", \"confidence\": 0.0-1.0}], "
                                "\"question\": \"...\" or null}"
                            )},
                            {"file_data": {"file_uri": frame_uri, "mime_type": "image/jpeg"}},
                        ],
                    }
                ],
            )
            text = response.text.strip()
            if text.startswith("```"):
                text = text.split("\n", 1)[1].rsplit("```", 1)[0].strip()
            parsed = json.loads(text)
        except Exception as e:
            logger.warning(f"Browse frame analysis failed: {e}")
            return self._fallback_observation()

        observation = parsed.get("observation", "I can see some items.")
        items = parsed.get("items", [])
        question = parsed.get("question")

        # Deduplicate and add new candidates
        new_candidates = []
        for item in items:
            name = item.get("name", "").lower().strip()
            if name and name not in self._seen_names:
                self._seen_names.add(name)
                candidate = {
                    "name": name,
                    "confidence": item.get("confidence", 0.5),
                    "source": self.source,
                    "frame_number": self.frame_count,
                }
                self.candidates.append(candidate)
                new_candidates.append(candidate)

        # Determine overall confidence
        avg_confidence = (
            sum(c.get("confidence", 0.5) for c in new_candidates) / len(new_candidates)
            if new_candidates else 0.5
        )

        return {
            "observation": observation,
            "confidence": round(avg_confidence, 2),
            "candidates": new_candidates,
            "question": question,
        }

    def _fallback_observation(self) -> dict:
        """Fallback when Gemini analysis fails — ask for better view or verbal confirmation."""
        return {
            "observation": "I'm having trouble seeing clearly. Could you hold the camera steady or tell me what you see?",
            "confidence": 0.0,
            "candidates": [],
            "question": "Can you tell me what's in there, or try a still photo?",
        }

    def get_all_candidates(self) -> list[dict]:
        """Return all accumulated ingredient candidates."""
        return list(self.candidates)
