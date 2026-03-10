"""Tests for Epic 7 — Product analytics events (Task 7.6)."""

import os
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

os.environ.setdefault("GCP_PROJECT_ID", "test-project")
os.environ.setdefault("GCS_BUCKET_NAME", "test-bucket")
os.environ.setdefault("ENVIRONMENT", "testing")


class TestProductEvents:
    def test_all_event_types_defined(self):
        from app.services.analytics import PRODUCT_EVENTS
        expected = [
            "scan_started", "scan_completed", "scan_confirmed",
            "suggestions_viewed", "suggestion_selected",
            "session_started", "session_completed", "session_abandoned",
            "vision_check_requested", "visual_guide_requested", "guide_image_feedback",
            "barge_in_triggered",
            "taste_check_requested", "recovery_requested", "user_override",
            "memory_confirmed", "memory_rejected",
            "timer_started", "timer_completed",
        ]
        for event in expected:
            assert event in PRODUCT_EVENTS

    @pytest.mark.asyncio
    async def test_emit_product_event(self):
        from app.services.analytics import emit_product_event

        with patch("app.services.analytics.db") as mock_db, \
             patch("app.services.analytics.metrics") as mock_metrics:
            mock_coll = MagicMock()
            mock_coll.add = AsyncMock()
            mock_db.collection.return_value = mock_coll
            mock_metrics.increment = AsyncMock()

            await emit_product_event("scan_started", "user1", {"source": "fridge"})

            mock_coll.add.assert_called_once()
            event = mock_coll.add.call_args[0][0]
            assert event["event_type"] == "scan_started"
            assert event["uid"] == "user1"
            assert event["metadata"] == {"source": "fridge"}
            mock_metrics.increment.assert_called_with("event_scan_started")

    @pytest.mark.asyncio
    async def test_emit_event_without_metadata(self):
        from app.services.analytics import emit_product_event

        with patch("app.services.analytics.db") as mock_db, \
             patch("app.services.analytics.metrics") as mock_metrics:
            mock_coll = MagicMock()
            mock_coll.add = AsyncMock()
            mock_db.collection.return_value = mock_coll
            mock_metrics.increment = AsyncMock()

            await emit_product_event("session_completed", "user1")

            event = mock_coll.add.call_args[0][0]
            assert event["metadata"] == {}

    @pytest.mark.asyncio
    async def test_emit_event_firestore_failure(self):
        """Event emission should not crash if Firestore fails."""
        from app.services.analytics import emit_product_event

        with patch("app.services.analytics.db") as mock_db, \
             patch("app.services.analytics.metrics") as mock_metrics:
            mock_coll = MagicMock()
            mock_coll.add = AsyncMock(side_effect=Exception("Firestore down"))
            mock_db.collection.return_value = mock_coll
            mock_metrics.increment = AsyncMock()

            # Should not raise
            await emit_product_event("scan_started", "user1")

            # Counter should still be incremented
            mock_metrics.increment.assert_called_with("event_scan_started")

    @pytest.mark.asyncio
    async def test_event_includes_timestamp(self):
        from app.services.analytics import emit_product_event
        from google.cloud import firestore

        with patch("app.services.analytics.db") as mock_db, \
             patch("app.services.analytics.metrics") as mock_metrics:
            mock_coll = MagicMock()
            mock_coll.add = AsyncMock()
            mock_db.collection.return_value = mock_coll
            mock_metrics.increment = AsyncMock()

            await emit_product_event("vision_check", "user1")

            event = mock_coll.add.call_args[0][0]
            assert event["timestamp"] is firestore.SERVER_TIMESTAMP
