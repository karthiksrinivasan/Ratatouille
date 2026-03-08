"""Tests for Epic 9 — Zero-Setup Seasoned Chef Buddy Mode."""

import pytest
from app.services.analytics import PRODUCT_EVENTS


class TestEpic9Analytics:
    """Task 9.1 — Verify zero-setup analytics events are registered."""

    def test_zero_setup_entry_event_registered(self):
        assert "zero_setup_entry_tapped" in PRODUCT_EVENTS

    def test_zero_setup_session_created_event_registered(self):
        assert "zero_setup_session_created" in PRODUCT_EVENTS

    def test_zero_setup_session_activated_event_registered(self):
        assert "zero_setup_session_activated" in PRODUCT_EVENTS

    def test_zero_setup_session_completed_event_registered(self):
        assert "zero_setup_session_completed" in PRODUCT_EVENTS

    def test_browse_events_registered(self):
        assert "browse_started" in PRODUCT_EVENTS
        assert "browse_completed" in PRODUCT_EVENTS
