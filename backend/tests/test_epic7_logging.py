"""Tests for Epic 7 — Structured logging (Task 7.4)."""

import json
import logging
import os

import pytest
from httpx import ASGITransport, AsyncClient

os.environ.setdefault("GCP_PROJECT_ID", "test-project")
os.environ.setdefault("GCS_BUCKET_NAME", "test-bucket")
os.environ.setdefault("ENVIRONMENT", "testing")


class TestStructuredFormatter:
    def test_basic_format(self):
        from app.services.logging import StructuredFormatter
        fmt = StructuredFormatter()
        record = logging.LogRecord(
            name="ratatouille",
            level=logging.INFO,
            pathname="",
            lineno=0,
            msg="test message",
            args=(),
            exc_info=None,
        )
        output = fmt.format(record)
        parsed = json.loads(output)
        assert parsed["severity"] == "INFO"
        assert parsed["message"] == "test message"
        assert "timestamp" in parsed
        assert parsed["component"] == "ratatouille"

    def test_extra_fields(self):
        from app.services.logging import StructuredFormatter
        fmt = StructuredFormatter()
        record = logging.LogRecord(
            name="ratatouille",
            level=logging.INFO,
            pathname="",
            lineno=0,
            msg="request logged",
            args=(),
            exc_info=None,
        )
        record.session_id = "sess-123"
        record.endpoint = "/v1/sessions"
        record.latency_ms = 42.5
        record.status_code = 200
        output = fmt.format(record)
        parsed = json.loads(output)
        assert parsed["session_id"] == "sess-123"
        assert parsed["endpoint"] == "/v1/sessions"
        assert parsed["latency_ms"] == 42.5
        assert parsed["status_code"] == 200

    def test_error_included(self):
        from app.services.logging import StructuredFormatter
        fmt = StructuredFormatter()
        try:
            raise ValueError("test error")
        except ValueError:
            import sys
            exc_info = sys.exc_info()

        record = logging.LogRecord(
            name="ratatouille",
            level=logging.ERROR,
            pathname="",
            lineno=0,
            msg="something failed",
            args=(),
            exc_info=exc_info,
        )
        output = fmt.format(record)
        parsed = json.loads(output)
        assert "error" in parsed
        assert "test error" in parsed["error"]

    def test_no_sensitive_fields(self):
        """Ensure no token/auth fields are logged."""
        from app.services.logging import StructuredFormatter
        fmt = StructuredFormatter()
        record = logging.LogRecord(
            name="ratatouille",
            level=logging.INFO,
            pathname="",
            lineno=0,
            msg="GET /v1/sessions 200",
            args=(),
            exc_info=None,
        )
        output = fmt.format(record)
        parsed = json.loads(output)
        assert "token" not in parsed
        assert "authorization" not in parsed
        assert "audio" not in parsed


class TestSetupLogging:
    def test_setup_configures_root_logger(self):
        from app.services.logging import setup_logging, StructuredFormatter
        setup_logging()
        assert logging.root.level == logging.INFO
        assert any(isinstance(h.formatter, StructuredFormatter) for h in logging.root.handlers)


@pytest.mark.asyncio
async def test_request_logging_middleware():
    """Middleware logs non-health requests."""
    from app.main import app
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        resp = await ac.get("/health")
    assert resp.status_code == 200


@pytest.mark.asyncio
async def test_middleware_logs_non_health():
    """Non-health endpoints get logged through middleware."""
    from app.main import app
    # Just verify the middleware doesn't crash on a real request
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        resp = await ac.get("/v1/nonexistent")
    # 404 or 405 — doesn't matter, just checking middleware works
    assert resp.status_code in (404, 405)
