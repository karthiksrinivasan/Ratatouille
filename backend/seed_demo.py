"""Seed the canonical demo recipe into Firestore.

Usage:
    python seed_demo.py

Requires GCP credentials and environment variables (GCP_PROJECT_ID, GCS_BUCKET_NAME).
"""

import asyncio

from google.cloud.firestore import AsyncClient

from app.config import settings

DEMO_RECIPE = {
    "recipe_id": "demo-aglio-e-olio",
    "uid": "demo-user",
    "title": "Pasta Aglio e Olio",
    "description": "Classic Roman pasta with garlic, olive oil, and chili flakes",
    "source_type": "manual",
    "servings": 2,
    "total_time_minutes": 25,
    "difficulty": "medium",
    "cuisine": "Italian",
    "ingredients": [
        {
            "name": "Spaghetti",
            "name_normalized": "spaghetti",
            "quantity": "200",
            "unit": "g",
        },
        {
            "name": "Garlic",
            "name_normalized": "garlic",
            "quantity": "6",
            "unit": "cloves",
            "preparation": "thinly sliced",
        },
        {
            "name": "Extra virgin olive oil",
            "name_normalized": "olive oil",
            "quantity": "80",
            "unit": "ml",
        },
        {
            "name": "Red chili flakes",
            "name_normalized": "chili flake",
            "quantity": "1",
            "unit": "tsp",
        },
        {
            "name": "Fresh parsley",
            "name_normalized": "parsley",
            "quantity": "1",
            "unit": "bunch",
            "preparation": "chopped",
        },
        {
            "name": "Parmesan cheese",
            "name_normalized": "parmesan",
            "quantity": "30",
            "unit": "g",
            "preparation": "grated",
        },
        {
            "name": "Salt",
            "name_normalized": "salt",
            "quantity": "to taste",
        },
        {
            "name": "Pasta water",
            "name_normalized": "pasta water",
            "quantity": "1",
            "unit": "cup",
            "preparation": "reserved",
        },
    ],
    "steps": [
        {
            "step_number": 1,
            "instruction": "Bring a large pot of salted water to a rolling boil.",
            "technique_tags": ["boil"],
            "duration_minutes": 8,
            "is_parallel": False,
            "guide_image_prompt": "A large pot of water at a full rolling boil with visible large bubbles breaking the surface, steam rising. Kitchen setting.",
        },
        {
            "step_number": 2,
            "instruction": "While water heats, thinly slice garlic cloves. Aim for even, paper-thin slices.",
            "technique_tags": ["slice"],
            "duration_minutes": 3,
            "is_parallel": True,
            "guide_image_prompt": "Paper-thin garlic slices on a cutting board, uniform thickness, translucent edges visible.",
        },
        {
            "step_number": 3,
            "instruction": "Cook spaghetti in boiling water until 1 minute short of al dente. Reserve 1 cup of pasta water before draining.",
            "technique_tags": ["boil"],
            "duration_minutes": 9,
            "is_parallel": True,
            "guide_image_prompt": "Spaghetti cooking in boiling water, slightly firm when bent. A measuring cup scooping cloudy starchy pasta water.",
        },
        {
            "step_number": 4,
            "instruction": "In a large pan, heat olive oil over medium-low heat. Add sliced garlic and cook slowly until light golden \u2014 NOT brown.",
            "technique_tags": ["saute"],
            "duration_minutes": 4,
            "is_parallel": True,
            "guide_image_prompt": "Garlic slices in olive oil in a pan, light golden color, some edges just starting to turn golden. Oil is gently sizzling, not smoking. Critical: NOT brown, NOT dark.",
        },
        {
            "step_number": 5,
            "instruction": "When garlic is light golden, add chili flakes and stir for 30 seconds. Remove pan from heat immediately.",
            "technique_tags": ["saute"],
            "duration_minutes": 0.5,
            "is_parallel": False,
            "guide_image_prompt": "Red chili flakes scattered in golden garlic oil, slight sizzle visible, pan being lifted off burner.",
        },
        {
            "step_number": 6,
            "instruction": "Add drained pasta to the pan. Return to low heat. Toss with tongs, adding pasta water a splash at a time until a silky, emulsified sauce coats every strand.",
            "technique_tags": ["emulsify", "saute"],
            "duration_minutes": 3,
            "is_parallel": False,
            "guide_image_prompt": "Spaghetti being tossed in a pan with tongs, glossy emulsified sauce coating strands. Sauce is creamy and slightly opaque from starch, not oily or dry.",
        },
        {
            "step_number": 7,
            "instruction": "Remove from heat. Toss with parsley and half the parmesan. Plate and top with remaining parmesan.",
            "technique_tags": ["fold"],
            "duration_minutes": 2,
            "is_parallel": False,
            "guide_image_prompt": "Plated spaghetti aglio e olio, glistening with sauce, flecks of parsley and chili visible, parmesan dusted on top. Rustic plate.",
        },
    ],
    "checklist_gate": [
        "Spaghetti (200g)",
        "Garlic (6 cloves)",
        "Extra virgin olive oil (80ml)",
        "Red chili flakes (1 tsp)",
        "Fresh parsley (1 bunch)",
        "Parmesan cheese (30g)",
        "Salt",
    ],
    "technique_tags": ["boil", "slice", "saute", "emulsify", "fold"],
    "ingredients_normalized": [
        "spaghetti",
        "garlic",
        "olive oil",
        "chili flake",
        "parsley",
        "parmesan",
        "salt",
        "pasta water",
    ],
}


async def seed():
    db = AsyncClient(project=settings.gcp_project_id)
    doc_ref = db.collection("recipes").document(DEMO_RECIPE["recipe_id"])
    await doc_ref.set(DEMO_RECIPE)
    print(f"Seeded demo recipe: {DEMO_RECIPE['recipe_id']}")
    print(f"  Title: {DEMO_RECIPE['title']}")
    print(f"  Steps: {len(DEMO_RECIPE['steps'])}")
    print(f"  Techniques: {DEMO_RECIPE['technique_tags']}")


if __name__ == "__main__":
    asyncio.run(seed())
