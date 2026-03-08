from fastapi import APIRouter, Depends, HTTPException
from google.cloud import firestore

from app.auth.firebase import get_current_user
from app.models.recipe import RecipeCreate, Recipe
from app.services.firestore import db

import uuid

router = APIRouter()


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
