"""Tests for Epic 9 — Zero-Setup Seasoned Chef Buddy Mode."""

import pytest
from app.services.analytics import PRODUCT_EVENTS
from app.models.session import SessionCreate, FreestyleContext, Session


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


class TestSessionCreateContract:
    """Task 9.2 — Unified session creation contract."""

    def test_freestyle_mode_no_recipe_id(self):
        body = SessionCreate(session_mode="freestyle")
        assert body.session_mode == "freestyle"
        assert body.recipe_id is None
        assert body.interaction_mode == "voice_video_call"
        assert body.allow_text_input is False

    def test_recipe_guided_mode_with_recipe_id(self):
        body = SessionCreate(session_mode="recipe_guided", recipe_id="r123")
        assert body.session_mode == "recipe_guided"
        assert body.recipe_id == "r123"

    def test_interaction_mode_default(self):
        body = SessionCreate()
        assert body.interaction_mode == "voice_video_call"

    def test_allow_text_input_default_false(self):
        body = SessionCreate()
        assert body.allow_text_input is False

    def test_allow_text_input_explicit_true(self):
        body = SessionCreate(allow_text_input=True)
        assert body.allow_text_input is True

    def test_freestyle_context_populated(self):
        ctx = FreestyleContext(
            dish_goal="quick dinner",
            available_ingredients=["eggs", "cheese"],
            time_budget_minutes=30,
        )
        body = SessionCreate(
            session_mode="freestyle",
            freestyle_context=ctx,
        )
        assert body.freestyle_context.dish_goal == "quick dinner"
        assert body.freestyle_context.available_ingredients == ["eggs", "cheese"]

    def test_session_model_has_interaction_fields(self):
        s = Session(uid="u1")
        assert s.interaction_mode == "voice_video_call"
        assert s.allow_text_input is False

    def test_voice_only_interaction_mode(self):
        body = SessionCreate(interaction_mode="voice_only")
        assert body.interaction_mode == "voice_only"
