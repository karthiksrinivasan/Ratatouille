"""Tests for Epic 7 — Technical metrics instrumentation (Task 7.5)."""

import os
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from httpx import ASGITransport, AsyncClient

os.environ.setdefault("GCP_PROJECT_ID", "test-project")
os.environ.setdefault("GCS_BUCKET_NAME", "test-bucket")
os.environ.setdefault("ENVIRONMENT", "testing")

from app.auth.firebase import get_current_user, require_admin
from app.main import app

MOCK_USER = {"uid": "user1", "email": "t@t.com"}


class TestMetricsCollector:
    @pytest.mark.asyncio
    async def test_record_latency(self):
        from app.services.metrics import MetricsCollector
        mc = MetricsCollector()
        with patch("app.services.metrics.db") as mock_db:
            mock_doc = MagicMock()
            mock_doc.set = AsyncMock()
            mock_coll = MagicMock()
            mock_coll.document.return_value = mock_doc
            mock_db.collection.return_value = mock_coll

            await mc.record_latency("voice_response_ms", 150.0)

        assert "voice_response_ms" in mc.latencies
        assert mc.latencies["voice_response_ms"] == [150.0]

    @pytest.mark.asyncio
    async def test_increment_counter(self):
        from app.services.metrics import MetricsCollector
        mc = MetricsCollector()
        with patch("app.services.metrics.db") as mock_db:
            mock_doc = MagicMock()
            mock_doc.set = AsyncMock()
            mock_coll = MagicMock()
            mock_coll.document.return_value = mock_doc
            mock_db.collection.return_value = mock_coll

            await mc.increment("ws_disconnect")
            await mc.increment("ws_disconnect")

        assert mc.counters["ws_disconnect"] == 2

    def test_get_summary_empty(self):
        from app.services.metrics import MetricsCollector
        mc = MetricsCollector()
        summary = mc.get_summary()
        assert summary == {"counters": {}}

    def test_get_summary_with_data(self):
        from app.services.metrics import MetricsCollector
        mc = MetricsCollector()
        mc.latencies["voice_ms"] = [100.0, 200.0, 150.0, 300.0, 250.0]
        mc.counters["errors"] = 3
        summary = mc.get_summary()
        assert summary["voice_ms"]["count"] == 5
        assert summary["voice_ms"]["p50"] == 200.0
        assert summary["voice_ms"]["mean"] == 200.0
        assert summary["counters"]["errors"] == 3

    def test_p95_with_enough_data(self):
        from app.services.metrics import MetricsCollector
        mc = MetricsCollector()
        mc.latencies["test_ms"] = list(range(1, 101))  # 1..100
        summary = mc.get_summary()
        assert summary["test_ms"]["count"] == 100
        # int(100 * 0.95) = 95 → sorted_vals[95] = 96
        assert summary["test_ms"]["p95"] == 96.0

    @pytest.mark.asyncio
    async def test_firestore_failure_graceful(self):
        """Metrics recording should not crash if Firestore fails."""
        from app.services.metrics import MetricsCollector
        mc = MetricsCollector()
        with patch("app.services.metrics.db") as mock_db:
            mock_db.collection.side_effect = Exception("Firestore down")
            await mc.record_latency("test_ms", 100.0)
        # Should still record in-memory
        assert mc.latencies["test_ms"] == [100.0]

    @pytest.mark.asyncio
    async def test_increment_firestore_failure_graceful(self):
        """Counter increment should not crash if Firestore fails."""
        from app.services.metrics import MetricsCollector
        mc = MetricsCollector()
        with patch("app.services.metrics.db") as mock_db:
            mock_db.collection.side_effect = Exception("Firestore down")
            await mc.increment("test_counter")
        assert mc.counters["test_counter"] == 1


@pytest.mark.asyncio
async def test_metrics_endpoint_accessible():
    """Metrics endpoint returns summary for admin users."""
    app.dependency_overrides[get_current_user] = lambda: MOCK_USER
    app.dependency_overrides[require_admin] = lambda: MOCK_USER
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            resp = await ac.get("/internal/metrics")
        assert resp.status_code == 200
        data = resp.json()
        assert "counters" in data
    finally:
        app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_metrics_route_registered():
    """Metrics endpoint is registered in the app."""
    routes = [r.path for r in app.routes]
    assert "/internal/metrics" in routes
