"""Tests for Epic 6 endpoints — vision-check, visual-guide, taste-check, recover."""

import io
import pytest
from unittest.mock import AsyncMock, MagicMock, patch


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _mock_session(uid="u1", recipe_id="r1", current_step=1):
    doc = MagicMock()
    doc.exists = True
    doc.to_dict.return_value = {
        "uid": uid,
        "recipe_id": recipe_id,
        "current_step": current_step,
        "status": "active",
    }
    return doc


def _mock_recipe():
    doc = MagicMock()
    doc.exists = True
    doc.to_dict.return_value = {
        "title": "Aglio e Olio",
        "steps": [
            {"step_number": 1, "instruction": "Saute garlic", "technique_tags": ["sauteing"]},
            {"step_number": 2, "instruction": "Cook pasta", "technique_tags": ["boiling"]},
        ],
    }
    return doc


def _mock_missing_doc():
    doc = MagicMock()
    doc.exists = False
    return doc


# ---------------------------------------------------------------------------
# Task 6.3 — Vision check endpoint
# ---------------------------------------------------------------------------

class TestVisionCheckEndpoint:
    def test_router_importable(self):
        from app.routers.vision import router
        assert router is not None

    def test_load_session_and_step_importable(self):
        from app.routers.vision import _load_session_and_step
        assert callable(_load_session_and_step)

    @pytest.mark.asyncio
    async def test_vision_check_success(self):
        from app.routers.vision import vision_check

        mock_session_doc = _mock_session()
        mock_recipe_doc = _mock_recipe()

        mock_collection = MagicMock()
        mock_doc_ref = MagicMock()
        mock_doc_ref.get = AsyncMock(side_effect=[mock_session_doc, mock_recipe_doc])
        mock_collection.document.return_value = mock_doc_ref

        # Mock event subcollection
        mock_events = MagicMock()
        mock_events.add = AsyncMock()
        mock_doc_ref.collection.return_value = mock_events

        assessment = {
            "confidence": 0.85,
            "confidence_tier": "high",
            "assessment": "Golden garlic",
            "is_expected_state": True,
            "recommendation": "Move on",
            "sensory_fallback": "Smells nutty",
        }

        frame = MagicMock()
        frame.read = AsyncMock(return_value=b"fake-image-bytes")

        with patch("app.routers.vision.db") as mock_db, \
             patch("app.routers.vision.upload_bytes", return_value="gs://bucket/frame.jpg"), \
             patch("app.routers.vision.assess_food_image", new_callable=AsyncMock, return_value=assessment), \
             patch("app.routers.vision.log_session_event", new_callable=AsyncMock):

            mock_db.collection.return_value = mock_collection

            result = await vision_check(
                session_id="s1",
                frame=frame,
                user={"uid": "u1"},
            )

        assert result["type"] == "vision_result"
        assert result["confidence"] == "high"

    @pytest.mark.asyncio
    async def test_vision_check_session_not_found(self):
        from app.routers.vision import vision_check
        from fastapi import HTTPException

        mock_collection = MagicMock()
        mock_doc_ref = MagicMock()
        mock_doc_ref.get = AsyncMock(return_value=_mock_missing_doc())
        mock_collection.document.return_value = mock_doc_ref

        frame = MagicMock()
        frame.read = AsyncMock(return_value=b"bytes")

        with patch("app.routers.vision.db") as mock_db, \
             pytest.raises(HTTPException) as exc_info:
            mock_db.collection.return_value = mock_collection
            await vision_check("s-missing", frame=frame, user={"uid": "u1"})
        assert exc_info.value.status_code == 404

    @pytest.mark.asyncio
    async def test_vision_check_forbidden(self):
        from app.routers.vision import vision_check
        from fastapi import HTTPException

        mock_collection = MagicMock()
        mock_doc_ref = MagicMock()
        mock_doc_ref.get = AsyncMock(return_value=_mock_session(uid="other-user"))
        mock_collection.document.return_value = mock_doc_ref

        frame = MagicMock()
        frame.read = AsyncMock(return_value=b"bytes")

        with patch("app.routers.vision.db") as mock_db, \
             pytest.raises(HTTPException) as exc_info:
            mock_db.collection.return_value = mock_collection
            await vision_check("s1", frame=frame, user={"uid": "u1"})
        assert exc_info.value.status_code == 403
