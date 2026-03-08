"""Tests for Task 1.5 — Firebase auth dependency."""
import pytest
from unittest.mock import patch, MagicMock
from fastapi import HTTPException


@pytest.mark.asyncio
async def test_missing_bearer_prefix():
    """Auth rejects tokens without Bearer prefix."""
    from app.auth.firebase import get_current_user

    with pytest.raises(HTTPException) as exc_info:
        await get_current_user(authorization="Token abc123")
    assert exc_info.value.status_code == 401
    assert "Invalid authorization header" in str(exc_info.value.detail)


@pytest.mark.asyncio
async def test_valid_token():
    """Auth returns decoded token for valid Bearer token."""
    from app.auth.firebase import get_current_user

    mock_decoded = {"uid": "user123", "email": "test@example.com"}
    with patch("app.auth.firebase.auth.verify_id_token", return_value=mock_decoded):
        result = await get_current_user(authorization="Bearer valid-token")
    assert result["uid"] == "user123"
    assert result["email"] == "test@example.com"


@pytest.mark.asyncio
async def test_invalid_token():
    """Auth rejects invalid tokens with 401."""
    from app.auth.firebase import get_current_user
    from firebase_admin import auth

    with patch(
        "app.auth.firebase.auth.verify_id_token",
        side_effect=auth.InvalidIdTokenError("bad"),
    ):
        with pytest.raises(HTTPException) as exc_info:
            await get_current_user(authorization="Bearer bad-token")
        assert exc_info.value.status_code == 401


@pytest.mark.asyncio
async def test_expired_token():
    """Auth rejects expired tokens with 401."""
    from app.auth.firebase import get_current_user
    from firebase_admin import auth

    with patch(
        "app.auth.firebase.auth.verify_id_token",
        side_effect=auth.ExpiredIdTokenError("expired", "cause"),
    ):
        with pytest.raises(HTTPException) as exc_info:
            await get_current_user(authorization="Bearer expired-token")
        assert exc_info.value.status_code == 401
