"""Tests for Epic 7, Task 7.9 — Demo script validation."""

import pytest

from app.demo_script import (
    ALL_SUCCESS_CRITERIA,
    ALL_UX_REQUIREMENTS,
    DEMO_ACTS,
    DEMO_MAX_RUNTIME_SECONDS,
    DEMO_RECIPE_ID,
    FALLBACK_TALKING_POINTS,
    validate_demo_coverage,
)


class TestDemoCoverage:
    """Validate that the demo script covers all requirements."""

    def test_validate_demo_coverage_returns_valid(self):
        result = validate_demo_coverage()
        assert result["valid"] is True, (
            f"Demo script is not valid. "
            f"Missing UX: {result['ux_missing']}, "
            f"Missing SC: {result['sc_missing']}, "
            f"Fits time cap: {result['fits_time_cap']}"
        )

    def test_all_14_ux_requirements_covered(self):
        result = validate_demo_coverage()
        assert result["all_ux_covered"] is True, (
            f"Missing UX requirements: {result['ux_missing']}"
        )
        assert len(result["ux_covered"]) == 14

    def test_all_6_success_criteria_covered(self):
        result = validate_demo_coverage()
        assert result["all_sc_covered"] is True, (
            f"Missing success criteria: {result['sc_missing']}"
        )
        assert len(result["sc_covered"]) == 6

    def test_demo_duration_fits_under_4_minutes(self):
        result = validate_demo_coverage()
        assert result["fits_time_cap"] is True, (
            f"Demo max duration {result['duration_range'][1]}s "
            f"exceeds cap of {DEMO_MAX_RUNTIME_SECONDS}s"
        )
        _, max_duration = result["duration_range"]
        assert max_duration <= DEMO_MAX_RUNTIME_SECONDS

    def test_fallback_talking_points_exist(self):
        expected_keys = [
            "scan_fails",
            "voice_fails",
            "vision_fails",
            "guide_image_fails",
            "timer_fails",
            "gemini_rate_limit",
        ]
        for key in expected_keys:
            assert key in FALLBACK_TALKING_POINTS, (
                f"Missing fallback talking point: {key}"
            )
            assert len(FALLBACK_TALKING_POINTS[key]) > 0, (
                f"Fallback talking point '{key}' is empty"
            )

    def test_demo_recipe_id_matches_seed(self):
        assert DEMO_RECIPE_ID == "demo-aglio-e-olio"

    def test_each_act_has_beats(self):
        for act in DEMO_ACTS:
            assert len(act["beats"]) > 0, (
                f"Act {act['act']} ('{act['title']}') has no beats"
            )

    def test_demo_acts_has_5_acts(self):
        assert len(DEMO_ACTS) == 5, (
            f"Expected 5 acts (0-4), got {len(DEMO_ACTS)}"
        )
        act_numbers = [act["act"] for act in DEMO_ACTS]
        assert act_numbers == [0, 1, 2, 3, 4], (
            f"Act numbers should be [0, 1, 2, 3, 4], got {act_numbers}"
        )
