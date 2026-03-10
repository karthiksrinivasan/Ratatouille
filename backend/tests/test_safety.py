"""Tests for safety constraints in freestyle mode (Epic 9, D9.9)."""

from app.agents.safety import check_safety_triggers, assess_confidence


class TestCheckSafetyTriggers:
    """Verify check_safety_triggers flags dangerous cooking situations."""

    def test_deep_fryer_with_water(self):
        """'deep fryer with water' should flag 'deep fry'."""
        warnings = check_safety_triggers("I'm using a deep fryer with water nearby")
        triggers = [w["trigger"] for w in warnings]
        assert "deep fry" in triggers
        assert any("water" in w["warning"].lower() for w in warnings)

    def test_fire_in_pan(self):
        """'there's a fire in the pan' should flag 'fire'."""
        warnings = check_safety_triggers("there's a fire in the pan!")
        triggers = [w["trigger"] for w in warnings]
        assert "fire" in triggers
        assert any("grease fire" in w["warning"].lower() for w in warnings)

    def test_raw_chicken_temperature(self):
        """Raw chicken should trigger safe-temperature warning."""
        warnings = check_safety_triggers("I'm handling raw chicken")
        triggers = [w["trigger"] for w in warnings]
        assert "raw chicken" in triggers
        assert any("165" in w["warning"] for w in warnings)

    def test_hot_oil_warning(self):
        """Hot oil should trigger splatter warning."""
        warnings = check_safety_triggers("the hot oil is smoking")
        triggers = [w["trigger"] for w in warnings]
        assert "hot oil" in triggers

    def test_boiling_warning(self):
        """Boiling should trigger boil-over warning."""
        warnings = check_safety_triggers("the water is boiling over")
        triggers = [w["trigger"] for w in warnings]
        assert "boiling" in triggers

    def test_safe_input_no_warnings(self):
        """Normal cooking text should not trigger any warnings."""
        warnings = check_safety_triggers("I'm chopping onions for the salad")
        assert len(warnings) == 0

    def test_multiple_triggers(self):
        """Text with multiple hazards should return multiple warnings."""
        warnings = check_safety_triggers(
            "I'm deep frying chicken and there's a fire on the stove"
        )
        triggers = [w["trigger"] for w in warnings]
        assert "deep fry" in triggers
        assert "fire" in triggers
        assert len(warnings) >= 2

    def test_case_insensitive(self):
        """Should match regardless of case."""
        warnings = check_safety_triggers("DEEP FRY this in HOT OIL")
        triggers = [w["trigger"] for w in warnings]
        assert "deep fry" in triggers
        assert "hot oil" in triggers

    def test_all_warnings_have_priority(self):
        """Every warning should include a priority field."""
        warnings = check_safety_triggers("raw chicken in hot oil near a fire")
        for w in warnings:
            assert "priority" in w
            assert w["priority"] == "high"


class TestAssessConfidence:
    """Verify confidence assessment logic."""

    def test_high_confidence_with_full_context(self):
        ctx = {
            "dish_goal": "pasta carbonara",
            "available_ingredients": ["pasta", "eggs", "cheese", "bacon"],
            "time_budget_minutes": 30,
            "equipment": ["pot", "pan"],
        }
        assert assess_confidence(ctx) == "high"

    def test_low_confidence_with_empty_context(self):
        assert assess_confidence({}) == "low"

    def test_medium_confidence_with_partial_context(self):
        ctx = {
            "dish_goal": "something with eggs",
        }
        assert assess_confidence(ctx) == "medium"
