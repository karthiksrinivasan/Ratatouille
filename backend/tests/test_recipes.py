"""Tests for Epic 2 — Recipe Management & Data Layer.

Covers: Task 2.1 (CRUD endpoints), Task 2.2 (technique tag extraction helper),
        Task 2.3 (URL parse request model), Task 2.4 (ingredient normalization),
        Task 2.5 (ingredient checklist model), Task 2.6 (demo recipe seed data).
"""
import json
from unittest.mock import AsyncMock, patch, MagicMock

import pytest
from fastapi.testclient import TestClient


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture()
def mock_firebase():
    """Patch firebase_admin.initialize_app so it does nothing."""
    with patch("firebase_admin.initialize_app"):
        yield


@pytest.fixture()
def mock_firestore():
    """Patch the Firestore db used by the recipes router."""
    with patch("app.routers.recipes.db") as mock_db:
        yield mock_db


@pytest.fixture()
def mock_auth():
    """Override get_current_user dependency to return a fake user."""
    from app.auth.firebase import get_current_user

    async def _fake_user():
        return {"uid": "test-user-123"}

    from app.main import app
    app.dependency_overrides[get_current_user] = _fake_user
    yield
    app.dependency_overrides.pop(get_current_user, None)


@pytest.fixture()
def client(mock_firebase, mock_firestore, mock_auth):
    """FastAPI test client with Firebase + Firestore mocked."""
    from app.main import app
    return TestClient(app)


# ===========================================================================
# Task 2.1 — Recipe CRUD endpoints
# ===========================================================================

class TestRecipeCRUD:
    """Endpoint-level tests for POST/GET/PUT/DELETE /v1/recipes."""

    def test_create_recipe(self, client, mock_firestore):
        mock_firestore.collection.return_value.document.return_value.set = AsyncMock()

        payload = {
            "title": "Test Recipe",
            "ingredients": [{"name": "Salt", "name_normalized": "salt"}],
            "steps": [
                {"step_number": 1, "instruction": "Add salt", "technique_tags": ["season"]}
            ],
        }
        resp = client.post("/v1/recipes", json=payload)
        assert resp.status_code == 200
        data = resp.json()
        assert data["title"] == "Test Recipe"
        assert data["uid"] == "test-user-123"
        assert "recipe_id" in data
        assert "salt" in data["ingredients_normalized"]

    def test_list_recipes(self, client, mock_firestore):
        # Simulate an async Firestore stream returning one doc
        fake_doc = MagicMock()
        fake_doc.to_dict.return_value = {
            "recipe_id": "r1",
            "uid": "test-user-123",
            "title": "Pasta",
            "created_at": "2025-01-01",
        }

        async def _stream():
            yield fake_doc

        mock_query = MagicMock()
        mock_query.stream = _stream
        mock_firestore.collection.return_value.where.return_value.order_by.return_value = mock_query

        resp = client.get("/v1/recipes")
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 1
        assert data[0]["title"] == "Pasta"

    def test_get_recipe(self, client, mock_firestore):
        fake_doc = MagicMock()
        fake_doc.exists = True
        fake_doc.to_dict.return_value = {
            "recipe_id": "r1",
            "uid": "test-user-123",
            "title": "Pasta",
        }
        mock_firestore.collection.return_value.document.return_value.get = AsyncMock(
            return_value=fake_doc
        )

        resp = client.get("/v1/recipes/r1")
        assert resp.status_code == 200
        assert resp.json()["title"] == "Pasta"

    def test_get_recipe_not_found(self, client, mock_firestore):
        fake_doc = MagicMock()
        fake_doc.exists = False
        mock_firestore.collection.return_value.document.return_value.get = AsyncMock(
            return_value=fake_doc
        )

        resp = client.get("/v1/recipes/missing")
        assert resp.status_code == 404

    def test_get_recipe_forbidden(self, client, mock_firestore):
        fake_doc = MagicMock()
        fake_doc.exists = True
        fake_doc.to_dict.return_value = {
            "recipe_id": "r1",
            "uid": "other-user",
            "title": "Not yours",
        }
        mock_firestore.collection.return_value.document.return_value.get = AsyncMock(
            return_value=fake_doc
        )

        resp = client.get("/v1/recipes/r1")
        assert resp.status_code == 403

    def test_delete_recipe(self, client, mock_firestore):
        fake_doc = MagicMock()
        fake_doc.exists = True
        fake_doc.to_dict.return_value = {
            "recipe_id": "r1",
            "uid": "test-user-123",
        }
        doc_ref = mock_firestore.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=fake_doc)
        doc_ref.delete = AsyncMock()

        resp = client.delete("/v1/recipes/r1")
        assert resp.status_code == 200
        assert resp.json()["status"] == "deleted"

    def test_update_recipe(self, client, mock_firestore):
        fake_doc = MagicMock()
        fake_doc.exists = True
        fake_doc.to_dict.return_value = {
            "recipe_id": "r1",
            "uid": "test-user-123",
            "title": "Old Title",
        }
        doc_ref = mock_firestore.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=fake_doc)
        doc_ref.update = AsyncMock()

        payload = {
            "title": "Updated Title",
            "steps": [{"step_number": 1, "instruction": "New step"}],
        }
        resp = client.put("/v1/recipes/r1", json=payload)
        assert resp.status_code == 200
        assert resp.json()["title"] == "Updated Title"

    def test_create_recipe_requires_title(self, client, mock_firestore):
        resp = client.post("/v1/recipes", json={"description": "No title"})
        assert resp.status_code == 422


# ===========================================================================
# Task 2.3 — URL parse request model
# ===========================================================================

class TestRecipeFromURLModel:
    def test_url_request_model(self):
        from app.models.recipe import RecipeFromURLRequest
        req = RecipeFromURLRequest(url="https://example.com/recipe")
        assert req.url == "https://example.com/recipe"


# ===========================================================================
# Task 2.4 — Ingredient normalization
# ===========================================================================

class TestIngredientNormalization:
    def test_lowercase_and_strip(self):
        from app.services.ingredients import normalize_ingredient
        assert normalize_ingredient("  Red Onion  ") == "red onion"

    def test_remove_parentheticals(self):
        from app.services.ingredients import normalize_ingredient
        assert normalize_ingredient("Chicken Breasts (boneless)") == "chicken breast"

    def test_depluralize_s(self):
        from app.services.ingredients import normalize_ingredient
        assert normalize_ingredient("carrots") == "carrot"

    def test_depluralize_es(self):
        from app.services.ingredients import normalize_ingredient
        assert normalize_ingredient("tomatoes") == "tomato"

    def test_depluralize_ies(self):
        from app.services.ingredients import normalize_ingredient
        assert normalize_ingredient("berries") == "berry"

    def test_no_depluralize_ss(self):
        from app.services.ingredients import normalize_ingredient
        assert normalize_ingredient("grass") == "grass"

    def test_match_ingredients_full_match(self):
        from app.services.ingredients import match_ingredients
        result = match_ingredients(["Carrots", "Onions"], ["carrot", "onion"])
        assert result["match_score"] == 1.0
        assert result["missing"] == []

    def test_match_ingredients_partial(self):
        from app.services.ingredients import match_ingredients
        result = match_ingredients(["carrot"], ["carrot", "onion"])
        assert result["match_score"] == 0.5
        assert "onion" in result["missing"]

    def test_match_ingredients_empty_required(self):
        from app.services.ingredients import match_ingredients
        result = match_ingredients(["carrot"], [])
        assert result["match_score"] == 0.0


# ===========================================================================
# Task 2.5 — Ingredient checklist model
# ===========================================================================

class TestIngredientChecklist:
    def test_all_available_true(self):
        from app.models.recipe import IngredientChecklist, IngredientCheck
        checklist = IngredientChecklist(
            recipe_id="r1",
            checks=[
                IngredientCheck(ingredient="salt", has_it=True),
                IngredientCheck(ingredient="pepper", has_it=True),
            ],
        )
        assert checklist.all_available is True
        assert checklist.missing == []

    def test_all_available_false_with_missing(self):
        from app.models.recipe import IngredientChecklist, IngredientCheck
        checklist = IngredientChecklist(
            recipe_id="r1",
            checks=[
                IngredientCheck(ingredient="salt", has_it=True),
                IngredientCheck(ingredient="saffron", has_it=False),
            ],
        )
        assert checklist.all_available is False
        assert checklist.missing == ["saffron"]


# ===========================================================================
# Task 2.6 — Demo recipe seed data validation
# ===========================================================================

class TestDemoRecipeSeed:
    def test_demo_recipe_has_required_fields(self):
        from seed_demo import DEMO_RECIPE
        assert DEMO_RECIPE["recipe_id"] == "demo-aglio-e-olio"
        assert DEMO_RECIPE["title"] == "Pasta Aglio e Olio"
        assert len(DEMO_RECIPE["steps"]) == 7
        assert len(DEMO_RECIPE["ingredients"]) == 8

    def test_all_steps_have_tags_and_prompts(self):
        from seed_demo import DEMO_RECIPE
        for step in DEMO_RECIPE["steps"]:
            assert step["technique_tags"], f"Step {step['step_number']} missing tags"
            assert step["guide_image_prompt"], f"Step {step['step_number']} missing prompt"

    def test_parallel_steps(self):
        from seed_demo import DEMO_RECIPE
        parallel = [s for s in DEMO_RECIPE["steps"] if s["is_parallel"]]
        step_numbers = {s["step_number"] for s in parallel}
        assert 2 in step_numbers, "Step 2 should be parallel"
        assert 4 in step_numbers, "Step 4 should be parallel"

    def test_ingredients_normalized_list(self):
        from seed_demo import DEMO_RECIPE
        assert "spaghetti" in DEMO_RECIPE["ingredients_normalized"]
        assert "garlic" in DEMO_RECIPE["ingredients_normalized"]
        assert len(DEMO_RECIPE["ingredients_normalized"]) == len(DEMO_RECIPE["ingredients"])

    def test_technique_tags_aggregated(self):
        from seed_demo import DEMO_RECIPE
        for tag in ["boil", "slice", "saute", "emulsify", "fold"]:
            assert tag in DEMO_RECIPE["technique_tags"], f"Missing tag: {tag}"
