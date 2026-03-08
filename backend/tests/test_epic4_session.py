"""Tests for Epic 4 — Live Cooking Session & Voice Loop.

Covers: session models, voice modes, calibration engine, degradation manager,
sessions service, orchestrator, and live WebSocket router.
"""

import pytest
from datetime import datetime


# ---------------------------------------------------------------------------
# Task 4.1 / 4.2 — Session models
# ---------------------------------------------------------------------------

class TestSessionModels:
    def test_session_defaults(self):
        from app.models.session import Session
        s = Session(uid="u1", recipe_id="r1")
        assert s.status == "created"
        assert s.current_step == 0
        assert s.calibration_state == {}
        assert s.started_at is None
        assert s.ended_at is None
        assert s.session_id  # UUID generated

    def test_mode_settings_defaults(self):
        from app.models.session import ModeSettings
        m = ModeSettings()
        assert m.ambient_listen is False
        assert m.phone_position == "counter"

    def test_session_create_model(self):
        from app.models.session import SessionCreate
        sc = SessionCreate(recipe_id="r123")
        assert sc.recipe_id == "r123"
        assert sc.mode_settings is None

    def test_session_create_with_mode_settings(self):
        from app.models.session import SessionCreate, ModeSettings
        sc = SessionCreate(
            recipe_id="r123",
            mode_settings=ModeSettings(ambient_listen=True, phone_position="mounted"),
        )
        assert sc.mode_settings.ambient_listen is True
        assert sc.mode_settings.phone_position == "mounted"

    def test_session_event_defaults(self):
        from app.models.session import SessionEvent
        e = SessionEvent(type="voice_query")
        assert e.type == "voice_query"
        assert e.event_id  # UUID generated
        assert isinstance(e.timestamp, datetime)
        assert e.payload == {}

    def test_guide_image_defaults(self):
        from app.models.session import GuideImage
        g = GuideImage(step_id="s1", stage_label="searing")
        assert g.guide_id is None
        assert g.cue_overlays == []


# ---------------------------------------------------------------------------
# Task 4.6 — Voice modes
# ---------------------------------------------------------------------------

class TestVoiceModeManager:
    def _make(self):
        from app.agents.voice_modes import VoiceModeManager
        return VoiceModeManager()

    def test_default_state(self):
        vm = self._make()
        assert vm.ambient_enabled is False
        assert vm.buddy_speaking is False
        assert vm.last_interrupted_response is None

    def test_classify_voice_query(self):
        vm = self._make()
        assert vm.classify_input("voice_query") == "VM-02"

    def test_classify_vision_check(self):
        vm = self._make()
        assert vm.classify_input("vision_check") == "VM-03"

    def test_classify_ambient_audio(self):
        vm = self._make()
        vm.ambient_enabled = True
        assert vm.classify_input("voice_audio") == "VM-01"

    def test_classify_barge_in_when_speaking(self):
        vm = self._make()
        vm.buddy_speaking = True
        assert vm.classify_input("voice_query") == "VM-04"
        assert vm.classify_input("voice_audio") == "VM-04"
        assert vm.classify_input("barge_in") == "VM-04"

    def test_ambient_filter_cooking_signal(self):
        vm = self._make()
        assert vm.should_respond_ambient("is it done yet?") is True
        assert vm.should_respond_ambient("how long do I cook this?") is True

    def test_ambient_filter_non_cooking(self):
        vm = self._make()
        assert vm.should_respond_ambient("what's the weather like?") is False

    def test_is_resume_request(self):
        vm = self._make()
        assert vm.is_resume_request("continue") is True
        assert vm.is_resume_request("what were you saying") is True
        assert vm.is_resume_request("repeat quickly") is True
        assert vm.is_resume_request("how much salt?") is False

    def test_start_speaking_sets_state(self):
        vm = self._make()
        vm.start_speaking("Here's how to dice the onion...")
        assert vm.buddy_speaking is True
        assert vm.last_interrupted_response == "Here's how to dice the onion..."

    def test_interrupt_returns_preview(self):
        vm = self._make()
        vm.start_speaking("A" * 200)
        preview = vm.interrupt()
        assert vm.buddy_speaking is False
        assert preview is not None
        assert len(preview) == 100  # Truncated to 100 chars

    def test_interrupt_when_not_speaking(self):
        vm = self._make()
        assert vm.interrupt() is None

    def test_consume_interrupted_clears_state(self):
        vm = self._make()
        vm.start_speaking("Test response")
        vm.interrupt()
        full_text = vm.consume_interrupted()
        assert full_text == "Test response"
        assert vm.last_interrupted_response is None
        # Second consume returns None
        assert vm.consume_interrupted() is None

    def test_get_mode_state(self):
        vm = self._make()
        state = vm.get_mode_state()
        assert state["ambient_listen"] is False
        assert state["buddy_speaking"] is False
        assert state["has_interrupted_content"] is False


# ---------------------------------------------------------------------------
# Task 4.7 — Calibration engine
# ---------------------------------------------------------------------------

class TestCalibrationEngine:
    def _make(self):
        from app.agents.calibration import CalibrationEngine
        return CalibrationEngine()

    def test_default_level(self):
        cal = self._make()
        assert cal.get_level() == "standard"

    def test_skip_signal_compresses(self):
        cal = self._make()
        cal.process_signal("skips")
        assert cal.get_level() == "compressed"

    def test_i_know_signal_compresses(self):
        cal = self._make()
        cal.process_signal("i_know_signals")
        assert cal.get_level() == "compressed"

    def test_clarification_expands(self):
        cal = self._make()
        cal.process_signal("clarification_asks")
        assert cal.get_level() == "detailed"

    def test_why_question_expands(self):
        cal = self._make()
        cal.process_signal("why_questions")
        assert cal.get_level() == "detailed"

    def test_error_signal_expands(self):
        cal = self._make()
        cal.process_signal("errors")
        assert cal.get_level() == "detailed"

    def test_per_technique_level(self):
        cal = self._make()
        cal.process_signal("skips", technique="sauteing")
        assert cal.get_level("sauteing") == "compressed"
        assert cal.get_level() == "standard"  # Global unchanged

    def test_does_not_over_compress(self):
        cal = self._make()
        cal.process_signal("skips")  # standard -> compressed
        cal.process_signal("skips")  # already compressed, stays
        assert cal.get_level() == "compressed"

    def test_does_not_over_expand(self):
        cal = self._make()
        cal.process_signal("clarification_asks")  # standard -> detailed
        cal.process_signal("clarification_asks")  # already detailed, stays
        assert cal.get_level() == "detailed"

    def test_detect_signal_skip(self):
        cal = self._make()
        assert cal.detect_signal_from_text("I know how to do this") == "i_know_signals"
        assert cal.detect_signal_from_text("skip this step") == "i_know_signals"
        assert cal.detect_signal_from_text("next") == "i_know_signals"

    def test_detect_signal_why(self):
        cal = self._make()
        assert cal.detect_signal_from_text("why do we need to blanch?") == "why_questions"
        assert cal.detect_signal_from_text("Why should I use butter?") == "why_questions"

    def test_detect_signal_clarification(self):
        cal = self._make()
        assert cal.detect_signal_from_text("what do you mean by julienne?") == "clarification_asks"
        assert cal.detect_signal_from_text("I don't understand") == "clarification_asks"

    def test_detect_signal_error(self):
        cal = self._make()
        assert cal.detect_signal_from_text("I messed up the sauce") == "errors"
        assert cal.detect_signal_from_text("it burned!") == "errors"

    def test_detect_signal_none(self):
        cal = self._make()
        assert cal.detect_signal_from_text("looks good to me") is None

    def test_is_critical_moment(self):
        cal = self._make()
        step = {"technique_tags": ["frying"], "instruction": "Deep fry the tempura"}
        assert cal.is_critical_moment(step) is True

    def test_is_not_critical_moment(self):
        cal = self._make()
        step = {"technique_tags": ["mixing"], "instruction": "Mix the batter"}
        assert cal.is_critical_moment(step) is False

    def test_critical_moment_from_instruction(self):
        cal = self._make()
        step = {"technique_tags": [], "instruction": "Be careful with the hot oil"}
        assert cal.is_critical_moment(step) is True

    def test_instruction_modifier(self):
        cal = self._make()
        assert "Standard" in cal.get_instruction_modifier()
        cal.process_signal("clarification_asks")
        assert "thoroughly" in cal.get_instruction_modifier()

    def test_serialize_roundtrip(self):
        cal = self._make()
        cal.process_signal("skips", technique="sauteing")
        cal.process_signal("clarification_asks")
        data = cal.to_dict()

        from app.agents.calibration import CalibrationEngine
        restored = CalibrationEngine.from_dict(data)
        assert restored.global_level == cal.global_level
        assert restored.technique_levels == cal.technique_levels
        assert restored.signal_counts == cal.signal_counts


# ---------------------------------------------------------------------------
# Task 4.9 — Degradation manager
# ---------------------------------------------------------------------------

class TestDegradationManager:
    def _make(self):
        from app.agents.degradation import DegradationManager
        return DegradationManager()

    def test_default_full_multimodal(self):
        dm = self._make()
        assert dm.get_response_modality() == "full_multimodal"

    def test_vision_failure_threshold(self):
        dm = self._make()
        dm.report_vision_failure()
        dm.report_vision_failure()
        assert dm.vision_available is True
        dm.report_vision_failure()
        assert dm.vision_available is False
        assert dm.get_response_modality() == "voice_text"

    def test_audio_failure_threshold(self):
        dm = self._make()
        for _ in range(3):
            dm.report_audio_failure()
        assert dm.audio_available is False
        assert dm.get_response_modality() == "text_only"

    def test_vision_recovery(self):
        dm = self._make()
        for _ in range(3):
            dm.report_vision_failure()
        assert dm.vision_available is False
        dm.report_vision_success()
        assert dm.vision_available is True
        assert dm.consecutive_vision_failures == 0

    def test_audio_recovery(self):
        dm = self._make()
        for _ in range(3):
            dm.report_audio_failure()
        assert dm.audio_available is False
        dm.report_audio_success()
        assert dm.audio_available is True

    def test_vision_fallback_text(self):
        dm = self._make()
        step = {"instruction": "Sear the steak until golden"}
        text = dm.get_vision_fallback_text(step)
        assert "can't see" in text.lower()
        assert "Sear the steak" in text

    def test_degradation_notice_full(self):
        dm = self._make()
        assert dm.get_degradation_notice() == {}

    def test_degradation_notice_voice_text(self):
        dm = self._make()
        for _ in range(3):
            dm.report_vision_failure()
        notice = dm.get_degradation_notice()
        assert notice["type"] == "mode_update"
        assert notice["modality"] == "voice_text"
        assert notice["vision_available"] is False

    def test_degradation_notice_text_only(self):
        dm = self._make()
        for _ in range(3):
            dm.report_audio_failure()
        notice = dm.get_degradation_notice()
        assert notice["modality"] == "text_only"
        assert notice["audio_available"] is False


# ---------------------------------------------------------------------------
# Task 4.4 — Orchestrator (unit-level)
# ---------------------------------------------------------------------------

class TestSessionOrchestrator:
    def _make(self):
        """Create an orchestrator with mock recipe and session."""
        from app.agents.orchestrator import SessionOrchestrator
        from unittest.mock import MagicMock

        mock_agent = MagicMock()
        session_state = {
            "recipe": {
                "title": "Test Pasta",
                "steps": [
                    {"step_number": 1, "instruction": "Boil water", "technique_tags": ["boiling"]},
                    {"step_number": 2, "instruction": "Cook pasta", "technique_tags": ["boiling"]},
                    {"step_number": 3, "instruction": "Make sauce", "technique_tags": ["sauteing"]},
                ],
                "ingredients": [{"name": "pasta"}, {"name": "water"}],
            },
            "recipe_title": "Test Pasta",
            "current_step": 1,
            "total_steps": 3,
            "ambient_listen": False,
            "calibration_level": "standard",
            "calibration_state": {},
            "uid": "test-user",
            "session_id": "test-session",
        }
        return SessionOrchestrator(agent=mock_agent, session_state=session_state)

    @pytest.mark.asyncio
    async def test_advance_step(self):
        orch = self._make()
        result = await orch.advance_step()
        assert result["type"] == "buddy_message"
        assert result["step"] == 2
        assert orch.state["current_step"] == 2

    @pytest.mark.asyncio
    async def test_advance_past_last_step(self):
        orch = self._make()
        orch.state["current_step"] = 3
        result = await orch.advance_step()
        assert "did it" in result["text"].lower() or "all" in result["text"].lower()
        assert result["step"] == 3

    @pytest.mark.asyncio
    async def test_set_ambient_mode(self):
        orch = self._make()
        await orch.set_ambient_mode(True)
        assert orch.state["ambient_listen"] is True
        assert orch.voice_mode.ambient_enabled is True

    def test_classify_input_delegates(self):
        orch = self._make()
        assert orch.classify_input("voice_query") == "VM-02"
        assert orch.classify_input("vision_check") == "VM-03"

    def test_should_respond_ambient(self):
        orch = self._make()
        assert orch.should_respond_ambient("is it done?") is True
        assert orch.should_respond_ambient("nice weather") is False

    @pytest.mark.asyncio
    async def test_handle_vision_check_degraded(self):
        orch = self._make()
        orch.degradation.vision_available = False
        result = await orch.handle_vision_check("gs://test/frame.jpg")
        assert result["confidence"] == "unavailable"
        assert "can't see" in result["assessment"].lower()

    @pytest.mark.asyncio
    async def test_handle_vision_check_available(self):
        orch = self._make()
        result = await orch.handle_vision_check("gs://test/frame.jpg")
        assert result["confidence"] == "pending"

    @pytest.mark.asyncio
    async def test_handle_audio_chunk_none(self):
        orch = self._make()
        result = await orch.handle_audio_chunk(None)
        assert result is None

    def test_get_mode_state(self):
        orch = self._make()
        state = orch.get_mode_state()
        assert "ambient_listen" in state
        assert "buddy_speaking" in state

    @pytest.mark.asyncio
    async def test_handle_resume_nothing(self):
        orch = self._make()
        result = await orch.handle_resume()
        assert result["type"] == "buddy_response"
        assert "nothing" in result["text"].lower()

    def test_calibration_restored_from_state(self):
        from app.agents.orchestrator import SessionOrchestrator
        from unittest.mock import MagicMock

        mock_agent = MagicMock()
        session_state = {
            "recipe": {"title": "Test", "steps": []},
            "current_step": 1,
            "total_steps": 0,
            "ambient_listen": False,
            "calibration_level": "standard",
            "calibration_state": {
                "global_level": "compressed",
                "technique_levels": {"sauteing": "detailed"},
                "signal_counts": {"skips": 3, "clarification_asks": 0,
                                   "i_know_signals": 0, "errors": 0, "why_questions": 0},
            },
        }
        orch = SessionOrchestrator(agent=mock_agent, session_state=session_state)
        assert orch.calibration.global_level == "compressed"
        assert orch.calibration.get_level("sauteing") == "detailed"


# ---------------------------------------------------------------------------
# Task 4.8 — Session service functions
# ---------------------------------------------------------------------------

class TestSessionService:
    def test_service_functions_importable(self):
        from app.services.sessions import (
            create_session_record,
            persist_session_state,
            log_session_event,
        )
        assert callable(create_session_record)
        assert callable(persist_session_state)
        assert callable(log_session_event)


# ---------------------------------------------------------------------------
# Task 4.5 — Live audio session
# ---------------------------------------------------------------------------

class TestLiveAudioSession:
    def test_importable(self):
        from app.agents.live_audio import LiveAudioSession
        session = LiveAudioSession(
            recipe={"title": "Test", "steps": []},
            session_state={"current_step": 1},
        )
        assert session.live_session is None

    @pytest.mark.asyncio
    async def test_close_without_connect(self):
        from app.agents.live_audio import LiveAudioSession
        session = LiveAudioSession(
            recipe={"title": "Test", "steps": []},
            session_state={"current_step": 1},
        )
        await session.close()  # Should not raise

    @pytest.mark.asyncio
    async def test_send_audio_without_connect(self):
        from app.agents.live_audio import LiveAudioSession
        session = LiveAudioSession(
            recipe={"title": "Test", "steps": []},
            session_state={"current_step": 1},
        )
        await session.send_audio("dGVzdA==")  # Should not raise


# ---------------------------------------------------------------------------
# Task 4.10 — Router registration
# ---------------------------------------------------------------------------

class TestRouterRegistration:
    def test_session_routes_registered(self):
        from app.main import app
        routes = [r.path for r in app.routes]
        assert "/v1/sessions" in routes or any("/sessions" in r for r in routes)

    def test_live_routes_registered(self):
        from app.main import app
        routes = [r.path for r in app.routes]
        assert any("live" in str(r) for r in routes)
