import json
import logging
import uuid

from fastapi import APIRouter, Depends, HTTPException
from google.cloud import firestore

from app.auth.firebase import get_current_user
from app.models.recipe import RecipeCreate, Recipe, RecipeStep
from app.services.firestore import db
from app.services.gemini import gemini_client, MODEL_FLASH

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

        tag_data = json.loads(response.text)
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

    # Normalize ingredient names for matching
    ingredients_normalized = [
        ing.name_normalized or ing.name.lower().strip()
        for ing in body.ingredients
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
    return recipe_data


@router.get("/recipes")
async def list_recipes(user: dict = Depends(get_current_user)):
    query = db.collection("recipes").where("uid", "==", user["uid"]).order_by("created_at")
    docs = [doc.to_dict() async for doc in query.stream()]
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

    # Rebuild with updated body, keep same recipe_id and uid
    technique_tags = list(set(
        tag for step in body.steps for tag in step.technique_tags
    ))
    ingredients_normalized = [
        ing.name_normalized or ing.name.lower().strip()
        for ing in body.ingredients
    ]

    update_data = {
        **body.model_dump(),
        "recipe_id": recipe_id,
        "uid": user["uid"],
        "technique_tags": technique_tags,
        "ingredients_normalized": ingredients_normalized,
        "updated_at": firestore.SERVER_TIMESTAMP,
    }
    await doc_ref.update(update_data)
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
