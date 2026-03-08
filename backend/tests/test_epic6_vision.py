"""Tests for Epic 6 — Vision, Visual Guides, Taste & Recovery."""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch


# ---------------------------------------------------------------------------
# Task 6.1 — Vision assessor
# ---------------------------------------------------------------------------

class TestVisionAssessor:
    def test_imports(self):
        from app.agents.vision import assess_food_image, format_vision_response, _fallback_result
        assert callable(assess_food_image)
        assert callable(format_vision_response)
        assert callable(_fallback_result)

    def test_fallback_result(self):
        from app.agents.vision import _fallback_result
        r = _fallback_result()
        assert r["confidence"] == 0.0
        assert r["confidence_tier"] == "failed"
        assert r["sensory_fallback"]

    @pytest.mark.asyncio
    async def test_assess_food_image_success(self):
        from app.agents.vision import assess_food_image
        mock_response = MagicMock()
        mock_response.text = '{"confidence": 0.9, "confidence_tier": "high", "assessment": "Golden garlic", "is_expected_state": true, "recommendation": "Move to next step", "sensory_fallback": "Smells nutty"}'

        mock_aio = MagicMock()
        mock_aio.models.generate_content = AsyncMock(return_value=mock_response)

        with patch("app.agents.vision.gemini_client") as mock_client:
            mock_client.aio = mock_aio
            result = await assess_food_image(
                "gs://bucket/frame.jpg",
                {"step_number": 1, "instruction": "Saute garlic", "technique_tags": ["sauteing"]},
                "Aglio e Olio",
            )
        assert result["confidence"] == 0.9
        assert result["confidence_tier"] == "high"

    @pytest.mark.asyncio
    async def test_assess_food_image_json_in_codeblock(self):
        from app.agents.vision import assess_food_image
        mock_response = MagicMock()
        mock_response.text = '```json\n{"confidence": 0.5, "confidence_tier": "medium", "assessment": "Partially visible", "is_expected_state": true, "recommendation": "Keep going", "sensory_fallback": "Listen for sizzle"}\n```'

        mock_aio = MagicMock()
        mock_aio.models.generate_content = AsyncMock(return_value=mock_response)

        with patch("app.agents.vision.gemini_client") as mock_client:
            mock_client.aio = mock_aio
            result = await assess_food_image(
                "gs://bucket/frame.jpg",
                {"step_number": 2, "instruction": "Cook pasta"},
                "Pasta",
            )
        assert result["confidence_tier"] == "medium"

    @pytest.mark.asyncio
    async def test_assess_food_image_bad_response(self):
        from app.agents.vision import assess_food_image
        mock_response = MagicMock()
        mock_response.text = "This is not JSON at all"

        mock_aio = MagicMock()
        mock_aio.models.generate_content = AsyncMock(return_value=mock_response)

        with patch("app.agents.vision.gemini_client") as mock_client:
            mock_client.aio = mock_aio
            result = await assess_food_image(
                "gs://bucket/frame.jpg",
                {"step_number": 1, "instruction": "Test"},
                "Test Recipe",
            )
        assert result["confidence_tier"] == "failed"
        assert result["confidence"] == 0.0


# ---------------------------------------------------------------------------
# Task 6.2 — Confidence hierarchy response formatting
# ---------------------------------------------------------------------------

class TestConfidenceHierarchy:
    def test_high_confidence(self):
        from app.agents.vision import format_vision_response
        assessment = {
            "confidence": 0.9,
            "confidence_tier": "high",
            "assessment": "Golden brown, perfectly seared",
            "is_expected_state": True,
            "recommendation": "Move to next step",
            "sensory_fallback": "Should smell nutty",
        }
        result = format_vision_response(assessment)
        assert result["type"] == "vision_result"
        assert result["confidence"] == "high"
        assert result["tone"] == "confident"
        assert "sensory_check" not in result

    def test_medium_confidence(self):
        from app.agents.vision import format_vision_response
        assessment = {
            "confidence": 0.6,
            "confidence_tier": "medium",
            "assessment": "Looks partially cooked",
            "recommendation": "Give it another minute",
            "sensory_fallback": "Should sizzle gently",
        }
        result = format_vision_response(assessment)
        assert result["confidence"] == "medium"
        assert result["tone"] == "qualified"
        assert "not 100% sure" in result["message"]
        assert result["sensory_check"] == "Should sizzle gently"

    def test_low_confidence(self):
        from app.agents.vision import format_vision_response
        assessment = {
            "confidence": 0.3,
            "confidence_tier": "low",
            "assessment": "Can barely see",
            "recommendation": "Reposition camera",
            "sensory_fallback": "Touch test: press gently",
        }
        result = format_vision_response(assessment)
        assert result["confidence"] == "low"
        assert result["tone"] == "uncertain"
        assert "camera" in result["message"].lower()
        assert result["sensory_check"]

    def test_failed_confidence(self):
        from app.agents.vision import format_vision_response
        assessment = {
            "confidence": 0.1,
            "confidence_tier": "failed",
            "assessment": "Cannot see",
            "recommendation": "Use other senses",
            "sensory_fallback": "Smell and touch instead",
        }
        result = format_vision_response(assessment)
        assert result["confidence"] == "failed"
        assert result["tone"] == "fallback"
        assert "other senses" in result["message"].lower()
        assert result["sensory_check"]

    def test_missing_tier_defaults_to_failed(self):
        from app.agents.vision import format_vision_response
        result = format_vision_response({"assessment": "x", "recommendation": "y"})
        assert result["confidence"] == "failed"
