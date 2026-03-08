"""Tests for Epic 6 — Guide Image Generator (Task 6.4)."""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch


class TestGuideImageGenerator:
    def test_importable(self):
        from app.agents.guide_image import GuideImageGenerator
        assert GuideImageGenerator is not None

    def test_constructor(self):
        from app.agents.guide_image import GuideImageGenerator
        gen = GuideImageGenerator("session-1", "Aglio e Olio")
        assert gen.session_id == "session-1"
        assert gen.recipe_title == "Aglio e Olio"
        assert gen._chat is None  # Lazy init

    @pytest.mark.asyncio
    async def test_generate_guide_success(self):
        from app.agents.guide_image import GuideImageGenerator

        gen = GuideImageGenerator("session-1", "Aglio e Olio")

        # Mock chat response with image + text
        mock_image_part = MagicMock()
        mock_image_part.inline_data = MagicMock(data=b"fake-png-bytes")
        mock_image_part.text = None

        mock_text_part = MagicMock()
        mock_text_part.inline_data = None
        mock_text_part.text = "- Edges are light golden\n- Oil sheen visible"

        mock_response = MagicMock()
        mock_response.candidates = [MagicMock(content=MagicMock(parts=[mock_image_part, mock_text_part]))]

        mock_chat = MagicMock()
        mock_chat.send_message.return_value = mock_response

        # Mock Firestore
        mock_guide_doc = MagicMock()
        mock_guide_doc.set = AsyncMock()
        mock_guide_col = MagicMock()
        mock_guide_col.document.return_value = mock_guide_doc
        mock_session_doc = MagicMock()
        mock_session_doc.collection.return_value = mock_guide_col
        mock_sessions_col = MagicMock()
        mock_sessions_col.document.return_value = mock_session_doc

        step = {
            "step_number": 4,
            "instruction": "Saute garlic until light golden",
            "recipe_id": "r1",
        }

        with patch.object(gen, "_get_chat", return_value=mock_chat), \
             patch("app.agents.guide_image.upload_bytes", return_value="gs://bucket/guide.png"), \
             patch("app.agents.guide_image.get_signed_url", return_value="https://signed-url/guide.png"), \
             patch("app.agents.guide_image.db") as mock_db:
            mock_db.collection.return_value = mock_sessions_col

            result = await gen.generate_guide(step, "light_golden")

        assert "guide_id" in result
        assert result["image_url"] == "https://signed-url/guide.png"
        assert result["stage_label"] == "light_golden"
        assert len(result["cue_overlays"]) == 2
        assert "golden" in result["cue_overlays"][0].lower()

    @pytest.mark.asyncio
    async def test_generate_guide_no_image(self):
        from app.agents.guide_image import GuideImageGenerator

        gen = GuideImageGenerator("session-1", "Test")

        # Response with no image
        mock_text_part = MagicMock()
        mock_text_part.inline_data = None
        mock_text_part.text = "Sorry, I couldn't generate an image."

        mock_response = MagicMock()
        mock_response.candidates = [MagicMock(content=MagicMock(parts=[mock_text_part]))]

        mock_chat = MagicMock()
        mock_chat.send_message.return_value = mock_response

        step = {"step_number": 1, "instruction": "Test step"}

        with patch.object(gen, "_get_chat", return_value=mock_chat):
            result = await gen.generate_guide(step, "target")

        assert "error" in result

    @pytest.mark.asyncio
    async def test_generate_guide_uses_custom_prompt(self):
        from app.agents.guide_image import GuideImageGenerator

        gen = GuideImageGenerator("session-1", "Test")

        mock_image_part = MagicMock()
        mock_image_part.inline_data = MagicMock(data=b"png")
        mock_image_part.text = None

        mock_text_part = MagicMock()
        mock_text_part.inline_data = None
        mock_text_part.text = "- Cue 1"

        mock_response = MagicMock()
        mock_response.candidates = [MagicMock(content=MagicMock(parts=[mock_image_part, mock_text_part]))]

        mock_chat = MagicMock()
        mock_chat.send_message.return_value = mock_response

        step = {
            "step_number": 1,
            "instruction": "Cook pasta",
            "guide_image_prompt": "Show al dente pasta with slight bite",
            "recipe_id": "r1",
        }

        mock_doc = MagicMock()
        mock_doc.set = AsyncMock()
        mock_col = MagicMock()
        mock_col.document.return_value = mock_doc
        mock_session = MagicMock()
        mock_session.collection.return_value = mock_col
        mock_sessions = MagicMock()
        mock_sessions.document.return_value = mock_session

        with patch.object(gen, "_get_chat", return_value=mock_chat), \
             patch("app.agents.guide_image.upload_bytes", return_value="gs://b/g.png"), \
             patch("app.agents.guide_image.get_signed_url", return_value="https://url"), \
             patch("app.agents.guide_image.db") as mock_db:
            mock_db.collection.return_value = mock_sessions

            result = await gen.generate_guide(step, "al_dente")

        # Verify custom prompt was used
        call_args = mock_chat.send_message.call_args[0][0]
        assert "al dente" in call_args.lower()
        assert result["stage_label"] == "al_dente"
