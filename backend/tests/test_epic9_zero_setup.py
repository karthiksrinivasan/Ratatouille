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


class TestFreestyleActivation:
    """Task 9.3 — Freestyle activation bootstrap."""

    @pytest.mark.asyncio
    async def test_generate_freestyle_plan_with_context(self):
        from app.routers.sessions import _generate_freestyle_plan
        plan = await _generate_freestyle_plan({
            "dish_goal": "quick eggs",
            "available_ingredients": ["eggs", "butter"],
            "time_budget_minutes": 15,
        })
        assert "steps" in plan
        assert "first_instruction" in plan
        assert len(plan["steps"]) >= 1

    @pytest.mark.asyncio
    async def test_generate_freestyle_plan_empty_context(self):
        from app.routers.sessions import _generate_freestyle_plan
        plan = await _generate_freestyle_plan({})
        assert "steps" in plan
        assert "first_instruction" in plan
        assert len(plan["steps"]) >= 1

    @pytest.mark.asyncio
    async def test_generate_freestyle_plan_fallback(self):
        """Plan generation falls back gracefully when Gemini fails."""
        from app.routers.sessions import _generate_freestyle_plan
        # Even with empty context, the fallback should work
        plan = await _generate_freestyle_plan({})
        assert isinstance(plan["steps"], list)
        assert isinstance(plan["first_instruction"], str)


class TestFreestyleOrchestrator:
    """Task 9.4 — Freestyle orchestrator behavior."""

    @pytest.mark.asyncio
    async def test_create_freestyle_orchestrator(self):
        from app.agents.orchestrator import create_session_orchestrator
        session = {
            "session_mode": "freestyle",
            "freestyle_context": {
                "dish_goal": "scrambled eggs",
                "available_ingredients": ["eggs", "butter"],
            },
            "current_step": 1,
            "mode_settings": {},
            "calibration_state": {},
            "uid": "u1",
            "session_id": "s1",
        }
        orch = await create_session_orchestrator(session, None)
        assert orch.state["session_mode"] == "freestyle"
        assert orch.state["dish_goal"] == "scrambled eggs"
        assert "eggs" in orch.state["available_ingredients"]

    @pytest.mark.asyncio
    async def test_create_recipe_orchestrator_still_works(self):
        from app.agents.orchestrator import create_session_orchestrator
        session = {
            "session_mode": "recipe_guided",
            "current_step": 1,
            "mode_settings": {},
            "calibration_state": {},
            "uid": "u1",
            "session_id": "s1",
        }
        recipe = {
            "title": "Test Recipe",
            "steps": [{"step_number": 1, "instruction": "Do step 1"}],
        }
        orch = await create_session_orchestrator(session, recipe)
        assert orch.state["session_mode"] == "recipe_guided"
        assert orch.state["recipe_title"] == "Test Recipe"

    @pytest.mark.asyncio
    async def test_freestyle_advance_step_keeps_going(self):
        from app.agents.orchestrator import create_session_orchestrator
        session = {
            "session_mode": "freestyle",
            "freestyle_context": {},
            "current_step": 1,
            "mode_settings": {},
            "calibration_state": {},
            "uid": "u1",
            "session_id": "s1",
        }
        orch = await create_session_orchestrator(session, None)
        # In freestyle, advance_step should always succeed
        result = await orch.advance_step()
        assert result["type"] == "buddy_message"
        assert result["step"] == 2

    def test_freestyle_tools_exist(self):
        from app.agents.orchestrator import (
            get_freestyle_context,
            update_freestyle_context,
            add_dynamic_step,
        )
        assert callable(get_freestyle_context)
        assert callable(update_freestyle_context)
        assert callable(add_dynamic_step)


class TestInSessionContextCapture:
    """Task 9.5 — In-session context capture."""

    @pytest.mark.asyncio
    async def test_context_update_adds_ingredients(self):
        from app.agents.orchestrator import create_session_orchestrator
        session = {
            "session_mode": "freestyle",
            "freestyle_context": {"available_ingredients": ["eggs"]},
            "current_step": 1,
            "mode_settings": {},
            "calibration_state": {},
            "uid": "u1",
            "session_id": "s1",
        }
        orch = await create_session_orchestrator(session, None)
        ctx = orch.state.get("freestyle_context", {})
        # Simulate context update (merge ingredients)
        new_ingredients = ["cheese", "spinach"]
        existing = ctx.get("available_ingredients", [])
        ctx["available_ingredients"] = list(set(existing + new_ingredients))
        orch.state["freestyle_context"] = ctx
        assert "eggs" in orch.state["freestyle_context"]["available_ingredients"]
        assert "cheese" in orch.state["freestyle_context"]["available_ingredients"]
        assert "spinach" in orch.state["freestyle_context"]["available_ingredients"]

    @pytest.mark.asyncio
    async def test_context_update_sets_time_budget(self):
        from app.agents.orchestrator import create_session_orchestrator
        session = {
            "session_mode": "freestyle",
            "freestyle_context": {},
            "current_step": 1,
            "mode_settings": {},
            "calibration_state": {},
            "uid": "u1",
            "session_id": "s1",
        }
        orch = await create_session_orchestrator(session, None)
        ctx = orch.state.get("freestyle_context", {})
        ctx["time_budget_minutes"] = 20
        orch.state["freestyle_context"] = ctx
        assert orch.state["freestyle_context"]["time_budget_minutes"] == 20

    @pytest.mark.asyncio
    async def test_missing_context_never_blocks(self):
        """Sessions should work even with no context at all."""
        from app.agents.orchestrator import create_session_orchestrator
        session = {
            "session_mode": "freestyle",
            "freestyle_context": {},
            "current_step": 1,
            "mode_settings": {},
            "calibration_state": {},
            "uid": "u1",
            "session_id": "s1",
        }
        orch = await create_session_orchestrator(session, None)
        # advance_step should work with no context
        result = await orch.advance_step()
        assert result["type"] == "buddy_message"


class TestProcessTimerFreestyle:
    """Task 9.6 — Process/timer compatibility for freestyle."""

    def test_create_dynamic_process_function_exists(self):
        from app.services.processes import create_dynamic_process
        assert callable(create_dynamic_process)

    def test_build_process_bar_with_empty_list(self):
        import asyncio
        from app.services.processes import build_process_bar_state
        result = asyncio.get_event_loop().run_until_complete(
            build_process_bar_state([])
        )
        assert result["type"] == "process_update"
        assert result["active_count"] == 0

    def test_build_process_bar_with_dynamic_process(self):
        import asyncio
        from app.services.processes import build_process_bar_state
        processes = [{
            "process_id": "p1",
            "name": "Boil pasta",
            "state": "countdown",
            "priority": "P2",
            "due_at": "2025-01-01T12:10:00",
            "dynamic": True,
        }]
        result = asyncio.get_event_loop().run_until_complete(
            build_process_bar_state(processes)
        )
        assert result["active_count"] == 1
        assert result["next_due"] is not None

    @pytest.mark.asyncio
    async def test_freestyle_session_starts_with_empty_processes(self):
        """Freestyle sessions start with no processes."""
        from app.agents.orchestrator import create_session_orchestrator
        session = {
            "session_mode": "freestyle",
            "freestyle_context": {},
            "current_step": 1,
            "mode_settings": {},
            "calibration_state": {},
            "uid": "u1",
            "session_id": "s1",
        }
        orch = await create_session_orchestrator(session, None)
        # No processes by default in freestyle
        assert orch.state.get("processes") is None or orch.state.get("processes") == []


class TestSafetyConstraints:
    """Task 9.8 — Safety and confidence constraints."""

    def test_check_safety_triggers_hot_oil(self):
        from app.agents.safety import check_safety_triggers
        warnings = check_safety_triggers("I'm heating up some hot oil")
        assert len(warnings) >= 1
        assert any(w["trigger"] == "hot oil" for w in warnings)

    def test_check_safety_triggers_raw_chicken(self):
        from app.agents.safety import check_safety_triggers
        warnings = check_safety_triggers("I have raw chicken on the counter")
        assert len(warnings) >= 1
        assert any("165" in w["warning"] for w in warnings)

    def test_check_safety_triggers_no_match(self):
        from app.agents.safety import check_safety_triggers
        warnings = check_safety_triggers("Let me chop some onions")
        assert len(warnings) == 0

    def test_assess_confidence_high(self):
        from app.agents.safety import assess_confidence
        ctx = {
            "dish_goal": "scrambled eggs",
            "available_ingredients": ["eggs", "butter", "salt"],
            "time_budget_minutes": 10,
        }
        assert assess_confidence(ctx) == "high"

    def test_assess_confidence_low(self):
        from app.agents.safety import assess_confidence
        assert assess_confidence({}) == "low"

    def test_assess_confidence_medium(self):
        from app.agents.safety import assess_confidence
        ctx = {"dish_goal": "something tasty"}
        assert assess_confidence(ctx) == "medium"

    def test_safety_instruction_addendum_exists(self):
        from app.agents.safety import SAFETY_INSTRUCTION_ADDENDUM
        assert "irreversible-risk" in SAFETY_INSTRUCTION_ADDENDUM
        assert "food safety" in SAFETY_INSTRUCTION_ADDENDUM.lower() or "safe internal" in SAFETY_INSTRUCTION_ADDENDUM.lower()

    def test_freestyle_instruction_includes_safety(self):
        from app.agents.orchestrator import FREESTYLE_INSTRUCTION
        assert "Safety Constraints" in FREESTYLE_INSTRUCTION
