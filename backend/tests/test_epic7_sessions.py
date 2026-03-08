"""Tests for Epic 7 — Session completion, wind-down, and deferred notification."""

import os
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from httpx import ASGITransport, AsyncClient

os.environ.setdefault("GCP_PROJECT_ID", "test-project")
os.environ.setdefault("GCS_BUCKET_NAME", "test-bucket")
os.environ.setdefault("ENVIRONMENT", "testing")

from app.auth.firebase import get_current_user
from app.main import app

MOCK_USER = {"uid": "user1", "email": "t@t.com"}


@pytest.fixture(autouse=True)
def override_auth():
    app.dependency_overrides[get_current_user] = lambda: MOCK_USER
    yield
    app.dependency_overrides.clear()


def _make_session_doc(status="active", uid="user1", recipe_id="recipe1"):
    doc = MagicMock()
    doc.exists = True
    doc.to_dict.return_value = {
        "uid": uid,
        "recipe_id": recipe_id,
        "status": status,
        "session_id": "sess1",
    }
    return doc


def _make_recipe_doc():
    doc = MagicMock()
    doc.exists = True
    doc.to_dict.return_value = {"title": "Aglio e Olio", "steps": []}
    return doc


def _not_found_doc():
    doc = MagicMock()
    doc.exists = False
    return doc


@pytest.mark.asyncio
async def test_complete_session():
    """Session completion sets status to completed and returns wind-down options."""
    session_doc = _make_session_doc()
    recipe_doc = _make_recipe_doc()

    with patch("app.routers.sessions.db") as mock_db, \
         patch("app.routers.sessions.gemini_client") as mock_gemini, \
         patch("app.routers.sessions.log_session_event", new_callable=AsyncMock), \
         patch("app.routers.vision._guide_generators", {}):

        response_obj = MagicMock()
        response_obj.text = "Great job! Enjoy your meal."
        mock_gemini.aio.models.generate_content = AsyncMock(return_value=response_obj)

        mock_doc = MagicMock()
        mock_doc.get = AsyncMock(side_effect=[session_doc, recipe_doc])
        mock_doc.update = AsyncMock()
        mock_coll = MagicMock()
        mock_coll.document.return_value = mock_doc
        mock_db.collection.return_value = mock_coll

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            resp = await ac.post("/v1/sessions/sess1/complete")

    assert resp.status_code == 200
    data = resp.json()
    assert data["type"] == "session_complete"
    assert "message" in data
    assert data["wind_down"]["max_interactions"] == 3
    assert len(data["wind_down"]["options"]) == 3
    option_ids = [o["id"] for o in data["wind_down"]["options"]]
    assert "difficulty" in option_ids
    assert "memory" in option_ids
    assert "photo" in option_ids


@pytest.mark.asyncio
async def test_complete_session_not_found():
    """Completing a non-existent session returns 404."""
    with patch("app.routers.sessions.db") as mock_db:
        mock_doc = MagicMock()
        mock_doc.get = AsyncMock(return_value=_not_found_doc())
        mock_coll = MagicMock()
        mock_coll.document.return_value = mock_doc
        mock_db.collection.return_value = mock_coll

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            resp = await ac.post("/v1/sessions/sess1/complete")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_complete_session_not_active():
    """Completing a non-active session returns 400."""
    with patch("app.routers.sessions.db") as mock_db:
        mock_doc = MagicMock()
        mock_doc.get = AsyncMock(return_value=_make_session_doc(status="completed"))
        mock_coll = MagicMock()
        mock_coll.document.return_value = mock_doc
        mock_db.collection.return_value = mock_coll

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            resp = await ac.post("/v1/sessions/sess1/complete")
    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_complete_session_wrong_user():
    """Completing another user's session returns 403."""
    with patch("app.routers.sessions.db") as mock_db:
        mock_doc = MagicMock()
        mock_doc.get = AsyncMock(return_value=_make_session_doc(uid="other-user"))
        mock_coll = MagicMock()
        mock_coll.document.return_value = mock_doc
        mock_db.collection.return_value = mock_coll

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            resp = await ac.post("/v1/sessions/sess1/complete")
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_wind_down_difficulty():
    """Difficulty rating wind-down interaction works."""
    with patch("app.routers.sessions.db") as mock_db, \
         patch("app.routers.sessions.log_session_event", new_callable=AsyncMock):
        mock_doc = MagicMock()
        mock_doc.get = AsyncMock(return_value=_make_session_doc(status="completed"))
        mock_coll = MagicMock()
        mock_coll.document.return_value = mock_doc
        mock_db.collection.return_value = mock_coll

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            resp = await ac.post(
                "/v1/sessions/sess1/wind-down/difficulty",
                json={"rating": "😊"},
            )
    assert resp.status_code == 200
    assert "Thanks" in resp.json()["message"]


@pytest.mark.asyncio
async def test_wind_down_memory_confirmed():
    """Confirmed memories are stored in user's memories subcollection."""
    with patch("app.routers.sessions.db") as mock_db:
        def _collection(name):
            coll = MagicMock()
            doc = MagicMock()
            if name == "sessions":
                doc.get = AsyncMock(return_value=_make_session_doc(status="completed"))
            elif name == "users":
                sub_coll = MagicMock()
                sub_doc = MagicMock()
                sub_doc.set = AsyncMock()
                sub_coll.document.return_value = sub_doc
                doc.collection.return_value = sub_coll
            coll.document.return_value = doc
            return coll
        mock_db.collection.side_effect = _collection

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            resp = await ac.post(
                "/v1/sessions/sess1/wind-down/memory",
                json={
                    "observations": ["You like garlic light", "Extra chili flakes"],
                    "confirmed": True,
                },
            )
    assert resp.status_code == 200
    assert "2 thing(s)" in resp.json()["message"]


@pytest.mark.asyncio
async def test_wind_down_memory_rejected():
    """Rejected memories are not stored."""
    with patch("app.routers.sessions.db") as mock_db:
        mock_doc = MagicMock()
        mock_doc.get = AsyncMock(return_value=_make_session_doc(status="completed"))
        mock_coll = MagicMock()
        mock_coll.document.return_value = mock_doc
        mock_db.collection.return_value = mock_coll

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            resp = await ac.post(
                "/v1/sessions/sess1/wind-down/memory",
                json={"observations": [], "confirmed": False},
            )
    assert resp.status_code == 200
    assert "No worries" in resp.json()["message"]


@pytest.mark.asyncio
async def test_wind_down_photo():
    """Photo wind-down interaction acknowledged."""
    with patch("app.routers.sessions.db") as mock_db:
        mock_doc = MagicMock()
        mock_doc.get = AsyncMock(return_value=_make_session_doc(status="completed"))
        mock_coll = MagicMock()
        mock_coll.document.return_value = mock_doc
        mock_db.collection.return_value = mock_coll

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            resp = await ac.post(
                "/v1/sessions/sess1/wind-down/photo",
                json={},
            )
    assert resp.status_code == 200
    assert "Enjoy" in resp.json()["message"]


@pytest.mark.asyncio
async def test_wind_down_unknown_interaction():
    """Unknown interaction ID returns 400."""
    with patch("app.routers.sessions.db") as mock_db:
        mock_doc = MagicMock()
        mock_doc.get = AsyncMock(return_value=_make_session_doc(status="completed"))
        mock_coll = MagicMock()
        mock_coll.document.return_value = mock_doc
        mock_db.collection.return_value = mock_coll

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            resp = await ac.post(
                "/v1/sessions/sess1/wind-down/unknown",
                json={},
            )
    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_deferred_winddown():
    """Deferred wind-down notification creates a Firestore document."""
    with patch("app.routers.sessions.db") as mock_db:
        mock_sub = MagicMock()
        mock_sub.add = AsyncMock()
        mock_doc = MagicMock()
        mock_doc.collection.return_value = mock_sub
        mock_coll = MagicMock()
        mock_coll.document.return_value = mock_doc
        mock_db.collection.return_value = mock_coll

        from app.routers.sessions import schedule_deferred_winddown
        await schedule_deferred_winddown("sess1", "user1")

        mock_sub.add.assert_called_once()
        call_args = mock_sub.add.call_args[0][0]
        assert call_args["type"] == "deferred_wind_down"
        assert call_args["session_id"] == "sess1"
        assert call_args["read"] is False


@pytest.mark.asyncio
async def test_complete_session_cleans_guide_generators():
    """Completing a session cleans up guide generators."""
    session_doc = _make_session_doc()
    recipe_doc = _make_recipe_doc()
    generators = {"sess1": "generator_obj"}

    with patch("app.routers.sessions.db") as mock_db, \
         patch("app.routers.sessions.gemini_client") as mock_gemini, \
         patch("app.routers.sessions.log_session_event", new_callable=AsyncMock), \
         patch("app.routers.vision._guide_generators", generators):

        response_obj = MagicMock()
        response_obj.text = "Well done!"
        mock_gemini.aio.models.generate_content = AsyncMock(return_value=response_obj)

        mock_doc = MagicMock()
        mock_doc.get = AsyncMock(side_effect=[session_doc, recipe_doc])
        mock_doc.update = AsyncMock()
        mock_coll = MagicMock()
        mock_coll.document.return_value = mock_doc
        mock_db.collection.return_value = mock_coll

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            resp = await ac.post("/v1/sessions/sess1/complete")

    assert resp.status_code == 200
    assert "sess1" not in generators
