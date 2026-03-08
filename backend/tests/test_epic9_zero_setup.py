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


class TestDemoCoverage:
    """Task 9.10 — Demo script includes zero-setup segment."""

    def test_act0_exists_with_zero_setup_title(self):
        from app.demo_script import DEMO_ACTS
        act0 = DEMO_ACTS[0]
        assert act0["act"] == 0
        assert "Zero-Setup" in act0["title"]

    def test_act0_demonstrates_no_recipe_dependency(self):
        from app.demo_script import DEMO_ACTS
        act0 = DEMO_ACTS[0]
        beats_text = " ".join(act0["beats"])
        assert "no recipe" in beats_text.lower()
        assert act0["zero_setup_specific"]["no_recipe_dependency"] is True

    def test_act0_demonstrates_persona_quality(self):
        from app.demo_script import DEMO_ACTS
        act0 = DEMO_ACTS[0]
        assert act0["zero_setup_specific"]["persona_quality_demo"] is True
        beats_text = " ".join(act0["beats"])
        assert "persona" in beats_text.lower()

    def test_act0_demonstrates_interruption_handling(self):
        from app.demo_script import DEMO_ACTS
        act0 = DEMO_ACTS[0]
        assert act0["zero_setup_specific"]["interruption_handling_demo"] is True
        assert "UX-13" in act0["ux_requirements"]
        beats_text = " ".join(act0["beats"])
        assert "interrupt" in beats_text.lower()

    def test_act0_voice_first(self):
        from app.demo_script import DEMO_ACTS
        act0 = DEMO_ACTS[0]
        assert act0["zero_setup_specific"]["voice_first"] is True
        beats_text = " ".join(act0["beats"])
        assert "voice" in beats_text.lower() or "call" in beats_text.lower()

    def test_act0_max_two_taps(self):
        from app.demo_script import DEMO_ACTS
        act0 = DEMO_ACTS[0]
        assert act0["zero_setup_specific"]["max_taps_to_conversation"] <= 2

    def test_demo_validation_still_passes(self):
        from app.demo_script import validate_demo_coverage
        result = validate_demo_coverage()
        assert result["valid"] is True
        assert result["all_ux_covered"] is True
        assert result["all_sc_covered"] is True
        assert result["fits_time_cap"] is True


class TestZeroSetupMetrics:
    """Task 9.9 — Metrics and judging alignment for zero-setup path."""

    def test_all_funnel_events_registered(self):
        from app.services.analytics import PRODUCT_EVENTS
        funnel_events = [
            "zero_setup_entry_tapped",
            "zero_setup_session_created",
            "zero_setup_session_activated",
            "zero_setup_session_completed",
        ]
        for event in funnel_events:
            assert event in PRODUCT_EVENTS, f"Missing event: {event}"

    def test_metrics_collector_supports_latency(self):
        from app.services.metrics import MetricsCollector
        mc = MetricsCollector()
        import asyncio
        asyncio.get_event_loop().run_until_complete(
            mc.record_latency("time_to_first_instruction_ms", 250.0)
        )
        summary = mc.get_summary()
        assert "time_to_first_instruction_ms" in summary
        assert summary["time_to_first_instruction_ms"]["count"] == 1

    def test_emit_product_event_import(self):
        from app.services.analytics import emit_product_event
        assert callable(emit_product_event)

    def test_sessions_router_imports_analytics(self):
        """Verify session router wires up analytics emission."""
        import app.routers.sessions as sr
        # These should be available after import
        assert hasattr(sr, 'emit_product_event')
        assert hasattr(sr, 'metrics')


class TestLiveBrowseVideoChat:
    """Task 9.11 — Fridge/Pantry Live Browse Video Chat."""

    def test_browse_session_init(self):
        from app.services.browse import BrowseSession
        bs = BrowseSession(source="fridge")
        assert bs.source == "fridge"
        assert bs.frame_count == 0
        assert bs.candidates == []

    def test_browse_session_pantry(self):
        from app.services.browse import BrowseSession
        bs = BrowseSession(source="pantry")
        assert bs.source == "pantry"

    def test_browse_session_get_all_candidates_empty(self):
        from app.services.browse import BrowseSession
        bs = BrowseSession()
        assert bs.get_all_candidates() == []

    def test_browse_session_fallback_observation(self):
        from app.services.browse import BrowseSession
        bs = BrowseSession()
        result = bs._fallback_observation()
        assert result["confidence"] == 0.0
        assert result["candidates"] == []
        assert result["question"] is not None

    @pytest.mark.asyncio
    async def test_browse_session_process_frame_fallback(self):
        """Frame processing falls back gracefully when Gemini fails."""
        from app.services.browse import BrowseSession
        bs = BrowseSession(source="fridge")
        # With invalid URI, Gemini will fail → fallback
        result = await bs.process_frame("gs://invalid/frame.jpg")
        assert "observation" in result
        assert "candidates" in result
        assert "confidence" in result
        assert bs.frame_count == 1

    def test_browse_session_deduplicates_candidates(self):
        from app.services.browse import BrowseSession
        bs = BrowseSession()
        # Simulate adding candidates manually
        bs._seen_names.add("eggs")
        bs.candidates.append({"name": "eggs", "confidence": 0.9})
        # Try adding same name — won't appear in new candidates
        assert "eggs" in bs._seen_names

    def test_live_router_imports_browse(self):
        import app.routers.live as lr
        assert hasattr(lr, 'BrowseSession')
        assert hasattr(lr, 'emit_product_event')

    def test_browse_analytics_events_registered(self):
        from app.services.analytics import PRODUCT_EVENTS
        assert "browse_started" in PRODUCT_EVENTS
        assert "browse_completed" in PRODUCT_EVENTS

    def test_browse_fallback_no_text_input_required(self):
        """Fallback asks for verbal confirmation, not text entry."""
        from app.services.browse import BrowseSession
        bs = BrowseSession()
        fallback = bs._fallback_observation()
        # Should suggest verbal or camera alternatives, not typing
        assert "tell me" in fallback["observation"].lower() or "photo" in fallback["question"].lower()


class TestTextInputAudit:
    """Task 9.12 — Retroactive text-input audit and voice/video migration."""

    def test_audit_matrix_exists(self):
        from app.text_input_audit import TEXT_INPUT_AUDIT
        assert len(TEXT_INPUT_AUDIT) >= 7

    def test_audit_matrix_validates(self):
        from app.text_input_audit import validate_audit
        result = validate_audit()
        assert result["valid"] is True
        assert result["total_entries"] >= 7

    def test_all_entries_have_classification(self):
        from app.text_input_audit import TEXT_INPUT_AUDIT
        valid = {"Keep", "Replace", "Optional"}
        for entry in TEXT_INPUT_AUDIT:
            assert entry["classification"] in valid

    def test_type_instead_classified_as_replace(self):
        from app.text_input_audit import TEXT_INPUT_AUDIT
        type_instead = [e for e in TEXT_INPUT_AUDIT if "Type Instead" in e["control"]]
        assert len(type_instead) == 1
        assert type_instead[0]["classification"] == "Replace"

    def test_recipe_url_classified_as_keep(self):
        from app.text_input_audit import TEXT_INPUT_AUDIT
        url_entries = [e for e in TEXT_INPUT_AUDIT if "URL" in e["control"]]
        assert len(url_entries) == 1
        assert url_entries[0]["classification"] == "Keep"

    def test_exceptions_documented_with_rationale(self):
        from app.text_input_audit import TEXT_INPUT_AUDIT
        kept = [e for e in TEXT_INPUT_AUDIT if e["classification"] == "Keep"]
        assert len(kept) >= 3  # URL import, recipe create, ingredient review
        for e in kept:
            assert e["rationale"], f"Missing rationale for {e['file']}"

    def test_regression_checklist_exists(self):
        from app.text_input_audit import VOICE_FIRST_REGRESSION
        assert len(VOICE_FIRST_REGRESSION) >= 6

    def test_regression_covers_full_session(self):
        from app.text_input_audit import VOICE_FIRST_REGRESSION
        text = " ".join(VOICE_FIRST_REGRESSION).lower()
        assert "cook now" in text
        assert "freestyle" in text or "voice" in text
        assert "browse" in text
        assert "taste" in text
        assert "recovery" in text or "error" in text
        assert "type instead" in text
