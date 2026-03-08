"""Inventory scan & recipe suggestion endpoints (Epic 3)."""

import json
import re
import uuid

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from google.cloud import firestore
from google.genai import types

from app.auth.firebase import get_current_user
from app.models.inventory import IngredientConfirmation, StartSessionFromSuggestionRequest
from app.services.firestore import db
from app.services.gemini import MODEL_FLASH, gemini_client
from app.services.ingredients import match_ingredients, normalize_ingredient
from app.services.media import extract_keyframes_to_gcs
from app.services.sessions import create_session_record
from app.services.storage import upload_bytes

router = APIRouter()


@router.post("/inventory-scans")
async def create_inventory_scan(
    source: str = Form(...),
    images: list[UploadFile] | None = File(default=None),
    video: UploadFile | None = File(default=None),
    user: dict = Depends(get_current_user),
):
    """Accept 2-6 fridge/pantry images or 1 short video, upload to GCS, create scan record."""
    images = images or []
    if source not in ("fridge", "pantry"):
        raise HTTPException(400, "source must be 'fridge' or 'pantry'")

    has_images = len(images) > 0
    has_video = video is not None
    if has_images == has_video:
        raise HTTPException(400, "Provide either 2-6 images or 1 short video")
    if has_images and not 2 <= len(images) <= 6:
        raise HTTPException(400, "Upload 2-6 images")

    scan_id = str(uuid.uuid4())
    uid = user["uid"]
    image_uris = []
    capture_mode = "images"

    if has_images:
        for i, image in enumerate(images):
            content = await image.read()
            content_type = image.content_type or "image/jpeg"
            path = f"inventory-scans/{uid}/{scan_id}/{i}.jpg"
            uri = upload_bytes(path, content, content_type)
            image_uris.append(uri)
    else:
        capture_mode = "video"
        if not (video.content_type or "").startswith("video/"):
            raise HTTPException(400, "video must be a valid video content type")
        video_bytes = await video.read()
        video_uri = upload_bytes(
            f"inventory-scans/{uid}/{scan_id}/raw.mp4",
            video_bytes,
            video.content_type or "video/mp4",
        )
        image_uris = await extract_keyframes_to_gcs(
            video_uri=video_uri,
            uid=uid,
            scan_id=scan_id,
            frame_count=3,
        )

    scan_data = {
        "scan_id": scan_id,
        "uid": uid,
        "source": source,
        "capture_mode": capture_mode,
        "image_uris": image_uris,
        "detected_ingredients": [],
        "confidence_map": {},
        "confirmed_ingredients": [],
        "status": "pending",
        "created_at": firestore.SERVER_TIMESTAMP,
    }
    await db.collection("inventory_scans").document(scan_id).set(scan_data)

    return {
        "scan_id": scan_id,
        "capture_mode": capture_mode,
        "image_count": len(image_uris),
        "status": "pending",
    }


async def extract_ingredients_from_images(
    image_uris: list[str], source: str
) -> list[dict]:
    """Use Gemini Flash to detect ingredients from fridge/pantry images."""
    parts = []
    for uri in image_uris:
        parts.append(types.Part.from_uri(file_uri=uri, mime_type="image/jpeg"))

    parts.append(
        f"""Analyze these {source} images and identify all visible food ingredients.

For each ingredient, provide:
- name: common ingredient name (e.g., "red bell pepper", "whole milk", "cheddar cheese")
- confidence: float 0.0-1.0 indicating how certain you are of the identification
- source_image_index: which image (0-indexed) the ingredient is most visible in

Rules:
- Only identify actual food ingredients, not containers, utensils, or non-food items
- If an item is partially obscured, lower the confidence
- If you can see a label, use the label name
- Provide confidence >= 0.8 only when clearly visible and identifiable
- Provide confidence 0.5-0.79 when partially visible or ambiguous
- Provide confidence < 0.5 when guessing from context

Return ONLY a JSON array of objects with the fields above."""
    )

    response = await gemini_client.aio.models.generate_content(
        model=MODEL_FLASH,
        contents=parts,
    )

    try:
        ingredients = json.loads(response.text)
    except json.JSONDecodeError:
        match = re.search(r"```(?:json)?\s*([\s\S]*?)```", response.text)
        if match:
            ingredients = json.loads(match.group(1))
        else:
            return []

    return ingredients


@router.post("/inventory-scans/{scan_id}/detect")
async def detect_ingredients(
    scan_id: str,
    user: dict = Depends(get_current_user),
):
    """Process uploaded images through Gemini Flash to detect ingredients."""
    doc = await db.collection("inventory_scans").document(scan_id).get()
    if not doc.exists:
        raise HTTPException(404, "Scan not found")
    scan = doc.to_dict()
    if scan["uid"] != user["uid"]:
        raise HTTPException(403, "Not your scan")

    raw_ingredients = await extract_ingredients_from_images(
        scan["image_uris"], scan["source"]
    )

    detected = []
    confidence_map = {}
    for item in raw_ingredients:
        name = item.get("name", "")
        norm = normalize_ingredient(name)
        confidence = min(max(item.get("confidence", 0.5), 0.0), 1.0)
        detected.append(
            {
                "name": name,
                "name_normalized": norm,
                "confidence": confidence,
                "source_image_index": item.get("source_image_index", 0),
            }
        )
        confidence_map[norm] = confidence

    detected.sort(key=lambda x: x["confidence"], reverse=True)

    await db.collection("inventory_scans").document(scan_id).update(
        {
            "detected_ingredients": detected,
            "confidence_map": confidence_map,
            "status": "detected",
        }
    )

    return {
        "scan_id": scan_id,
        "detected_ingredients": detected,
        "status": "detected",
        "low_confidence_count": sum(1 for d in detected if d["confidence"] < 0.5),
    }


@router.post("/inventory-scans/{scan_id}/confirm-ingredients")
async def confirm_ingredients(
    scan_id: str,
    body: IngredientConfirmation,
    user: dict = Depends(get_current_user),
):
    """User reviews detected ingredients, adds/removes items, confirms final list."""
    doc = await db.collection("inventory_scans").document(scan_id).get()
    if not doc.exists:
        raise HTTPException(404, "Scan not found")
    scan = doc.to_dict()
    if scan["uid"] != user["uid"]:
        raise HTTPException(403, "Not your scan")
    if scan["status"] not in ("detected", "confirmed"):
        raise HTTPException(400, "Scan must be in 'detected' state first")

    confirmed = [normalize_ingredient(i) for i in body.confirmed_ingredients]

    await db.collection("inventory_scans").document(scan_id).update(
        {
            "confirmed_ingredients": confirmed,
            "status": "confirmed",
        }
    )

    return {
        "scan_id": scan_id,
        "confirmed_ingredients": confirmed,
        "status": "confirmed",
    }


# --- Ranking helpers (FP-06) ---


def _difficulty_score(difficulty: str | None, skill_level: str) -> float:
    order = {"easy": 0, "medium": 1, "hard": 2}
    d = order.get((difficulty or "medium").lower(), 1)
    s = order.get((skill_level or "medium").lower(), 1)
    return max(0.0, 1.0 - (abs(d - s) * 0.5))


def _time_score(estimated_time_min: int | None, max_time_minutes: int) -> float:
    if not estimated_time_min:
        return 0.7
    if estimated_time_min <= max_time_minutes:
        return 1.0
    over = estimated_time_min - max_time_minutes
    return max(0.0, 1.0 - (over / max(15, max_time_minutes)))


def _rank_score(
    match_score: float, missing_count: int, t_score: float, s_score: float
) -> float:
    missing_penalty = max(0.0, 1.0 - (0.2 * missing_count))
    return round(
        (0.50 * match_score)
        + (0.20 * missing_penalty)
        + (0.20 * t_score)
        + (0.10 * s_score),
        3,
    )


# --- Suggestion engines ---


async def find_matching_saved_recipes(
    uid: str, confirmed_ingredients: list[str]
) -> list[dict]:
    """Query user's recipes and rank by ingredient match + time fit + skill fit."""
    user_doc = await db.collection("users").document(uid).get()
    profile = user_doc.to_dict() if user_doc.exists else {}
    prefs = {
        "max_time_minutes": profile.get("max_time_minutes", 40),
        "skill_level": profile.get("skill_level", "medium"),
    }

    query = db.collection("recipes").where("uid", "==", uid)
    recipes = [doc.to_dict() async for doc in query.stream()]

    suggestions = []
    for recipe in recipes:
        result = match_ingredients(
            confirmed_ingredients, recipe.get("ingredients_normalized", [])
        )

        if result["match_score"] > 0.3:
            matched_str = ", ".join(result["matched"][:5])
            missing_str = (
                ", ".join(result["missing"][:3]) if result["missing"] else "nothing"
            )
            explanation = (
                f"You have {len(result['matched'])} of "
                f"{len(recipe.get('ingredients_normalized', []))} "
                f"ingredients ({matched_str}). "
                f"{'Only missing ' + missing_str + '.' if result['missing'] else 'You have everything!'}"
            )
            grounding_sources = [
                f"Matched from your confirmed scan: {matched_str}",
                f"Recipe saved on your account: {recipe['recipe_id']}",
            ]

            t_score = _time_score(
                recipe.get("total_time_minutes"), prefs["max_time_minutes"]
            )
            s_score = _difficulty_score(recipe.get("difficulty"), prefs["skill_level"])

            suggestions.append(
                {
                    "suggestion_id": str(uuid.uuid4()),
                    "source_type": "saved_recipe",
                    "recipe_id": recipe["recipe_id"],
                    "title": recipe["title"],
                    "description": recipe.get("description"),
                    "match_score": result["match_score"],
                    "matched_ingredients": result["matched"],
                    "missing_ingredients": result["missing"],
                    "estimated_time_min": recipe.get("total_time_minutes"),
                    "difficulty": recipe.get("difficulty"),
                    "cuisine": recipe.get("cuisine"),
                    "source_label": "Saved",
                    "explanation": explanation,
                    "grounding_sources": grounding_sources,
                    "assumptions": [],
                    "time_fit": t_score,
                    "skill_fit": s_score,
                    "ranking_score": _rank_score(
                        result["match_score"],
                        len(result["missing"]),
                        t_score,
                        s_score,
                    ),
                }
            )

    suggestions.sort(
        key=lambda s: (
            -s["ranking_score"],
            -s["match_score"],
            len(s["missing_ingredients"]),
        )
    )
    return suggestions[:5]


async def generate_buddy_recipes(confirmed_ingredients: list[str]) -> list[dict]:
    """Use Gemini to suggest recipes from available ingredients."""
    ingredients_str = ", ".join(confirmed_ingredients)

    response = await gemini_client.aio.models.generate_content(
        model=MODEL_FLASH,
        contents=f"""Given these available ingredients: {ingredients_str}

Suggest 3 recipes that can be made using primarily these ingredients.
For each recipe, you may include up to 3 common pantry staples not in the list
(salt, pepper, oil, butter, etc.) as missing ingredients.

Return a JSON array where each recipe has:
- title: string
- description: string (1 sentence)
- match_score: float (proportion of recipe ingredients that are in the available list)
- matched_ingredients: array of strings (from available list used)
- missing_ingredients: array of strings (needed but not available)
- estimated_time_min: integer
- difficulty: "easy" | "medium" | "hard"
- cuisine: string
- explanation: string (1-2 sentences explaining WHY this recipe fits these ingredients — e.g., "Your chicken, garlic, and lemon are the core of a classic piccata. You only need capers and flour.")
- assumptions: array of strings (what you assumed — e.g., "Assumes you have basic pantry staples: salt, pepper, olive oil")

Prioritize:
1. Recipes that use more of the available ingredients
2. Recipes with fewer missing ingredients
3. Reasonable meal options (not just combinations)

Return ONLY valid JSON.""",
    )

    try:
        recipes = json.loads(response.text)
    except json.JSONDecodeError:
        match = re.search(r"```(?:json)?\s*([\s\S]*?)```", response.text)
        if match:
            recipes = json.loads(match.group(1))
        else:
            return []

    suggestions = []
    for recipe in recipes:
        suggestions.append(
            {
                "suggestion_id": str(uuid.uuid4()),
                "source_type": "buddy_generated",
                "recipe_id": None,
                "title": recipe.get("title", ""),
                "description": recipe.get("description"),
                "match_score": recipe.get("match_score", 0.7),
                "matched_ingredients": recipe.get("matched_ingredients", []),
                "missing_ingredients": recipe.get("missing_ingredients", []),
                "estimated_time_min": recipe.get("estimated_time_min"),
                "difficulty": recipe.get("difficulty"),
                "cuisine": recipe.get("cuisine"),
                "source_label": "Buddy",
                "explanation": recipe.get("explanation", ""),
                "grounding_sources": [
                    f"Generated from your confirmed ingredients: {ingredients_str}"
                ],
                "assumptions": recipe.get("assumptions", []),
            }
        )

    return suggestions


@router.get("/inventory-scans/{scan_id}/suggestions")
async def get_suggestions(
    scan_id: str,
    user: dict = Depends(get_current_user),
):
    """Combine saved recipe matches and buddy-generated suggestions into dual-lane response."""
    doc = await db.collection("inventory_scans").document(scan_id).get()
    if not doc.exists:
        raise HTTPException(404, "Scan not found")
    scan = doc.to_dict()
    if scan["uid"] != user["uid"]:
        raise HTTPException(403, "Not your scan")
    if scan["status"] != "confirmed":
        raise HTTPException(400, "Ingredients must be confirmed first")

    confirmed = scan["confirmed_ingredients"]

    # Fetch user prefs for ranking
    user_doc = await db.collection("users").document(user["uid"]).get()
    profile = user_doc.to_dict() if user_doc.exists else {}
    prefs = {
        "max_time_minutes": profile.get("max_time_minutes", 40),
        "skill_level": profile.get("skill_level", "medium"),
    }

    # Run both suggestion engines in parallel
    import asyncio

    saved_suggestions, buddy_suggestions = await asyncio.gather(
        find_matching_saved_recipes(user["uid"], confirmed),
        generate_buddy_recipes(confirmed),
    )

    # Apply FP-06 ranking consistently to buddy lane
    for s in buddy_suggestions:
        s["time_fit"] = _time_score(
            s.get("estimated_time_min"), prefs["max_time_minutes"]
        )
        s["skill_fit"] = _difficulty_score(s.get("difficulty"), prefs["skill_level"])
        s["ranking_score"] = _rank_score(
            s.get("match_score", 0.0),
            len(s.get("missing_ingredients", [])),
            s["time_fit"],
            s["skill_fit"],
        )

    buddy_suggestions.sort(
        key=lambda s: (
            -s.get("ranking_score", 0),
            -s.get("match_score", 0),
            len(s.get("missing_ingredients", [])),
        )
    )

    # Persist suggestions in Firestore subcollection
    all_suggestions = saved_suggestions + buddy_suggestions
    for suggestion in all_suggestions:
        await (
            db.collection("inventory_scans")
            .document(scan_id)
            .collection("suggestions")
            .document(suggestion["suggestion_id"])
            .set(suggestion)
        )

    return {
        "scan_id": scan_id,
        "from_saved": saved_suggestions,
        "buddy_recipes": buddy_suggestions,
        "total_suggestions": len(all_suggestions),
    }


async def create_recipe_from_buddy_suggestion(
    suggestion: dict,
    available_ingredients: list[str],
    uid: str,
) -> str:
    """Generate a full recipe from a buddy suggestion using Gemini."""
    response = await gemini_client.aio.models.generate_content(
        model=MODEL_FLASH,
        contents=f"""Create a complete recipe for: {suggestion['title']}
Description: {suggestion.get('description', '')}
Available ingredients: {', '.join(available_ingredients)}

Return JSON with:
- title, description, servings, total_time_minutes, difficulty, cuisine
- ingredients: array of {{"name", "quantity", "unit", "preparation"}}
- steps: array of {{"step_number", "instruction", "duration_minutes", "technique_tags"}}

Make it practical and achievable. Use the available ingredients as much as possible.
Return ONLY valid JSON.""",
    )

    try:
        parsed = json.loads(response.text)
    except json.JSONDecodeError:
        match = re.search(r"```(?:json)?\s*([\s\S]*?)```", response.text)
        parsed = json.loads(match.group(1)) if match else {}

    recipe_id = str(uuid.uuid4())

    # Build ingredients with normalized names
    ingredients = []
    ingredients_normalized = []
    for ing in parsed.get("ingredients", []):
        name = ing.get("name", "")
        norm = normalize_ingredient(name)
        ingredients.append(
            {
                "name": name,
                "name_normalized": norm,
                "quantity": ing.get("quantity"),
                "unit": ing.get("unit"),
                "preparation": ing.get("preparation"),
            }
        )
        ingredients_normalized.append(norm)

    recipe_data = {
        "recipe_id": recipe_id,
        "uid": uid,
        "title": parsed.get("title", suggestion["title"]),
        "description": parsed.get("description", suggestion.get("description", "")),
        "source_type": "buddy_generated",
        "servings": parsed.get("servings"),
        "total_time_minutes": parsed.get("total_time_minutes"),
        "difficulty": parsed.get("difficulty", suggestion.get("difficulty")),
        "cuisine": parsed.get("cuisine", suggestion.get("cuisine")),
        "ingredients": ingredients,
        "ingredients_normalized": ingredients_normalized,
        "steps": parsed.get("steps", []),
        "technique_tags": [],
        "created_at": firestore.SERVER_TIMESTAMP,
        "updated_at": firestore.SERVER_TIMESTAMP,
    }

    # Aggregate technique tags from steps
    all_tags = set()
    for step in recipe_data["steps"]:
        for tag in step.get("technique_tags", []):
            all_tags.add(tag.lower())
    recipe_data["technique_tags"] = sorted(all_tags)

    await db.collection("recipes").document(recipe_id).set(recipe_data)
    return recipe_id


@router.post("/inventory-scans/{scan_id}/start-session")
async def start_session_from_scan(
    scan_id: str,
    body: StartSessionFromSuggestionRequest,
    user: dict = Depends(get_current_user),
):
    """User selects a suggestion and transitions to cooking session creation."""
    scan_doc = await db.collection("inventory_scans").document(scan_id).get()
    if not scan_doc.exists:
        raise HTTPException(404, "Scan not found")
    scan = scan_doc.to_dict()
    if scan["uid"] != user["uid"]:
        raise HTTPException(403, "Not your scan")

    suggestion_doc = await (
        db.collection("inventory_scans")
        .document(scan_id)
        .collection("suggestions")
        .document(body.suggestion_id)
        .get()
    )
    if not suggestion_doc.exists:
        raise HTTPException(404, "Suggestion not found")
    suggestion = suggestion_doc.to_dict()

    recipe_id = suggestion.get("recipe_id")
    if suggestion["source_type"] == "buddy_generated" and not recipe_id:
        recipe_id = await create_recipe_from_buddy_suggestion(
            suggestion, scan["confirmed_ingredients"], user["uid"]
        )

    session = await create_session_record(
        uid=user["uid"],
        recipe_id=recipe_id,
        mode_settings=body.mode_settings or None,
    )

    return {
        "recipe_id": recipe_id,
        "scan_id": scan_id,
        "suggestion_id": body.suggestion_id,
        "suggestion": suggestion,
        "session": {
            "session_id": session["session_id"],
            "status": session["status"],
        },
        "next": {
            "endpoint": f"/v1/sessions/{session['session_id']}/activate",
            "method": "POST",
            "body": {},
        },
    }


@router.get("/inventory-scans/{scan_id}/suggestions/{suggestion_id}/explain")
async def explain_suggestion(
    scan_id: str,
    suggestion_id: str,
    user: dict = Depends(get_current_user),
):
    """Provide grounded 'Why this recipe?' explanation for a suggestion card."""
    scan_doc = await db.collection("inventory_scans").document(scan_id).get()
    if not scan_doc.exists:
        raise HTTPException(404, "Scan not found")
    scan = scan_doc.to_dict()
    if scan["uid"] != user["uid"]:
        raise HTTPException(403, "Not your scan")

    suggestion_doc = await (
        db.collection("inventory_scans")
        .document(scan_id)
        .collection("suggestions")
        .document(suggestion_id)
        .get()
    )
    if not suggestion_doc.exists:
        raise HTTPException(404, "Suggestion not found")
    suggestion = suggestion_doc.to_dict()

    confidence_map = scan.get("confidence_map", {})
    matched = suggestion.get("matched_ingredients", [])
    missing = suggestion.get("missing_ingredients", [])
    assumptions = suggestion.get("assumptions", [])

    # GE-03: Flag low-confidence detections used in matching
    low_confidence_matches = [
        ing for ing in matched if confidence_map.get(ing, 1.0) < 0.5
    ]

    explanation_parts = []

    # Why this recipe fits
    if suggestion["source_type"] == "saved_recipe":
        explanation_parts.append(
            f"This is from your saved recipes. "
            f"You have {len(matched)} of the {len(matched) + len(missing)} required ingredients."
        )
    else:
        explanation_parts.append(
            f"I designed this recipe around what you have available. "
            f"It uses {len(matched)} of your confirmed ingredients."
        )

    # What matched
    if matched:
        explanation_parts.append(f"Using: {', '.join(matched[:8])}.")

    # What's missing
    if missing:
        explanation_parts.append(f"You'd still need: {', '.join(missing)}.")
    else:
        explanation_parts.append("You have everything you need!")

    # GE-03: Trust caveat for low-confidence ingredients
    if low_confidence_matches:
        names = ", ".join(low_confidence_matches[:3])
        pronoun = "it" if len(low_confidence_matches) == 1 else "them"
        explanation_parts.append(
            f"Note: I wasn't fully certain about {names} from the scan — "
            f"double-check you actually have {pronoun}."
        )

    # GE-02: Surface assumptions for buddy recipes
    if assumptions:
        explanation_parts.append(f"I assumed: {'; '.join(assumptions)}.")

    return {
        "suggestion_id": suggestion_id,
        "title": suggestion["title"],
        "explanation_full": " ".join(explanation_parts),
        "grounding_sources": suggestion.get("grounding_sources", []),
        "matched_ingredients": matched,
        "missing_ingredients": missing,
        "assumptions": assumptions,
        "low_confidence_warnings": low_confidence_matches,
        "match_score": suggestion["match_score"],
    }
