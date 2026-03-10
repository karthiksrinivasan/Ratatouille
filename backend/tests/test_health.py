"""Tests for health endpoint and startup warmup (Epic 7, Task 7.11)."""
import pytest
from unittest.mock import patch, AsyncMock, MagicMock
from httpx import AsyncClient, ASGITransport


@pytest.fixture
def client():
    """Create a TestClient, mocking Firebase init to avoid credentials."""
    with patch("firebase_admin.initialize_app"):
        from app.main import app
        from fastapi.testclient import TestClient
        return TestClient(app)


def test_health_returns_ok_when_services_available(client):
    """GET /health returns 'ok' when Firestore and GCS are reachable."""
    mock_doc = AsyncMock()
    mock_collection = MagicMock()
    mock_collection.document.return_value.get = mock_doc

    mock_blob = MagicMock()
    mock_blob.exists.return_value = True
    mock_bucket = MagicMock()
    mock_bucket.blob.return_value = mock_blob

    with patch("app.services.firestore.db.collection", return_value=mock_collection), \
         patch("app.services.storage.bucket", mock_bucket):
        response = client.get("/health")

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"
    assert data["checks"]["firestore"] == "ok"
    assert data["checks"]["gcs"] == "ok"


def test_health_returns_degraded_when_firestore_fails(client):
    """GET /health returns 'degraded' when Firestore is unreachable."""
    mock_blob = MagicMock()
    mock_blob.exists.return_value = True
    mock_bucket = MagicMock()
    mock_bucket.blob.return_value = mock_blob

    with patch("app.services.firestore.db.collection", side_effect=Exception("connection error")), \
         patch("app.services.storage.bucket", mock_bucket):
        response = client.get("/health")

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "degraded"
    assert data["checks"]["firestore"] == "error"
    assert data["checks"]["gcs"] == "ok"


def test_health_returns_degraded_when_gcs_fails(client):
    """GET /health returns 'degraded' when GCS is unreachable."""
    mock_doc = AsyncMock()
    mock_collection = MagicMock()
    mock_collection.document.return_value.get = mock_doc

    mock_bucket = MagicMock()
    mock_bucket.blob.side_effect = Exception("gcs error")

    with patch("app.services.firestore.db.collection", return_value=mock_collection), \
         patch("app.services.storage.bucket", mock_bucket):
        response = client.get("/health")

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "degraded"
    assert data["checks"]["firestore"] == "ok"
    assert data["checks"]["gcs"] == "error"


def test_startup_warmup_runs_without_error():
    """Startup warmup event completes without raising."""
    with patch("firebase_admin.initialize_app"):
        from app.main import warmup
        import asyncio

        mock_generate = AsyncMock(return_value="ok")
        with patch("app.services.gemini.gemini_client.aio.models.generate_content", mock_generate):
            asyncio.get_event_loop().run_until_complete(warmup())

        mock_generate.assert_called_once()


@pytest.mark.asyncio
async def test_health_gcs_uses_async():
    """GCS health check must not block the event loop."""
    mock_bucket = MagicMock()
    mock_blob = MagicMock()
    mock_bucket.blob.return_value = mock_blob
    mock_blob.exists.return_value = True

    with patch("firebase_admin.initialize_app"):
        from app.main import app
        with patch("app.main.asyncio.to_thread", new_callable=AsyncMock) as mock_to_thread:
            mock_to_thread.return_value = True
            async with AsyncClient(
                transport=ASGITransport(app=app), base_url="http://test"
            ) as client:
                resp = await client.get("/health")
                assert resp.status_code == 200
                mock_to_thread.assert_called_once()


def test_cors_headers(client):
    """CORS middleware allows all origins (hackathon config)."""
    response = client.options(
        "/health",
        headers={
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "GET",
        },
    )
    assert response.status_code == 200
    assert "access-control-allow-origin" in response.headers
