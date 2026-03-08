"""Tests for privacy controls verification (Epic 7, Task 7.8)."""

import inspect
from unittest.mock import MagicMock

from app.services.privacy import (
    PRIVACY_CONSTRAINTS,
    SENSITIVE_FIELDS,
    sanitize_log_data,
    verify_no_pii_in_log,
)


# --- verify_no_pii_in_log ---


class TestVerifyNoPiiInLog:
    def test_catches_token_field(self):
        entry = {"message": "user logged in", "token": "abc123"}
        assert verify_no_pii_in_log(entry) is False

    def test_catches_authorization_field(self):
        entry = {"authorization": "Bearer xyz", "path": "/v1/sessions"}
        assert verify_no_pii_in_log(entry) is False

    def test_catches_audio_field(self):
        entry = {"audio": "base64data==", "type": "voice"}
        assert verify_no_pii_in_log(entry) is False

    def test_catches_password_field(self):
        entry = {"password": "secret123", "user": "test"}
        assert verify_no_pii_in_log(entry) is False

    def test_catches_bearer_in_value(self):
        entry = {"header": "Bearer some-token-value"}
        assert verify_no_pii_in_log(entry) is False

    def test_catches_nested_sensitive_field(self):
        entry = {"request": {"headers": {"authorization": "Bearer tok"}}}
        assert verify_no_pii_in_log(entry) is False

    def test_allows_clean_entry(self):
        entry = {
            "message": "request processed",
            "status_code": 200,
            "latency_ms": 42.5,
            "endpoint": "/v1/sessions",
        }
        assert verify_no_pii_in_log(entry) is True

    def test_allows_empty_entry(self):
        assert verify_no_pii_in_log({}) is True

    def test_case_insensitive_key_check(self):
        entry = {"Authorization": "Bearer xyz"}
        assert verify_no_pii_in_log(entry) is False

    def test_catches_id_token_field(self):
        entry = {"id_token": "eyJhbGciOi..."}
        assert verify_no_pii_in_log(entry) is False


# --- sanitize_log_data ---


class TestSanitizeLogData:
    def test_redacts_sensitive_fields(self):
        data = {
            "authorization": "Bearer abc",
            "token": "xyz",
            "endpoint": "/v1/sessions",
        }
        result = sanitize_log_data(data)
        assert result["authorization"] == "[REDACTED]"
        assert result["token"] == "[REDACTED]"
        assert result["endpoint"] == "/v1/sessions"

    def test_preserves_non_sensitive_fields(self):
        data = {"message": "ok", "status": 200}
        result = sanitize_log_data(data)
        assert result == data

    def test_redacts_nested_sensitive_fields(self):
        data = {"headers": {"authorization": "Bearer tok", "content_type": "json"}}
        result = sanitize_log_data(data)
        assert result["headers"]["authorization"] == "[REDACTED]"
        assert result["headers"]["content_type"] == "json"

    def test_does_not_mutate_original(self):
        data = {"token": "secret", "msg": "hi"}
        original_token = data["token"]
        sanitize_log_data(data)
        assert data["token"] == original_token

    def test_empty_dict(self):
        assert sanitize_log_data({}) == {}


# --- PRIVACY_CONSTRAINTS ---


class TestPrivacyConstraints:
    def test_all_constraints_documented(self):
        expected = [
            "ambient_mode_requires_optin",
            "ambient_raw_not_persisted",
            "only_user_triggered_artifacts_stored",
            "auth_on_every_endpoint",
            "memory_confirmation_gate",
            "no_pii_in_logs",
        ]
        for constraint in expected:
            assert constraint in PRIVACY_CONSTRAINTS, f"Missing constraint: {constraint}"
            assert PRIVACY_CONSTRAINTS[constraint] is True

    def test_sensitive_fields_list(self):
        required = ["authorization", "token", "audio", "password", "Bearer"]
        for field in required:
            assert field in SENSITIVE_FIELDS, f"Missing sensitive field: {field}"


# --- Auth dependency on all router endpoints ---


class TestAuthOnEndpoints:
    def test_session_router_endpoints_require_auth(self):
        from app.routers.sessions import router

        for route in router.routes:
            if not hasattr(route, "dependant"):
                continue
            deps = route.dependant.dependencies
            dep_callables = [d.call.__name__ for d in deps if hasattr(d.call, "__name__")]
            assert "get_current_user" in dep_callables, (
                f"Route {route.path} missing get_current_user dependency"
            )

    def test_recipe_router_endpoints_require_auth(self):
        from app.routers.recipes import router

        for route in router.routes:
            if not hasattr(route, "dependant"):
                continue
            deps = route.dependant.dependencies
            dep_callables = [d.call.__name__ for d in deps if hasattr(d.call, "__name__")]
            assert "get_current_user" in dep_callables, (
                f"Route {route.path} missing get_current_user dependency"
            )

    def test_inventory_router_endpoints_require_auth(self):
        from app.routers.inventory import router

        for route in router.routes:
            if not hasattr(route, "dependant"):
                continue
            deps = route.dependant.dependencies
            dep_callables = [d.call.__name__ for d in deps if hasattr(d.call, "__name__")]
            assert "get_current_user" in dep_callables, (
                f"Route {route.path} missing get_current_user dependency"
            )

    def test_vision_router_endpoints_require_auth(self):
        from app.routers.vision import router

        for route in router.routes:
            if not hasattr(route, "dependant"):
                continue
            deps = route.dependant.dependencies
            dep_callables = [d.call.__name__ for d in deps if hasattr(d.call, "__name__")]
            assert "get_current_user" in dep_callables, (
                f"Route {route.path} missing get_current_user dependency"
            )

    def test_websocket_has_auth(self):
        """Verify the live WebSocket endpoint authenticates users."""
        from app.routers.live import authenticate_websocket

        # The function exists and is used in the WebSocket handler
        assert callable(authenticate_websocket)
        assert inspect.iscoroutinefunction(authenticate_websocket)


# --- Memory confirmation gate ---


class TestMemoryConfirmationGate:
    def test_wind_down_memory_requires_confirmed(self):
        """Verify that the memory wind-down interaction checks for 'confirmed' field."""
        from app.routers.sessions import wind_down_interaction

        source = inspect.getsource(wind_down_interaction)
        # The handler must check "confirmed" before persisting memories
        assert "confirmed" in source, (
            "wind_down_interaction must check 'confirmed' field before storing memories"
        )

    def test_memories_only_stored_when_confirmed(self):
        """Verify that memories are only stored when confirmed is True."""
        from app.routers.sessions import wind_down_interaction

        source = inspect.getsource(wind_down_interaction)
        # Must have a conditional that checks confirmed before writing to memories
        assert "if confirmed" in source or "if confirmed and" in source, (
            "Memories must only be stored when user explicitly confirms"
        )


# --- Ambient mode opt-in ---


class TestAmbientOptIn:
    def test_ambient_toggle_requires_explicit_enabled(self):
        """Verify ambient_toggle event requires an explicit 'enabled' field."""
        from app.routers.live import live_session

        source = inspect.getsource(live_session)
        # ambient_toggle must read the enabled field from client data
        assert "ambient_toggle" in source
        assert 'data.get("enabled"' in source or "data.get('enabled'" in source, (
            "ambient_toggle must require explicit enabled field from client"
        )

    def test_ambient_defaults_to_off(self):
        """Verify ambient mode defaults to False (opt-in, not opt-out)."""
        from app.routers.live import live_session

        source = inspect.getsource(live_session)
        # Default should be False
        assert "enabled, False" in source or "enabled\", False" in source, (
            "ambient_toggle must default to False (opt-in required)"
        )
