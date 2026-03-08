import json
import logging
import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from google.cloud import firestore

from app.auth.firebase import get_current_user
from app.models.recipe import RecipeCreate, Recipe, RecipeStep, RecipeFromURLRequest
from app.services.firestore import db
from app.services.gemini import gemini_client, MODEL_FLASH
from app.services.ingredients import normalize_ingredient

logger = logging.getLogger(__name__)

router = APIRouter()

KNOWN_TECHNIQUE_TAGS = {
    "saute", "boil", "simmer", "roast", "grill", "bake", "fry", "deep-fry",
    "steam", "blanch", "braise", "deglaze", "reduce", "emulsify", "fold",
    "knead", "proof", "caramelize", "sear", "poach", "julienne", "dice",
    "mince", "chiffonade", "temper", "slice",
}


async def extract_technique_tags(steps: list[RecipeStep]) -> list[RecipeStep]:
    """Use Gemini to extract cooking technique tags from step instructions."""
    # Only process steps that don't already have tags
    needs_tags = [s for s in steps if not s.technique_tags]
    if not needs_tags:
        return steps

    steps_text = "\n".join(
        f"Step {s.step_number}: {s.instruction}" for s in needs_tags
    )

    try:
        response = await gemini_client.aio.models.generate_content(
            model=MODEL_FLASH,
            contents=f"""Extract cooking technique tags from each step.
Return JSON array where each element has step_number and tags.
Valid tags include: saute, boil, simmer, roast, grill, bake, fry, deep-fry,
steam, blanch, braise, deglaze, reduce, emulsify, fold, knead, proof,
caramelize, sear, poach, julienne, dice, mince, chiffonade, temper, slice.

Steps:
{steps_text}

Return ONLY valid JSON.""",
        )

        raw_tags = response.text.strip()
        if raw_tags.startswith("```"):
            raw_tags = raw_tags.split("\n", 1)[1]
            raw_tags = raw_tags.rsplit("```", 1)[0]
        tag_data = json.loads(raw_tags)
        tag_map = {item["step_number"]: item["tags"] for item in tag_data}
        for step in steps:
            if not step.technique_tags and step.step_number in tag_map:
                # Filter to known tags only
                step.technique_tags = [
                    t for t in tag_map[step.step_number]
                    if t in KNOWN_TECHNIQUE_TAGS
                ]
    except (json.JSONDecodeError, KeyError, Exception) as e:
        logger.warning("Technique tag extraction failed: %s", e)
        # Graceful degradation — steps work without tags

    return steps


def _build_recipe_data(body: RecipeCreate, recipe_id: str, uid: str) -> dict:
    """Build Firestore document data from a RecipeCreate body."""
    # Aggregate technique tags from steps
    technique_tags = list(set(
        tag for step in body.steps for tag in step.technique_tags
    ))

    # Auto-fill name_normalized on ingredients if missing
    for ing in body.ingredients:
        if not ing.name_normalized:
            ing.name_normalized = normalize_ingredient(ing.name)

    # Flat normalized list for matching
    ingredients_normalized = [
        ing.name_normalized for ing in body.ingredients
    ]

    recipe_data = {
        **body.model_dump(),
        "recipe_id": recipe_id,
        "uid": uid,
        "technique_tags": technique_tags,
        "ingredients_normalized": ingredients_normalized,
        "created_at": firestore.SERVER_TIMESTAMP,
        "updated_at": firestore.SERVER_TIMESTAMP,
    }
    return recipe_data


@router.post("/recipes", response_model=Recipe)
async def create_recipe(body: RecipeCreate, user: dict = Depends(get_current_user)):
    recipe_id = str(uuid.uuid4())
    # Extract technique tags for steps that don't have them
    body.steps = await extract_technique_tags(body.steps)
    recipe_data = _build_recipe_data(body, recipe_id, user["uid"])
    await db.collection("recipes").document(recipe_id).set(recipe_data)
    # Replace SERVER_TIMESTAMP sentinels with real datetimes for the response
    now = datetime.utcnow()
    recipe_data["created_at"] = now
    recipe_data["updated_at"] = now
    return recipe_data


@router.post("/recipes/from-url", response_model=Recipe)
async def create_recipe_from_url(
    body: RecipeFromURLRequest,
    user: dict = Depends(get_current_user),
):
    """Parse a recipe from a URL using Gemini (best effort)."""
    try:
        response = await gemini_client.aio.models.generate_content(
            model=MODEL_FLASH,
            contents=f"""Parse this recipe URL and extract structured data.
URL: {body.url}

Return JSON with these fields:
- title: string
- description: string
- servings: number or null
- total_time_minutes: number or null
- difficulty: "easy" | "medium" | "hard" or null
- cuisine: string or null
- ingredients: array of {{"name": string, "quantity": string, "unit": string, "preparation": string}}
- steps: array of {{"step_number": number, "instruction": string, "duration_minutes": number or null}}

Return ONLY valid JSON.""",
        )

        raw = response.text.strip()
        # Strip markdown code fences that Gemini often adds.
        if raw.startswith("```"):
            raw = raw.split("\n", 1)[1]  # remove opening ```json line
            raw = raw.rsplit("```", 1)[0]  # remove closing ```
        logger.info("Gemini URL-parse response: %s", raw[:500])
        parsed = json.loads(raw)
        parsed["source_type"] = "url_parsed"
        parsed["source_url"] = body.url

        # Normalize ingredient names
        for ing in parsed.get("ingredients", []):
            if "name_normalized" not in ing:
                ing["name_normalized"] = ing.get("name", "").lower().strip()

        recipe_create = RecipeCreate(**parsed)
    except json.JSONDecodeError:
        raise HTTPException(422, "Could not parse recipe from URL: invalid response from AI")
    except Exception as e:
        raise HTTPException(422, f"Could not parse recipe from URL: {str(e)}")

    # Use standard creation flow with tag extraction
    recipe_id = str(uuid.uuid4())
    recipe_create.steps = await extract_technique_tags(recipe_create.steps)
    recipe_data = _build_recipe_data(recipe_create, recipe_id, user["uid"])
    await db.collection("recipes").document(recipe_id).set(recipe_data)
    # Replace SERVER_TIMESTAMP sentinels with real datetimes for the response
    now = datetime.utcnow()
    recipe_data["created_at"] = now
    recipe_data["updated_at"] = now
    return recipe_data


@router.get("/recipes")
async def list_recipes(user: dict = Depends(get_current_user)):
    query = db.collection("recipes").where("uid", "==", user["uid"])
    docs = [doc.to_dict() async for doc in query.stream()]
    # Sort by created_at in-memory to avoid requiring a composite index.
    docs.sort(key=lambda d: d.get("created_at") or "", reverse=False)
    return docs


@router.get("/recipes/{recipe_id}")
async def get_recipe(recipe_id: str, user: dict = Depends(get_current_user)):
    doc = await db.collection("recipes").document(recipe_id).get()
    if not doc.exists:
        raise HTTPException(404, "Recipe not found")
    data = doc.to_dict()
    if data["uid"] != user["uid"]:
        raise HTTPException(403, "Not your recipe")
    return data


@router.put("/recipes/{recipe_id}", response_model=Recipe)
async def update_recipe(
    recipe_id: str,
    body: RecipeCreate,
    user: dict = Depends(get_current_user),
):
    doc_ref = db.collection("recipes").document(recipe_id)
    doc = await doc_ref.get()
    if not doc.exists:
        raise HTTPException(404, "Recipe not found")
    data = doc.to_dict()
    if data["uid"] != user["uid"]:
        raise HTTPException(403, "Not your recipe")

    # Extract technique tags and build data using shared helper
    body.steps = await extract_technique_tags(body.steps)
    update_data = _build_recipe_data(body, recipe_id, user["uid"])
    # Preserve original created_at, only update updated_at
    del update_data["created_at"]
    await doc_ref.update(update_data)
    # Replace SERVER_TIMESTAMP sentinel with real datetime for the response
    update_data["updated_at"] = datetime.utcnow()
    update_data["created_at"] = data.get("created_at", datetime.utcnow())
    return update_data


@router.delete("/recipes/{recipe_id}")
async def delete_recipe(recipe_id: str, user: dict = Depends(get_current_user)):
    doc_ref = db.collection("recipes").document(recipe_id)
    doc = await doc_ref.get()
    if not doc.exists:
        raise HTTPException(404, "Recipe not found")
    data = doc.to_dict()
    if data["uid"] != user["uid"]:
        raise HTTPException(403, "Not your recipe")
    await doc_ref.delete()
    return {"status": "deleted", "recipe_id": recipe_id}
