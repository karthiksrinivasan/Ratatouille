"""Tests for Task 1.3 — Pydantic models matching Firestore schema."""
from datetime import datetime


def test_user_profile_schema():
    from app.models.user import UserProfile

    u = UserProfile(uid="abc123")
    assert u.uid == "abc123"
    assert u.preferences == {}
    assert u.calibration_summary == {}
    assert u.display_name is None


def test_user_memory_schema():
    from app.models.user import UserMemory

    m = UserMemory(observation="Prefers medium-rare")
    assert m.observation == "Prefers medium-rare"
    assert m.confirmed is False
    assert m.confidence == 0.0


def test_recipe_schema():
    from app.models.recipe import Recipe

    r = Recipe(title="Pasta", uid="u1")
    assert r.title == "Pasta"
    assert r.source_type == "manual"
    assert r.recipe_id  # Should have a UUID default
    assert isinstance(r.created_at, datetime)
    assert r.ingredients == []
    assert r.steps == []
    assert r.technique_tags == []
    assert r.ingredients_normalized == []


def test_recipe_step_schema():
    from app.models.recipe import RecipeStep

    s = RecipeStep(step_number=1, instruction="Boil water")
    assert s.step_number == 1
    assert s.technique_tags == []
    assert s.is_parallel is False


def test_ingredient_schema():
    from app.models.recipe import Ingredient

    i = Ingredient(name="onion")
    assert i.name == "onion"
    assert i.name_normalized == ""


def test_session_schema():
    from app.models.session import Session

    s = Session(uid="u1", recipe_id="r1")
    assert s.status == "created"
    assert s.session_id  # UUID default
    assert s.current_step == 0
    assert s.started_at is None
    assert s.ended_at is None


def test_session_event_schema():
    from app.models.session import SessionEvent

    e = SessionEvent(type="voice_query")
    assert e.type == "voice_query"
    assert e.event_id  # UUID default
    assert isinstance(e.timestamp, datetime)


def test_guide_image_schema():
    from app.models.session import GuideImage

    g = GuideImage(step_id="s1", stage_label="searing")
    assert g.step_id == "s1"
    assert g.cue_overlays == []


def test_inventory_scan_schema():
    from app.models.inventory import InventoryScan

    scan = InventoryScan(uid="u1", source="fridge")
    assert scan.source == "fridge"
    assert scan.scan_id  # UUID default
    assert scan.detected_ingredients == []
    assert scan.confidence_map == {}
    assert scan.confirmed_ingredients == []
    assert scan.status == "pending"


def test_detected_ingredient_schema():
    from app.models.inventory import DetectedIngredient

    d = DetectedIngredient(name="carrot", name_normalized="carrot", confidence=0.95, source_image_index=0)
    assert d.confidence == 0.95


def test_recipe_suggestion_schema():
    from app.models.inventory import RecipeSuggestion

    s = RecipeSuggestion(
        source_type="saved_recipe",
        title="Carrot Soup",
        match_score=0.8,
        source_label="Saved",
    )
    assert s.match_score == 0.8
    assert s.missing_ingredients == []
    assert s.suggestion_id  # UUID default


def test_cooking_process_schema():
    from app.models.process import Process

    p = Process(session_id="s1", name="Boiling pasta", step_number=3)
    assert p.state == "pending"
    assert p.priority == "P2"
    assert p.buddy_managed is False
    assert p.process_id  # auto-generated
