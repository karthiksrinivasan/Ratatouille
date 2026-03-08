"""Tests for Epic 7, Task 7.7 — Graceful Degradation Hardening."""

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.services.resilience import (
    safe_firestore_write,
    safe_gemini_call,
    safe_gcs_upload,
    with_fallback,
    with_retry,
)


# ---------------------------------------------------------------------------
# Unit tests for resilience utilities
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_with_retry_retries_on_failure():
    """with_retry should retry the callable and succeed on a later attempt."""
    call_count = 0

    async def flaky():
        nonlocal call_count
        call_count += 1
        if call_count < 3:
            raise RuntimeError("transient")
        return "ok"

    result = await with_retry(flaky, max_retries=2, backoff_base=0.01)
    assert result == "ok"
    assert call_count == 3


@pytest.mark.asyncio
async def test_with_retry_raises_after_max_retries():
    """with_retry should raise the last exception after exhausting retries."""
    async def always_fails():
        raise RuntimeError("permanent")

    with pytest.raises(RuntimeError, match="permanent"):
        await with_retry(always_fails, max_retries=2, backoff_base=0.01)


@pytest.mark.asyncio
async def test_with_fallback_returns_fallback_on_error():
    """with_fallback should return fallback_value when the callable raises."""
    async def broken():
        raise ValueError("boom")

    result = await with_fallback(broken, fallback_value="safe", error_msg="test")
    assert result == "safe"


@pytest.mark.asyncio
async def test_with_fallback_returns_result_on_success():
    """with_fallback should return the actual result when the callable succeeds."""
    async def ok():
        return "real"

    result = await with_fallback(ok, fallback_value="safe")
    assert result == "real"


@pytest.mark.asyncio
async def test_safe_gemini_call_returns_fallback_text():
    """safe_gemini_call should return the fallback text on failure."""
    async def bad_gemini():
        raise ConnectionError("Gemini unavailable")

    result = await safe_gemini_call(bad_gemini, fallback_text="fallback advice")
    assert result == "fallback advice"


@pytest.mark.asyncio
async def test_safe_gemini_call_returns_result_on_success():
    """safe_gemini_call should return the real result on success."""
    async def good_gemini():
        return "real response"

    result = await safe_gemini_call(good_gemini)
    assert result == "real response"


@pytest.mark.asyncio
async def test_safe_firestore_write_handles_errors():
    """safe_firestore_write should swallow errors and return None."""
    async def bad_write():
        raise RuntimeError("Firestore down")

    result = await safe_firestore_write(bad_write, fallback_msg="write failed")
    assert result is None


@pytest.mark.asyncio
async def test_safe_firestore_write_returns_result_on_success():
    """safe_firestore_write should return the result on success."""
    async def good_write():
        return "written"

    result = await safe_firestore_write(good_write)
    assert result == "written"


@pytest.mark.asyncio
async def test_safe_gcs_upload_handles_errors():
    """safe_gcs_upload should swallow errors and return None."""
    async def bad_upload():
        raise IOError("GCS down")

    result = await safe_gcs_upload(bad_upload, fallback_msg="upload failed")
    assert result is None


# ---------------------------------------------------------------------------
# Integration-style tests for vision router degradation
# ---------------------------------------------------------------------------

def _mock_session_doc(uid="user1", recipe_id="recipe1", step=1):
    doc = MagicMock()
    doc.exists = True
    doc.to_dict.return_value = {
        "uid": uid,
        "recipe_id": recipe_id,
        "current_step": step,
    }
    return doc


def _mock_recipe_doc(title="Pasta", steps=None):
    if steps is None:
        steps = [{"step_number": 1, "instruction": "Boil water", "technique_tags": ["boiling"]}]
    doc = MagicMock()
    doc.exists = True
    doc.to_dict.return_value = {"title": title, "steps": steps}
    return doc


@pytest.mark.asyncio
async def test_vision_check_gemini_failure_returns_degraded():
    """vision_check should return a degraded response when assess_food_image fails."""
    with patch("app.routers.vision.db") as mock_db, \
         patch("app.routers.vision.upload_bytes", return_value="gs://bucket/frame.jpg"), \
         patch("app.routers.vision.assess_food_image", side_effect=RuntimeError("Gemini down")), \
         patch("app.routers.vision.format_vision_response", side_effect=lambda x: x) as mock_format, \
         patch("app.routers.vision.log_session_event", new_callable=AsyncMock):

        session_doc = _mock_session_doc()
        recipe_doc = _mock_recipe_doc()

        mock_collection = MagicMock()
        mock_db.collection.return_value = mock_collection
        mock_doc_ref = MagicMock()
        mock_collection.document.return_value = mock_doc_ref
        mock_doc_ref.get = AsyncMock(side_effect=[session_doc, recipe_doc])

        from app.routers.vision import vision_check

        mock_frame = MagicMock()
        mock_frame.read = AsyncMock(return_value=b"fake-image-data")

        result = await vision_check(
            session_id="sess1",
            frame=mock_frame,
            user={"uid": "user1"},
        )

        assert result["degraded"] is True
        assert "can't see clearly" in result["assessment"].lower() or "senses" in result["assessment"].lower()


@pytest.mark.asyncio
async def test_taste_check_gemini_failure_returns_fallback():
    """taste_check should return fallback advice when Gemini fails."""
    with patch("app.routers.vision.db") as mock_db, \
         patch("app.routers.vision.gemini_client") as mock_gemini, \
         patch("app.routers.vision.log_session_event", new_callable=AsyncMock):

        session_doc = _mock_session_doc()
        recipe_doc = _mock_recipe_doc()

        mock_collection = MagicMock()
        mock_db.collection.return_value = mock_collection
        mock_doc_ref = MagicMock()
        mock_collection.document.return_value = mock_doc_ref
        mock_doc_ref.get = AsyncMock(side_effect=[session_doc, recipe_doc])

        # Make Gemini call fail
        mock_gemini.aio.models.generate_content = AsyncMock(
            side_effect=RuntimeError("Gemini down")
        )

        from app.routers.vision import taste_check

        result = await taste_check(
            session_id="sess1",
            description="too salty",
            user={"uid": "user1"},
        )

        assert result["type"] == "taste_result"
        assert result.get("degraded") is True
        assert "trouble analyzing" in result["message"].lower() or "general advice" in result["message"].lower()
