# Epic 2: Recipe Management & Data Layer

## Goal

Users can create, store, and retrieve recipes. Recipes have normalized ingredients and technique tags for downstream coaching and suggestion matching. A demo recipe is seeded with visual checkpoints.

## Prerequisites

- Epic 1 complete (Firestore, GCS, auth, FastAPI scaffold)
- Coordinate with Epic 8 for mobile recipe list/detail rendering contracts

## PRD References

- §6.1 Pillar 1: Recipe collection
- §10.1 `recipes/{recipe_id}` collection
- §10.2 `reference-crops/{recipe_id}/{step_id}.png`

## Tech Guide References

- §5 Firestore — AsyncClient, batch writes
- §1 Vertex AI — text generation for tag extraction

---

## Data Model

### Pydantic Models — `app/models/recipe.py`

```python
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
import uuid

class Ingredient(BaseModel):
    name: str                          # e.g., "onion"
    name_normalized: str               # e.g., "onion" (lowercase, singular)
    quantity: Optional[str] = None     # e.g., "2 medium"
    unit: Optional[str] = None         # e.g., "cups"
    preparation: Optional[str] = None  # e.g., "diced"
    category: Optional[str] = None     # e.g., "vegetable"

class RecipeStep(BaseModel):
    step_number: int
    instruction: str
    technique_tags: list[str] = []          # e.g., ["saute", "deglaze"]
    duration_minutes: Optional[float] = None
    is_parallel: bool = False               # Can run alongside other steps
    reference_image_uri: Optional[str] = None  # gs:// URI for visual checkpoint
    guide_image_prompt: Optional[str] = None   # Prompt for generating target-state image

class RecipeCreate(BaseModel):
    title: str
    description: Optional[str] = None
    source_type: str = "manual"             # "manual" | "url_parsed" | "buddy_generated"
    source_url: Optional[str] = None
    servings: Optional[int] = None
    total_time_minutes: Optional[int] = None
    difficulty: Optional[str] = None        # "easy" | "medium" | "hard"
    cuisine: Optional[str] = None
    ingredients: list[Ingredient] = []
    steps: list[RecipeStep] = []

class Recipe(RecipeCreate):
    recipe_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    uid: str                                # Owner user ID
    technique_tags: list[str] = []          # Aggregated from all steps
    ingredients_normalized: list[str] = []  # Flat list for matching
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
```

---

## Tasks

### 2.1 Recipe CRUD Endpoints

**What:** REST endpoints for creating, reading, listing, and deleting recipes.

**Deliverable:** `app/routers/recipes.py`

**Endpoints:**

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/recipes` | Create a recipe |
| `GET` | `/v1/recipes` | List user's recipes |
| `GET` | `/v1/recipes/{recipe_id}` | Get single recipe |
| `PUT` | `/v1/recipes/{recipe_id}` | Update recipe |
| `DELETE` | `/v1/recipes/{recipe_id}` | Delete recipe |

```python
from fastapi import APIRouter, Depends, HTTPException
from app.auth.firebase import get_current_user
from app.models.recipe import RecipeCreate, Recipe
from app.services.firestore import db
from google.cloud import firestore
import uuid

router = APIRouter()

@router.post("/recipes", response_model=Recipe)
async def create_recipe(body: RecipeCreate, user: dict = Depends(get_current_user)):
    recipe_id = str(uuid.uuid4())

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
        "uid": user["uid"],
        "technique_tags": technique_tags,
        "ingredients_normalized": ingredients_normalized,
        "created_at": firestore.SERVER_TIMESTAMP,
        "updated_at": firestore.SERVER_TIMESTAMP,
    }

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
```

**Acceptance Criteria:**
- [ ] All 5 CRUD endpoints work with auth
- [ ] Recipe scoped to user via `uid`
- [ ] `technique_tags` auto-aggregated from steps
- [ ] `ingredients_normalized` auto-generated as lowercase flat list
- [ ] Timestamps use `SERVER_TIMESTAMP`

---

### 2.2 Technique Tag Extraction via Gemini

**What:** When a recipe is created with raw step text (no technique_tags provided), use Gemini Flash to extract technique tags automatically.

**Implementation:** Add to recipe creation flow:

```python
from app.services.gemini import gemini_client, MODEL_FLASH

async def extract_technique_tags(steps: list[RecipeStep]) -> list[RecipeStep]:
    """Use Gemini to extract cooking technique tags from step instructions."""
    steps_text = "\n".join(
        f"Step {s.step_number}: {s.instruction}" for s in steps
    )

    response = await gemini_client.aio.models.generate_content(
        model=MODEL_FLASH,
        contents=f"""Extract cooking technique tags from each step.
Return JSON array where each element has step_number and tags.
Valid tags include: saute, boil, simmer, roast, grill, bake, fry, deep-fry,
steam, blanch, braise, deglaze, reduce, emulsify, fold, knead, proof,
caramelize, sear, poach, julienne, dice, mince, chiffonade, temper.

Steps:
{steps_text}

Return ONLY valid JSON.""",
    )

    # Parse and merge tags back into steps
    import json
    try:
        tag_data = json.loads(response.text)
        tag_map = {item["step_number"]: item["tags"] for item in tag_data}
        for step in steps:
            if not step.technique_tags and step.step_number in tag_map:
                step.technique_tags = tag_map[step.step_number]
    except (json.JSONDecodeError, KeyError):
        pass  # Graceful degradation — steps work without tags

    return steps
```

**Acceptance Criteria:**
- [ ] Tags extracted for steps that don't already have them
- [ ] Graceful fallback if Gemini returns unparseable response
- [ ] Tags limited to known culinary technique vocabulary

---

### 2.3 URL-Based Recipe Parse (Best Effort)

**What:** Accept a URL and attempt to parse recipe content using Gemini Flash. This is best-effort for the hackathon — not every site will work.

**Implementation:**

```python
@router.post("/recipes/from-url")
async def create_recipe_from_url(
    url: str,
    user: dict = Depends(get_current_user),
):
    response = await gemini_client.aio.models.generate_content(
        model=MODEL_FLASH,
        contents=f"""Parse this recipe URL and extract structured data.
URL: {url}

Return JSON with these fields:
- title: string
- description: string
- servings: number
- total_time_minutes: number
- difficulty: "easy" | "medium" | "hard"
- cuisine: string
- ingredients: array of {{name, quantity, unit, preparation}}
- steps: array of {{step_number, instruction, duration_minutes}}

Return ONLY valid JSON.""",
    )

    import json
    try:
        parsed = json.loads(response.text)
        parsed["source_type"] = "url_parsed"
        parsed["source_url"] = url
        # Create recipe using standard flow
        recipe_create = RecipeCreate(**parsed)
        # ... proceed with standard creation + tag extraction
    except (json.JSONDecodeError, Exception) as e:
        raise HTTPException(422, f"Could not parse recipe from URL: {str(e)}")
```

**Notes:**
- Gemini can access public URLs in its training but NOT fetch live pages. For live page content, consider fetching the HTML server-side first and passing it as text.
- This is explicitly best-effort per PRD §6.1.

**Acceptance Criteria:**
- [ ] Accepts URL, returns structured recipe or 422 error
- [ ] Sets `source_type: "url_parsed"` and `source_url`
- [ ] Falls through to standard creation flow with tag extraction

---

### 2.4 Ingredient Normalization Service

**What:** Normalize ingredient names for consistent matching across recipes and inventory scans.

**Implementation:** `app/services/ingredients.py`:

```python
import re

# Simple normalization rules — sufficient for hackathon
def normalize_ingredient(name: str) -> str:
    """Normalize ingredient name for matching.
    'Red Onions' -> 'red onion'
    'Chicken Breasts (boneless)' -> 'chicken breast'
    """
    name = name.lower().strip()
    # Remove parenthetical qualifiers
    name = re.sub(r'\([^)]*\)', '', name).strip()
    # Remove trailing 's' for basic depluralization
    # (not linguistically perfect, but good enough for matching)
    if name.endswith('es') and not name.endswith('ies'):
        name = name[:-2] if name[-3] in 'shxz' else name[:-1]
    elif name.endswith('ies'):
        name = name[:-3] + 'y'
    elif name.endswith('s') and not name.endswith('ss'):
        name = name[:-1]
    return name.strip()

def match_ingredients(available: list[str], required: list[str]) -> dict:
    """Match available ingredients against required ones.
    Returns {matched: [...], missing: [...], match_score: float}
    """
    available_norm = {normalize_ingredient(i) for i in available}
    required_norm = [normalize_ingredient(i) for i in required]

    matched = [r for r in required_norm if r in available_norm]
    missing = [r for r in required_norm if r not in available_norm]

    score = len(matched) / len(required_norm) if required_norm else 0.0

    return {
        "matched": matched,
        "missing": missing,
        "match_score": round(score, 2),
    }
```

**Acceptance Criteria:**
- [ ] Basic normalization handles plurals, case, parentheticals
- [ ] `match_ingredients` returns score, matched, and missing lists
- [ ] Used consistently in recipe creation and inventory scan suggestion engine

---

### 2.5 Ingredient Checklist Gate

**What:** Before starting a cooking session, user confirms they have all required ingredients. Returns structured have/don't-have status.

**Implementation:** Part of session creation flow (Epic 4), but the data model lives here:

```python
class IngredientCheck(BaseModel):
    ingredient: str
    has_it: bool

class IngredientChecklist(BaseModel):
    recipe_id: str
    checks: list[IngredientCheck]
    all_available: bool  # Computed: all checks are True

    @property
    def missing(self) -> list[str]:
        return [c.ingredient for c in self.checks if not c.has_it]
```

Endpoint is provided in Epic 4 session creation, but the model and validation logic is defined here.

**Acceptance Criteria:**
- [ ] Model supports have/don't-have per ingredient
- [ ] `all_available` computed property
- [ ] Missing ingredient list extractable

---

### 2.6 Demo Recipe Seeding

**What:** Seed one canonical demo recipe with full visual checkpoints, technique tags, and guide image prompts. This is the recipe used in the live demo.

**Suggested recipe:** Pasta Aglio e Olio (simple, visual, has timing/doneness moments)

**Implementation:** Create a seed script `backend/seed_demo.py`:

```python
DEMO_RECIPE = {
    "recipe_id": "demo-aglio-e-olio",
    "title": "Pasta Aglio e Olio",
    "description": "Classic Roman pasta with garlic, olive oil, and chili flakes",
    "source_type": "manual",
    "servings": 2,
    "total_time_minutes": 25,
    "difficulty": "medium",
    "cuisine": "Italian",
    "ingredients": [
        {"name": "Spaghetti", "name_normalized": "spaghetti", "quantity": "200", "unit": "g"},
        {"name": "Garlic", "name_normalized": "garlic", "quantity": "6", "unit": "cloves", "preparation": "thinly sliced"},
        {"name": "Extra virgin olive oil", "name_normalized": "olive oil", "quantity": "80", "unit": "ml"},
        {"name": "Red chili flakes", "name_normalized": "chili flake", "quantity": "1", "unit": "tsp"},
        {"name": "Fresh parsley", "name_normalized": "parsley", "quantity": "1", "unit": "bunch", "preparation": "chopped"},
        {"name": "Parmesan cheese", "name_normalized": "parmesan", "quantity": "30", "unit": "g", "preparation": "grated"},
        {"name": "Salt", "name_normalized": "salt", "quantity": "to taste"},
        {"name": "Pasta water", "name_normalized": "pasta water", "quantity": "1", "unit": "cup", "preparation": "reserved"},
    ],
    "steps": [
        {
            "step_number": 1,
            "instruction": "Bring a large pot of salted water to a rolling boil.",
            "technique_tags": ["boil"],
            "duration_minutes": 8,
            "is_parallel": False,
            "guide_image_prompt": "A large pot of water at a full rolling boil with visible large bubbles breaking the surface, steam rising. Kitchen setting."
        },
        {
            "step_number": 2,
            "instruction": "While water heats, thinly slice garlic cloves. Aim for even, paper-thin slices.",
            "technique_tags": ["slice"],
            "duration_minutes": 3,
            "is_parallel": True,
            "guide_image_prompt": "Paper-thin garlic slices on a cutting board, uniform thickness, translucent edges visible."
        },
        {
            "step_number": 3,
            "instruction": "Cook spaghetti in boiling water until 1 minute short of al dente. Reserve 1 cup of pasta water before draining.",
            "technique_tags": ["boil"],
            "duration_minutes": 9,
            "is_parallel": False,
            "guide_image_prompt": "Spaghetti cooking in boiling water, slightly firm when bent. A measuring cup scooping cloudy starchy pasta water."
        },
        {
            "step_number": 4,
            "instruction": "In a large pan, heat olive oil over medium-low heat. Add sliced garlic and cook slowly until light golden — NOT brown.",
            "technique_tags": ["saute"],
            "duration_minutes": 4,
            "is_parallel": True,
            "guide_image_prompt": "Garlic slices in olive oil in a pan, light golden color, some edges just starting to turn golden. Oil is gently sizzling, not smoking. Critical: NOT brown, NOT dark."
        },
        {
            "step_number": 5,
            "instruction": "When garlic is light golden, add chili flakes and stir for 30 seconds. Remove pan from heat immediately.",
            "technique_tags": ["saute"],
            "duration_minutes": 0.5,
            "is_parallel": False,
            "guide_image_prompt": "Red chili flakes scattered in golden garlic oil, slight sizzle visible, pan being lifted off burner."
        },
        {
            "step_number": 6,
            "instruction": "Add drained pasta to the pan. Return to low heat. Toss with tongs, adding pasta water a splash at a time until a silky, emulsified sauce coats every strand.",
            "technique_tags": ["emulsify", "saute"],
            "duration_minutes": 3,
            "is_parallel": False,
            "guide_image_prompt": "Spaghetti being tossed in a pan with tongs, glossy emulsified sauce coating strands. Sauce is creamy and slightly opaque from starch, not oily or dry."
        },
        {
            "step_number": 7,
            "instruction": "Remove from heat. Toss with parsley and half the parmesan. Plate and top with remaining parmesan.",
            "technique_tags": ["fold"],
            "duration_minutes": 2,
            "is_parallel": False,
            "guide_image_prompt": "Plated spaghetti aglio e olio, glistening with sauce, flecks of parsley and chili visible, parmesan dusted on top. Rustic plate."
        }
    ],
    "technique_tags": ["boil", "slice", "saute", "emulsify", "fold"],
    "ingredients_normalized": ["spaghetti", "garlic", "olive oil", "chili flake", "parsley", "parmesan", "salt", "pasta water"],
}
```

**Acceptance Criteria:**
- [ ] Demo recipe seeded in Firestore with ID `demo-aglio-e-olio`
- [ ] All steps have `technique_tags` and `guide_image_prompt` populated
- [ ] Steps 2 and 4 marked `is_parallel: true` (concurrent with boiling)
- [ ] Step 4 (garlic) is the primary vision-check demo moment
- [ ] Ingredients normalized for matching

---

### 2.7 Register Recipe Router

**What:** Mount recipe router in main app.

**Implementation:** Update `app/main.py`:
```python
from app.routers import recipes
app.include_router(recipes.router, prefix="/v1", tags=["recipes"])
```

**Acceptance Criteria:**
- [ ] `POST /v1/recipes` creates recipe
- [ ] `GET /v1/recipes` returns user's recipes
- [ ] `GET /v1/recipes/demo-aglio-e-olio` returns seeded demo recipe
- [ ] All endpoints require valid Firebase auth token

---

### 2.8 Mobile UX Implementation (Recipe Library + Ingredient Gate)

**What:** Implement saved-recipe mobile UX that is tightly coupled to recipe APIs and session-start prerequisites.

**Required mobile UX components:**
1. Recipe library list:
   - Sections: `Your Recipes` and `Demo`
   - Sort/filter controls (`Recently used`, `Fastest`, `Difficulty`)
   - Empty-state CTA: `Import from URL` or `Create recipe`
2. Recipe detail view:
   - Header with total time, difficulty, servings
   - Ingredients list with normalized names shown clearly
   - Step preview with technique tags and parallel-step badges
3. Ingredient checklist gate:
   - Per-ingredient `Have it` toggle with sticky continue CTA
   - Missing-ingredient summary before session start
4. Session handoff:
   - Primary CTA: `Cook this now`
   - Loading/error handling for start-session bridge
5. Create/edit reliability:
   - Validation for required fields (`title`, at least one ingredient, at least one step)
   - Inline error messages for malformed or incomplete steps

**Acceptance Criteria:**
- [ ] `GET /v1/recipes` and `GET /v1/recipes/{id}` are rendered with loading/empty/error states
- [ ] Ingredient checklist UX maps to structured `have/don't-have` model used by session creation flow
- [ ] User can move from recipe detail to session setup without losing checklist state
- [ ] Create/edit flows block invalid submission and surface actionable errors
- [ ] Auth/network/server errors always provide retry or back navigation path

---

## Epic Completion Checklist

- [ ] Recipe CRUD endpoints functional with auth
- [ ] Technique tag extraction via Gemini working
- [ ] URL parse path (best effort) returning structured recipes
- [ ] Ingredient normalization consistent across system
- [ ] Ingredient checklist model defined
- [ ] Demo recipe seeded with visual checkpoints and guide prompts
- [ ] Router mounted and all endpoints accessible
- [ ] Mobile recipe library/detail/checklist UX connected to backend contracts
