"""Inventory scan & recipe suggestion endpoints (Epic 3)."""

import json
import re
import uuid

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from google.cloud import firestore
from google.genai import types

from app.auth.firebase import get_current_user
from app.models.inventory import IngredientConfirmation
from app.services.firestore import db
from app.services.gemini import MODEL_FLASH, gemini_client
from app.services.ingredients import match_ingredients, normalize_ingredient
from app.services.media import extract_keyframes_to_gcs
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
