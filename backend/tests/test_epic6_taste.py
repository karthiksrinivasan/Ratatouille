"""Tests for Epic 6 — Taste Coach Agent (Task 6.6)."""

import pytest


class TestTasteCoach:
    def test_imports(self):
        from app.agents.taste import (
            get_taste_dimensions,
            get_diagnostic_questions,
            determine_cooking_stage,
            get_stage_advice,
            TASTE_DIMENSIONS,
            DIAGNOSTIC_QUESTIONS,
            TASTE_COACH_INSTRUCTION,
        )
        assert callable(get_taste_dimensions)
        assert callable(get_diagnostic_questions)
        assert callable(determine_cooking_stage)
        assert callable(get_stage_advice)

    def test_taste_dimensions(self):
        from app.agents.taste import get_taste_dimensions
        dims = get_taste_dimensions()
        assert len(dims) == 5
        names = {d["name"] for d in dims}
        assert names == {"salt", "acid", "sweet", "fat", "umami"}

    def test_diagnostic_questions(self):
        from app.agents.taste import get_diagnostic_questions
        questions = get_diagnostic_questions()
        assert len(questions) == 3
        assert "flat" in questions[0]["question"].lower()
        assert "sharp" in questions[1]["question"].lower()
        assert "one-note" in questions[2]["question"].lower()

    def test_cooking_stage_early(self):
        from app.agents.taste import determine_cooking_stage
        assert determine_cooking_stage(1, 6) == "early"

    def test_cooking_stage_mid(self):
        from app.agents.taste import determine_cooking_stage
        assert determine_cooking_stage(3, 6) == "mid"

    def test_cooking_stage_late(self):
        from app.agents.taste import determine_cooking_stage
        assert determine_cooking_stage(5, 6) == "late"
        assert determine_cooking_stage(6, 6) == "late"

    def test_cooking_stage_zero_steps(self):
        from app.agents.taste import determine_cooking_stage
        assert determine_cooking_stage(1, 0) == "mid"

    def test_stage_advice_early(self):
        from app.agents.taste import get_stage_advice
        advice = get_stage_advice("early")
        assert "bold" in advice.lower()

    def test_stage_advice_mid(self):
        from app.agents.taste import get_stage_advice
        advice = get_stage_advice("mid")
        assert "moderate" in advice.lower()

    def test_stage_advice_late(self):
        from app.agents.taste import get_stage_advice
        advice = get_stage_advice("late")
        assert "small" in advice.lower()

    def test_instruction_content(self):
        from app.agents.taste import TASTE_COACH_INSTRUCTION
        assert "salt" in TASTE_COACH_INSTRUCTION
        assert "acid" in TASTE_COACH_INSTRUCTION
        assert "TR-01" in TASTE_COACH_INSTRUCTION
        assert "TR-02" in TASTE_COACH_INSTRUCTION
        assert "TR-03" in TASTE_COACH_INSTRUCTION
