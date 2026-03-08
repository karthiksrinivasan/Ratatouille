"""Tests for Epic 3 — Fridge/Pantry Scan & Recipe Suggestions.

Covers tasks 3.1 through 3.8:
  3.1 Image/Video Upload & Scan Creation
  3.2 Ingredient Extraction via Gemini Vision
  3.3 User Ingredient Confirmation
  3.4 Saved Recipe Matching
  3.5 Buddy-Generated Recipe Suggestions
  3.6 Dual-Lane Suggestions Endpoint
  3.7 Start Session from Suggestion
  3.8 "Why This Recipe?" Explainability
"""

import io
import json
import uuid
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi.testclient import TestClient


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture()
def mock_firebase():
    with patch("firebase_admin.initialize_app"):
        yield


@pytest.fixture()
def mock_firestore_inventory():
    with patch("app.routers.inventory.db") as mock_db:
        yield mock_db


@pytest.fixture()
def mock_auth():
    from app.auth.firebase import get_current_user
    from app.main import app

    async def _fake_user():
        return {"uid": "test-user-123"}

    app.dependency_overrides[get_current_user] = _fake_user
    yield
    app.dependency_overrides.pop(get_current_user, None)


@pytest.fixture()
def client(mock_firebase, mock_firestore_inventory, mock_auth):
    from app.main import app
    return TestClient(app)


def _make_scan_doc(overrides=None):
    """Helper to create a fake scan Firestore document."""
    base = {
        "scan_id": "scan-1",
        "uid": "test-user-123",
        "source": "fridge",
        "capture_mode": "images",
        "image_uris": ["gs://bucket/img0.jpg", "gs://bucket/img1.jpg"],
        "detected_ingredients": [],
        "confidence_map": {},
        "confirmed_ingredients": [],
        "status": "pending",
    }
    if overrides:
        base.update(overrides)
    doc = MagicMock()
    doc.exists = True
    doc.to_dict.return_value = base
    return doc


def _make_not_found_doc():
    doc = MagicMock()
    doc.exists = False
    return doc


# ===========================================================================
# Task 3.1 — Image/Video Upload & Scan Creation
# ===========================================================================

class TestScanCreation:
    """POST /v1/inventory-scans"""

    def test_create_scan_with_images(self, client, mock_firestore_inventory):
        mock_firestore_inventory.collection.return_value.document.return_value.set = AsyncMock()

        with patch("app.routers.inventory.upload_bytes", return_value="gs://bucket/img.jpg") as mock_upload:
            files = [
                ("images", ("img0.jpg", io.BytesIO(b"fake-image-0"), "image/jpeg")),
                ("images", ("img1.jpg", io.BytesIO(b"fake-image-1"), "image/jpeg")),
            ]
            resp = client.post(
                "/v1/inventory-scans",
                data={"source": "fridge"},
                files=files,
            )

        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "pending"
        assert data["capture_mode"] == "images"
        assert data["image_count"] == 2
        assert "scan_id" in data
        assert mock_upload.call_count == 2

    def test_create_scan_with_video(self, client, mock_firestore_inventory):
        mock_firestore_inventory.collection.return_value.document.return_value.set = AsyncMock()

        with patch("app.routers.inventory.upload_bytes", return_value="gs://bucket/raw.mp4"), \
             patch("app.routers.inventory.extract_keyframes_to_gcs", new_callable=AsyncMock,
                   return_value=["gs://b/f0.jpg", "gs://b/f1.jpg", "gs://b/f2.jpg"]):
            files = [("video", ("clip.mp4", io.BytesIO(b"fake-video"), "video/mp4"))]
            resp = client.post(
                "/v1/inventory-scans",
                data={"source": "pantry"},
                files=files,
            )

        assert resp.status_code == 200
        data = resp.json()
        assert data["capture_mode"] == "video"
        assert data["image_count"] == 3

    def test_create_scan_invalid_source(self, client, mock_firestore_inventory):
        files = [
            ("images", ("img0.jpg", io.BytesIO(b"x"), "image/jpeg")),
            ("images", ("img1.jpg", io.BytesIO(b"x"), "image/jpeg")),
        ]
        resp = client.post(
            "/v1/inventory-scans",
            data={"source": "garage"},
            files=files,
        )
        assert resp.status_code == 400

    def test_create_scan_too_few_images(self, client, mock_firestore_inventory):
        files = [("images", ("img0.jpg", io.BytesIO(b"x"), "image/jpeg"))]
        resp = client.post(
            "/v1/inventory-scans",
            data={"source": "fridge"},
            files=files,
        )
        assert resp.status_code == 400

    def test_create_scan_too_many_images(self, client, mock_firestore_inventory):
        files = [
            ("images", (f"img{i}.jpg", io.BytesIO(b"x"), "image/jpeg"))
            for i in range(7)
        ]
        resp = client.post(
            "/v1/inventory-scans",
            data={"source": "fridge"},
            files=files,
        )
        assert resp.status_code == 400

    def test_create_scan_no_media(self, client, mock_firestore_inventory):
        resp = client.post(
            "/v1/inventory-scans",
            data={"source": "fridge"},
        )
        assert resp.status_code == 400

    def test_create_scan_both_images_and_video(self, client, mock_firestore_inventory):
        files = [
            ("images", ("img0.jpg", io.BytesIO(b"x"), "image/jpeg")),
            ("images", ("img1.jpg", io.BytesIO(b"x"), "image/jpeg")),
            ("video", ("clip.mp4", io.BytesIO(b"v"), "video/mp4")),
        ]
        resp = client.post(
            "/v1/inventory-scans",
            data={"source": "fridge"},
            files=files,
        )
        # Should fail - both provided
        assert resp.status_code == 400

    def test_create_scan_video_wrong_content_type(self, client, mock_firestore_inventory):
        files = [("video", ("file.txt", io.BytesIO(b"text"), "text/plain"))]
        resp = client.post(
            "/v1/inventory-scans",
            data={"source": "fridge"},
            files=files,
        )
        assert resp.status_code == 400


# ===========================================================================
# Task 3.2 — Ingredient Extraction via Gemini Vision
# ===========================================================================

class TestIngredientDetection:
    """POST /v1/inventory-scans/{scan_id}/detect"""

    def test_detect_ingredients_success(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc()
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=scan_doc)
        doc_ref.update = AsyncMock()

        gemini_response = MagicMock()
        gemini_response.text = json.dumps([
            {"name": "Red Bell Pepper", "confidence": 0.92, "source_image_index": 0},
            {"name": "Milk", "confidence": 0.45, "source_image_index": 1},
        ])

        with patch("app.routers.inventory.gemini_client") as mock_gemini:
            mock_gemini.aio.models.generate_content = AsyncMock(return_value=gemini_response)
            resp = client.post("/v1/inventory-scans/scan-1/detect")

        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "detected"
        assert len(data["detected_ingredients"]) == 2
        # Sorted by confidence descending
        assert data["detected_ingredients"][0]["confidence"] >= data["detected_ingredients"][1]["confidence"]
        assert data["low_confidence_count"] == 1  # milk at 0.45

    def test_detect_ingredients_with_code_block_response(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc()
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=scan_doc)
        doc_ref.update = AsyncMock()

        gemini_response = MagicMock()
        gemini_response.text = '```json\n[{"name": "Egg", "confidence": 0.8, "source_image_index": 0}]\n```'

        with patch("app.routers.inventory.gemini_client") as mock_gemini:
            mock_gemini.aio.models.generate_content = AsyncMock(return_value=gemini_response)
            resp = client.post("/v1/inventory-scans/scan-1/detect")

        assert resp.status_code == 200
        assert len(resp.json()["detected_ingredients"]) == 1

    def test_detect_ingredients_gemini_unparseable(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc()
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=scan_doc)
        doc_ref.update = AsyncMock()

        gemini_response = MagicMock()
        gemini_response.text = "I cannot parse these images properly."

        with patch("app.routers.inventory.gemini_client") as mock_gemini:
            mock_gemini.aio.models.generate_content = AsyncMock(return_value=gemini_response)
            resp = client.post("/v1/inventory-scans/scan-1/detect")

        assert resp.status_code == 200
        assert resp.json()["detected_ingredients"] == []

    def test_detect_scan_not_found(self, client, mock_firestore_inventory):
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=_make_not_found_doc())

        resp = client.post("/v1/inventory-scans/missing/detect")
        assert resp.status_code == 404

    def test_detect_scan_wrong_user(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc({"uid": "other-user"})
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=scan_doc)

        resp = client.post("/v1/inventory-scans/scan-1/detect")
        assert resp.status_code == 403

    def test_detect_normalizes_ingredients(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc()
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=scan_doc)
        doc_ref.update = AsyncMock()

        gemini_response = MagicMock()
        gemini_response.text = json.dumps([
            {"name": "Red Onions", "confidence": 0.9, "source_image_index": 0},
        ])

        with patch("app.routers.inventory.gemini_client") as mock_gemini:
            mock_gemini.aio.models.generate_content = AsyncMock(return_value=gemini_response)
            resp = client.post("/v1/inventory-scans/scan-1/detect")

        ingredients = resp.json()["detected_ingredients"]
        assert ingredients[0]["name_normalized"] == "red onion"

    def test_detect_clamps_confidence(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc()
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=scan_doc)
        doc_ref.update = AsyncMock()

        gemini_response = MagicMock()
        gemini_response.text = json.dumps([
            {"name": "Salt", "confidence": 1.5, "source_image_index": 0},
            {"name": "Pepper", "confidence": -0.2, "source_image_index": 0},
        ])

        with patch("app.routers.inventory.gemini_client") as mock_gemini:
            mock_gemini.aio.models.generate_content = AsyncMock(return_value=gemini_response)
            resp = client.post("/v1/inventory-scans/scan-1/detect")

        ingredients = resp.json()["detected_ingredients"]
        assert ingredients[0]["confidence"] <= 1.0
        assert ingredients[1]["confidence"] >= 0.0


# ===========================================================================
# Task 3.3 — User Ingredient Confirmation
# ===========================================================================

class TestIngredientConfirmation:
    """POST /v1/inventory-scans/{scan_id}/confirm-ingredients"""

    def test_confirm_ingredients_success(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc({"status": "detected"})
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=scan_doc)
        doc_ref.update = AsyncMock()

        resp = client.post(
            "/v1/inventory-scans/scan-1/confirm-ingredients",
            json={"confirmed_ingredients": ["Red Bell Pepper", "Milk", "Eggs"]},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "confirmed"
        assert "red bell pepper" in data["confirmed_ingredients"]
        assert "egg" in data["confirmed_ingredients"]  # normalized/depluralized

    def test_confirm_allows_reconfirmation(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc({"status": "confirmed"})
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=scan_doc)
        doc_ref.update = AsyncMock()

        resp = client.post(
            "/v1/inventory-scans/scan-1/confirm-ingredients",
            json={"confirmed_ingredients": ["salt"]},
        )
        assert resp.status_code == 200

    def test_confirm_requires_detected_state(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc({"status": "pending"})
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=scan_doc)

        resp = client.post(
            "/v1/inventory-scans/scan-1/confirm-ingredients",
            json={"confirmed_ingredients": ["salt"]},
        )
        assert resp.status_code == 400

    def test_confirm_not_found(self, client, mock_firestore_inventory):
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=_make_not_found_doc())

        resp = client.post(
            "/v1/inventory-scans/missing/confirm-ingredients",
            json={"confirmed_ingredients": ["salt"]},
        )
        assert resp.status_code == 404

    def test_confirm_wrong_user(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc({"uid": "other-user", "status": "detected"})
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=scan_doc)

        resp = client.post(
            "/v1/inventory-scans/scan-1/confirm-ingredients",
            json={"confirmed_ingredients": ["salt"]},
        )
        assert resp.status_code == 403

    def test_confirm_user_can_add_new_ingredients(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc({"status": "detected"})
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=scan_doc)
        doc_ref.update = AsyncMock()

        # User adds "saffron" which was never detected
        resp = client.post(
            "/v1/inventory-scans/scan-1/confirm-ingredients",
            json={"confirmed_ingredients": ["saffron", "truffle"]},
        )
        assert resp.status_code == 200
        assert "saffron" in resp.json()["confirmed_ingredients"]


# ===========================================================================
# Task 3.4 — Saved Recipe Matching
# ===========================================================================

class TestSavedRecipeMatching:
    """Unit tests for find_matching_saved_recipes."""

    @pytest.mark.asyncio
    async def test_match_saved_recipes_basic(self):
        """Recipes with >30% match returned, ranked by score."""
        from app.routers.inventory import find_matching_saved_recipes

        user_doc = MagicMock()
        user_doc.exists = True
        user_doc.to_dict.return_value = {"max_time_minutes": 40, "skill_level": "medium"}

        recipe_doc = MagicMock()
        recipe_doc.to_dict.return_value = {
            "recipe_id": "r1",
            "uid": "test-user-123",
            "title": "Pasta",
            "description": "Simple pasta",
            "ingredients_normalized": ["pasta", "garlic", "olive oil", "salt"],
            "total_time_minutes": 20,
            "difficulty": "easy",
            "cuisine": "Italian",
        }

        async def _stream():
            yield recipe_doc

        mock_query = MagicMock()
        mock_query.stream = _stream

        with patch("app.routers.inventory.db") as mock_db:
            mock_db.collection.return_value.document.return_value.get = AsyncMock(return_value=user_doc)
            mock_db.collection.return_value.where.return_value = mock_query

            results = await find_matching_saved_recipes(
                "test-user-123", ["pasta", "garlic", "olive oil"]
            )

        assert len(results) == 1
        assert results[0]["source_type"] == "saved_recipe"
        assert results[0]["match_score"] == 0.75  # 3/4
        assert "salt" in results[0]["missing_ingredients"]
        assert results[0]["source_label"] == "Saved"
        assert results[0]["explanation"]  # grounded explanation present
        assert len(results[0]["grounding_sources"]) > 0

    @pytest.mark.asyncio
    async def test_match_filters_low_matches(self):
        """Recipes with <=30% match are excluded."""
        from app.routers.inventory import find_matching_saved_recipes

        user_doc = MagicMock()
        user_doc.exists = False

        recipe_doc = MagicMock()
        recipe_doc.to_dict.return_value = {
            "recipe_id": "r2",
            "uid": "test-user-123",
            "title": "Complex Dish",
            "ingredients_normalized": ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"],
            "total_time_minutes": 60,
            "difficulty": "hard",
        }

        async def _stream():
            yield recipe_doc

        mock_query = MagicMock()
        mock_query.stream = _stream

        with patch("app.routers.inventory.db") as mock_db:
            mock_db.collection.return_value.document.return_value.get = AsyncMock(return_value=user_doc)
            mock_db.collection.return_value.where.return_value = mock_query

            results = await find_matching_saved_recipes("test-user-123", ["a", "b"])

        assert len(results) == 0  # 2/10 = 0.2, below 0.3 threshold


# ===========================================================================
# Task 3.5 — Buddy-Generated Recipe Suggestions
# ===========================================================================

class TestBuddyRecipeGeneration:
    """Unit tests for generate_buddy_recipes."""

    @pytest.mark.asyncio
    async def test_generate_buddy_recipes_success(self):
        from app.routers.inventory import generate_buddy_recipes

        gemini_response = MagicMock()
        gemini_response.text = json.dumps([
            {
                "title": "Garlic Chicken",
                "description": "Simple garlic chicken",
                "match_score": 0.8,
                "matched_ingredients": ["chicken", "garlic"],
                "missing_ingredients": ["salt"],
                "estimated_time_min": 30,
                "difficulty": "easy",
                "cuisine": "American",
                "explanation": "Your chicken and garlic are perfect for this.",
                "assumptions": ["Assumes basic pantry staples: salt, pepper"],
            },
            {
                "title": "Garlic Bread",
                "description": "Classic garlic bread",
                "match_score": 0.7,
                "matched_ingredients": ["garlic"],
                "missing_ingredients": ["bread", "butter"],
                "estimated_time_min": 15,
                "difficulty": "easy",
                "cuisine": "Italian",
                "explanation": "Quick side dish with your garlic.",
                "assumptions": ["Assumes you have bread and butter"],
            },
        ])

        with patch("app.routers.inventory.gemini_client") as mock_gemini:
            mock_gemini.aio.models.generate_content = AsyncMock(return_value=gemini_response)
            results = await generate_buddy_recipes(["chicken", "garlic"])

        assert len(results) == 2
        assert results[0]["source_type"] == "buddy_generated"
        assert results[0]["source_label"] == "Buddy"
        assert results[0]["recipe_id"] is None
        assert results[0]["explanation"]  # GE-02
        assert results[0]["assumptions"]  # GE-02
        assert len(results[0]["grounding_sources"]) > 0

    @pytest.mark.asyncio
    async def test_generate_buddy_recipes_unparseable(self):
        from app.routers.inventory import generate_buddy_recipes

        gemini_response = MagicMock()
        gemini_response.text = "Sorry, I can't help with that."

        with patch("app.routers.inventory.gemini_client") as mock_gemini:
            mock_gemini.aio.models.generate_content = AsyncMock(return_value=gemini_response)
            results = await generate_buddy_recipes(["chicken"])

        assert results == []

    @pytest.mark.asyncio
    async def test_generate_buddy_recipes_code_block_fallback(self):
        from app.routers.inventory import generate_buddy_recipes

        gemini_response = MagicMock()
        gemini_response.text = '```json\n[{"title":"Quick Salad","description":"Fresh","match_score":0.9,"matched_ingredients":["lettuce"],"missing_ingredients":[],"estimated_time_min":5,"difficulty":"easy","cuisine":"Any","explanation":"Uses your lettuce.","assumptions":[]}]\n```'

        with patch("app.routers.inventory.gemini_client") as mock_gemini:
            mock_gemini.aio.models.generate_content = AsyncMock(return_value=gemini_response)
            results = await generate_buddy_recipes(["lettuce"])

        assert len(results) == 1
        assert results[0]["title"] == "Quick Salad"


# ===========================================================================
# Task 3.6 — Dual-Lane Suggestions Endpoint
# ===========================================================================

class TestDualLaneSuggestions:
    """GET /v1/inventory-scans/{scan_id}/suggestions"""

    def test_suggestions_success(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc({
            "status": "confirmed",
            "confirmed_ingredients": ["chicken", "garlic", "olive oil"],
        })

        user_doc = MagicMock()
        user_doc.exists = True
        user_doc.to_dict.return_value = {"max_time_minutes": 40, "skill_level": "medium"}

        # First call: scan doc, second: user doc
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(side_effect=[scan_doc, user_doc])
        doc_ref.collection.return_value.document.return_value.set = AsyncMock()

        with patch("app.routers.inventory.find_matching_saved_recipes", new_callable=AsyncMock,
                    return_value=[{
                        "suggestion_id": "s1",
                        "source_type": "saved_recipe",
                        "recipe_id": "r1",
                        "title": "Saved Pasta",
                        "match_score": 0.8,
                        "matched_ingredients": ["chicken", "garlic"],
                        "missing_ingredients": ["pasta"],
                        "estimated_time_min": 20,
                        "difficulty": "easy",
                        "source_label": "Saved",
                        "explanation": "You have most ingredients.",
                        "grounding_sources": ["scan match"],
                        "assumptions": [],
                        "ranking_score": 0.85,
                    }]), \
             patch("app.routers.inventory.generate_buddy_recipes", new_callable=AsyncMock,
                    return_value=[{
                        "suggestion_id": "s2",
                        "source_type": "buddy_generated",
                        "recipe_id": None,
                        "title": "Buddy Stir Fry",
                        "match_score": 0.7,
                        "matched_ingredients": ["chicken"],
                        "missing_ingredients": ["soy sauce"],
                        "estimated_time_min": 25,
                        "difficulty": "medium",
                        "source_label": "Buddy",
                        "explanation": "Quick stir fry with your chicken.",
                        "grounding_sources": ["Generated from ingredients"],
                        "assumptions": ["Assumes pantry staples"],
                    }]):
            resp = client.get("/v1/inventory-scans/scan-1/suggestions")

        assert resp.status_code == 200
        data = resp.json()
        assert "from_saved" in data
        assert "buddy_recipes" in data
        assert data["total_suggestions"] == 2
        assert data["from_saved"][0]["source_label"] == "Saved"
        assert data["buddy_recipes"][0]["source_label"] == "Buddy"

    def test_suggestions_requires_confirmed_status(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc({"status": "detected"})
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=scan_doc)

        resp = client.get("/v1/inventory-scans/scan-1/suggestions")
        assert resp.status_code == 400

    def test_suggestions_not_found(self, client, mock_firestore_inventory):
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=_make_not_found_doc())

        resp = client.get("/v1/inventory-scans/missing/suggestions")
        assert resp.status_code == 404

    def test_suggestions_wrong_user(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc({"uid": "other-user", "status": "confirmed"})
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=scan_doc)

        resp = client.get("/v1/inventory-scans/scan-1/suggestions")
        assert resp.status_code == 403


# ===========================================================================
# Task 3.7 — Start Session from Suggestion
# ===========================================================================

class TestStartSession:
    """POST /v1/inventory-scans/{scan_id}/start-session"""

    def test_start_session_saved_recipe(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc({"status": "confirmed"})
        suggestion_doc = MagicMock()
        suggestion_doc.exists = True
        suggestion_doc.to_dict.return_value = {
            "suggestion_id": "s1",
            "source_type": "saved_recipe",
            "recipe_id": "r1",
            "title": "Pasta",
        }

        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=scan_doc)
        doc_ref.collection.return_value.document.return_value.get = AsyncMock(
            return_value=suggestion_doc
        )

        with patch("app.routers.inventory.create_session_record", new_callable=AsyncMock,
                    return_value={"session_id": "sess-1", "status": "created"}):
            resp = client.post(
                "/v1/inventory-scans/scan-1/start-session",
                json={"suggestion_id": "s1"},
            )

        assert resp.status_code == 200
        data = resp.json()
        assert data["recipe_id"] == "r1"
        assert data["session"]["session_id"] == "sess-1"
        assert data["next"]["endpoint"] == "/v1/sessions/sess-1/activate"

    def test_start_session_buddy_recipe(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc({
            "status": "confirmed",
            "confirmed_ingredients": ["chicken", "garlic"],
        })
        suggestion_doc = MagicMock()
        suggestion_doc.exists = True
        suggestion_doc.to_dict.return_value = {
            "suggestion_id": "s2",
            "source_type": "buddy_generated",
            "recipe_id": None,
            "title": "Garlic Chicken",
            "description": "Simple garlic chicken",
        }

        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=scan_doc)
        doc_ref.collection.return_value.document.return_value.get = AsyncMock(
            return_value=suggestion_doc
        )

        with patch("app.routers.inventory.create_recipe_from_buddy_suggestion",
                    new_callable=AsyncMock, return_value="new-recipe-id"), \
             patch("app.routers.inventory.create_session_record", new_callable=AsyncMock,
                    return_value={"session_id": "sess-2", "status": "created"}):
            resp = client.post(
                "/v1/inventory-scans/scan-1/start-session",
                json={"suggestion_id": "s2"},
            )

        assert resp.status_code == 200
        data = resp.json()
        assert data["recipe_id"] == "new-recipe-id"
        assert data["session"]["session_id"] == "sess-2"

    def test_start_session_scan_not_found(self, client, mock_firestore_inventory):
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=_make_not_found_doc())

        resp = client.post(
            "/v1/inventory-scans/missing/start-session",
            json={"suggestion_id": "s1"},
        )
        assert resp.status_code == 404

    def test_start_session_suggestion_not_found(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc({"status": "confirmed"})
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=scan_doc)
        doc_ref.collection.return_value.document.return_value.get = AsyncMock(
            return_value=_make_not_found_doc()
        )

        resp = client.post(
            "/v1/inventory-scans/scan-1/start-session",
            json={"suggestion_id": "missing"},
        )
        assert resp.status_code == 404


# ===========================================================================
# Task 3.8 — "Why This Recipe?" Explainability
# ===========================================================================

class TestExplainSuggestion:
    """GET /v1/inventory-scans/{scan_id}/suggestions/{suggestion_id}/explain"""

    def test_explain_saved_recipe(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc({
            "status": "confirmed",
            "confidence_map": {"chicken": 0.95, "garlic": 0.4},
        })
        suggestion_doc = MagicMock()
        suggestion_doc.exists = True
        suggestion_doc.to_dict.return_value = {
            "suggestion_id": "s1",
            "source_type": "saved_recipe",
            "title": "Garlic Chicken",
            "match_score": 0.8,
            "matched_ingredients": ["chicken", "garlic"],
            "missing_ingredients": ["salt"],
            "grounding_sources": ["scan match"],
            "assumptions": [],
        }

        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=scan_doc)
        doc_ref.collection.return_value.document.return_value.get = AsyncMock(
            return_value=suggestion_doc
        )

        resp = client.get("/v1/inventory-scans/scan-1/suggestions/s1/explain")
        assert resp.status_code == 200
        data = resp.json()
        assert "saved recipes" in data["explanation_full"]
        assert data["matched_ingredients"] == ["chicken", "garlic"]
        assert data["missing_ingredients"] == ["salt"]
        # GE-03: garlic is low confidence (0.4), should have warning
        assert "garlic" in data["low_confidence_warnings"]
        assert "double-check" in data["explanation_full"].lower()

    def test_explain_buddy_recipe_with_assumptions(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc({
            "status": "confirmed",
            "confidence_map": {},
        })
        suggestion_doc = MagicMock()
        suggestion_doc.exists = True
        suggestion_doc.to_dict.return_value = {
            "suggestion_id": "s2",
            "source_type": "buddy_generated",
            "title": "Quick Stir Fry",
            "match_score": 0.7,
            "matched_ingredients": ["chicken"],
            "missing_ingredients": [],
            "grounding_sources": ["Generated from ingredients"],
            "assumptions": ["Assumes basic pantry staples: salt, pepper, oil"],
        }

        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=scan_doc)
        doc_ref.collection.return_value.document.return_value.get = AsyncMock(
            return_value=suggestion_doc
        )

        resp = client.get("/v1/inventory-scans/scan-1/suggestions/s2/explain")
        assert resp.status_code == 200
        data = resp.json()
        assert "designed this recipe" in data["explanation_full"]
        assert "assumed" in data["explanation_full"].lower()
        assert data["assumptions"] == ["Assumes basic pantry staples: salt, pepper, oil"]

    def test_explain_not_found_scan(self, client, mock_firestore_inventory):
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=_make_not_found_doc())

        resp = client.get("/v1/inventory-scans/missing/suggestions/s1/explain")
        assert resp.status_code == 404

    def test_explain_not_found_suggestion(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc({"status": "confirmed"})
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=scan_doc)
        doc_ref.collection.return_value.document.return_value.get = AsyncMock(
            return_value=_make_not_found_doc()
        )

        resp = client.get("/v1/inventory-scans/scan-1/suggestions/missing/explain")
        assert resp.status_code == 404

    def test_explain_wrong_user(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc({"uid": "other-user"})
        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=scan_doc)

        resp = client.get("/v1/inventory-scans/scan-1/suggestions/s1/explain")
        assert resp.status_code == 403

    def test_explain_everything_available(self, client, mock_firestore_inventory):
        scan_doc = _make_scan_doc({"status": "confirmed", "confidence_map": {}})
        suggestion_doc = MagicMock()
        suggestion_doc.exists = True
        suggestion_doc.to_dict.return_value = {
            "suggestion_id": "s3",
            "source_type": "saved_recipe",
            "title": "Simple Salt",
            "match_score": 1.0,
            "matched_ingredients": ["salt"],
            "missing_ingredients": [],
            "grounding_sources": ["scan"],
            "assumptions": [],
        }

        doc_ref = mock_firestore_inventory.collection.return_value.document.return_value
        doc_ref.get = AsyncMock(return_value=scan_doc)
        doc_ref.collection.return_value.document.return_value.get = AsyncMock(
            return_value=suggestion_doc
        )

        resp = client.get("/v1/inventory-scans/scan-1/suggestions/s3/explain")
        assert resp.status_code == 200
        assert "everything you need" in resp.json()["explanation_full"]


# ===========================================================================
# Model unit tests
# ===========================================================================

class TestInventoryModels:
    def test_detected_ingredient_model(self):
        from app.models.inventory import DetectedIngredient
        ing = DetectedIngredient(
            name="Tomato",
            name_normalized="tomato",
            confidence=0.85,
            source_image_index=0,
        )
        assert ing.confidence == 0.85

    def test_inventory_scan_defaults(self):
        from app.models.inventory import InventoryScan
        scan = InventoryScan(uid="u1", source="fridge")
        assert scan.status == "pending"
        assert scan.image_uris == []
        assert scan.capture_mode == "images"

    def test_recipe_suggestion_model(self):
        from app.models.inventory import RecipeSuggestion
        s = RecipeSuggestion(
            source_type="saved_recipe",
            title="Test",
            match_score=0.8,
            source_label="Saved",
        )
        assert s.recipe_id is None
        assert s.explanation == ""

    def test_ingredient_confirmation_model(self):
        from app.models.inventory import IngredientConfirmation
        c = IngredientConfirmation(confirmed_ingredients=["salt", "pepper"])
        assert len(c.confirmed_ingredients) == 2

    def test_start_session_request_model(self):
        from app.models.inventory import StartSessionFromSuggestionRequest
        req = StartSessionFromSuggestionRequest(suggestion_id="s1")
        assert req.mode_settings == {}


# ===========================================================================
# Ranking helper unit tests
# ===========================================================================

class TestRankingHelpers:
    def test_difficulty_score_aligned(self):
        from app.routers.inventory import _difficulty_score
        assert _difficulty_score("medium", "medium") == 1.0
        assert _difficulty_score("easy", "easy") == 1.0

    def test_difficulty_score_mismatch(self):
        from app.routers.inventory import _difficulty_score
        assert _difficulty_score("hard", "easy") == 0.0
        assert _difficulty_score("easy", "hard") == 0.0
        assert _difficulty_score("easy", "medium") == 0.5

    def test_time_score_within_budget(self):
        from app.routers.inventory import _time_score
        assert _time_score(20, 40) == 1.0

    def test_time_score_over_budget(self):
        from app.routers.inventory import _time_score
        score = _time_score(55, 40)
        assert 0.0 <= score < 1.0

    def test_time_score_no_estimate(self):
        from app.routers.inventory import _time_score
        assert _time_score(None, 40) == 0.7

    def test_rank_score_perfect(self):
        from app.routers.inventory import _rank_score
        score = _rank_score(1.0, 0, 1.0, 1.0)
        assert score == 1.0

    def test_rank_score_partial(self):
        from app.routers.inventory import _rank_score
        score = _rank_score(0.5, 2, 0.7, 0.5)
        assert 0.0 <= score <= 1.0
