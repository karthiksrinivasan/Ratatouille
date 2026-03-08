"""Tests for Task 1.6 — FastAPI app health endpoint."""
import pytest
from unittest.mock import patch


@pytest.fixture
def client():
    """Create a TestClient, mocking Firebase init to avoid credentials."""
    with patch("firebase_admin.initialize_app"):
        from app.main import app
        from fastapi.testclient import TestClient
        return TestClient(app)


def test_health_returns_200(client):
    """GET /health returns 200 with status ok."""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


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
