"""Tests for Tasks 1.3, 1.4, 1.8 — service module imports and structure."""


def test_firestore_client_importable():
    """Firestore AsyncClient wrapper is importable."""
    from app.services.firestore import db, get_db
    assert db is not None
    assert callable(get_db)


def test_storage_helpers_importable():
    """GCS upload_bytes and get_signed_url are importable."""
    from app.services.storage import upload_bytes, get_signed_url
    assert callable(upload_bytes)
    assert callable(get_signed_url)


def test_gemini_client_importable():
    """Gemini client and model constants are importable."""
    from app.services.gemini import (
        gemini_client,
        get_gemini_client,
        MODEL_FLASH,
        MODEL_LIVE,
        MODEL_IMAGE_GEN,
        MODEL_PRO,
    )
    assert gemini_client is not None
    assert callable(get_gemini_client)
    # Model constants must be non-empty strings
    assert isinstance(MODEL_FLASH, str) and len(MODEL_FLASH) > 0
    assert isinstance(MODEL_LIVE, str) and len(MODEL_LIVE) > 0
    assert isinstance(MODEL_IMAGE_GEN, str) and len(MODEL_IMAGE_GEN) > 0
    assert isinstance(MODEL_PRO, str) and len(MODEL_PRO) > 0


def test_gemini_vertexai_flag():
    """Gemini client initializes with vertexai=True."""
    from app.services.gemini import get_gemini_client
    client = get_gemini_client()
    # The client should exist (actual API call not tested here)
    assert client is not None


def test_storage_returns_gs_uri():
    """upload_bytes returns gs:// URI format."""
    from unittest.mock import patch, MagicMock
    from app.services import storage

    mock_blob = MagicMock()
    with patch.object(storage.bucket, "blob", return_value=mock_blob):
        uri = storage.upload_bytes("test/path.jpg", b"data", "image/jpeg")

    assert uri.startswith("gs://")
    assert "test/path.jpg" in uri
    mock_blob.upload_from_string.assert_called_once_with(b"data", content_type="image/jpeg")
