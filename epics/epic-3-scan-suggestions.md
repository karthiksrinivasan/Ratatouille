# Epic 3: Fridge/Pantry Scan & Recipe Suggestions

## Goal

User captures their fridge or pantry (2-6 photos or a short video), the system detects ingredients with confidence scores, the user confirms/edits the list, and the system returns dual-lane recipe suggestions (matching saved recipes + AI-generated buddy recipes).

## Prerequisites

- Epic 1 complete (Firestore, GCS, auth, Gemini client)
- Epic 2 complete (recipe data model, ingredient normalization, demo recipe seeded)

## PRD References

- §7.10 Fridge/Pantry-to-Recipe Flow (FP-01 through FP-08)
- §7.11 Grounding and Explainability (GE-01 through GE-04)
- §7.2 MI-05 Inventory scan input
- §7.3 MO-06 Recipe suggestion output
- §10.1 `inventory_scans` collection
- §12.1 REST endpoints for inventory
- §13 UX-14 "Why this recipe?" explanation on suggestion cards
- NFR-01 Scan-to-suggestions p95 <= 6.0s
- NFR-06 Scan Quality and Trust
- NFR-07 Demo must include at least one grounded suggestion explanation

## Tech Guide References

- §1 Vertex AI — Vision (image analysis), `gs://` URIs
- §5 Firestore — AsyncClient
- §7 GCS — upload, signed URLs

---

## Data Model

### Pydantic Models — `app/models/inventory.py`

```python
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
import uuid

class DetectedIngredient(BaseModel):
    name: str                      # e.g., "red bell pepper"
    name_normalized: str           # e.g., "red bell pepper"
    confidence: float              # 0.0 - 1.0
    source_image_index: int        # Which uploaded image it was spotted in

class InventoryScanCreate(BaseModel):
    source: str                    # "fridge" | "pantry"

class InventoryScan(BaseModel):
    scan_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    uid: str
    source: str
    image_uris: list[str] = []                    # gs:// URIs
    detected_ingredients: list[DetectedIngredient] = []
    confidence_map: dict[str, float] = {}         # name -> confidence
    confirmed_ingredients: list[str] = []         # After user confirmation
    status: str = "pending"                       # pending | detected | confirmed
    created_at: datetime = Field(default_factory=datetime.utcnow)

class IngredientConfirmation(BaseModel):
    confirmed_ingredients: list[str]              # User-edited final list

class RecipeSuggestion(BaseModel):
    suggestion_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    source_type: str              # "saved_recipe" | "buddy_generated"
    recipe_id: Optional[str] = None  # Only for saved_recipe
    title: str
    description: Optional[str] = None
    match_score: float            # 0.0 - 1.0
    matched_ingredients: list[str] = []
    missing_ingredients: list[str] = []
    estimated_time_min: Optional[int] = None
    difficulty: Optional[str] = None
    cuisine: Optional[str] = None
    source_label: str             # "Saved" | "Buddy"
    # Grounding & explainability (§7.11)
    explanation: str = ""         # Human-readable "Why this recipe?" text
    grounding_sources: list[str] = []  # What evidence supports this suggestion
    assumptions: list[str] = []   # For buddy recipes: what the model assumed
```

---

## Tasks

### 3.1 Image/Video Upload & Scan Creation

**What:** Accept either:
- 2-6 fridge/pantry images, or
- 1 short fridge/pantry video (extract keyframes server-side),
then upload media to GCS, create scan record in Firestore, and return `scan_id`.

**Endpoint:** `POST /v1/inventory-scans`

**Implementation:**

```python
from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException
from app.auth.firebase import get_current_user
from app.services.storage import upload_bytes
from app.services.media import extract_keyframes_to_gcs
from app.services.firestore import db
from google.cloud import firestore
import uuid

router = APIRouter()

@router.post("/inventory-scans")
async def create_inventory_scan(
    source: str = Form(...),   # "fridge" | "pantry"
    images: list[UploadFile] | None = File(default=None),
    video: UploadFile | None = File(default=None),
    user: dict = Depends(get_current_user),
):
    images = images or []
    if source not in ("fridge", "pantry"):
        raise HTTPException(400, "source must be 'fridge' or 'pantry'")

    # Exactly one capture mode must be provided
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
        # Extract 3 representative keyframes to align with the image-only detection path.
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
```

**Acceptance Criteria:**
- [ ] Accepts either 2-6 images OR 1 short video via multipart upload
- [ ] Images stored in GCS at `inventory-scans/{uid}/{scan_id}/{index}.jpg`
- [ ] For video mode, keyframes are extracted and stored to the same path convention
- [ ] Scan record created in Firestore with status `pending`
- [ ] Returns `scan_id` for subsequent calls

---

### 3.2 Ingredient Extraction via Gemini Vision

**What:** Process uploaded images through Gemini Flash to detect ingredients with confidence scores.

**Endpoint:** `POST /v1/inventory-scans/{scan_id}/detect` (called automatically after upload, or as separate step)

**Implementation:**

```python
from google.genai import types
from app.services.gemini import gemini_client, MODEL_FLASH
import json

async def extract_ingredients_from_images(image_uris: list[str], source: str) -> list[dict]:
    """Use Gemini Flash to detect ingredients from fridge/pantry images."""
    parts = []
    for uri in image_uris:
        # Use gs:// URI directly — no download needed
        mime_type = "image/jpeg"
        parts.append(types.Part.from_uri(file_uri=uri, mime_type=mime_type))

    parts.append(f"""Analyze these {source} images and identify all visible food ingredients.

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

Return ONLY a JSON array of objects with the fields above.""")

    response = await gemini_client.aio.models.generate_content(
        model=MODEL_FLASH,
        contents=parts,
    )

    try:
        ingredients = json.loads(response.text)
        return ingredients
    except json.JSONDecodeError:
        # Try to extract JSON from markdown code block
        import re
        match = re.search(r'```(?:json)?\s*([\s\S]*?)```', response.text)
        if match:
            return json.loads(match.group(1))
        return []

@router.post("/inventory-scans/{scan_id}/detect")
async def detect_ingredients(
    scan_id: str,
    user: dict = Depends(get_current_user),
):
    doc = await db.collection("inventory_scans").document(scan_id).get()
    if not doc.exists:
        raise HTTPException(404, "Scan not found")
    scan = doc.to_dict()
    if scan["uid"] != user["uid"]:
        raise HTTPException(403, "Not your scan")

    raw_ingredients = await extract_ingredients_from_images(
        scan["image_uris"], scan["source"]
    )

    # Normalize and structure
    from app.services.ingredients import normalize_ingredient
    detected = []
    confidence_map = {}
    for item in raw_ingredients:
        name = item.get("name", "")
        norm = normalize_ingredient(name)
        confidence = min(max(item.get("confidence", 0.5), 0.0), 1.0)
        detected.append({
            "name": name,
            "name_normalized": norm,
            "confidence": confidence,
            "source_image_index": item.get("source_image_index", 0),
        })
        confidence_map[norm] = confidence

    # Sort by confidence descending
    detected.sort(key=lambda x: x["confidence"], reverse=True)

    await db.collection("inventory_scans").document(scan_id).update({
        "detected_ingredients": detected,
        "confidence_map": confidence_map,
        "status": "detected",
    })

    return {
        "scan_id": scan_id,
        "detected_ingredients": detected,
        "status": "detected",
        "low_confidence_count": sum(1 for d in detected if d["confidence"] < 0.5),
    }
```

**Design Notes:**
- Uses `gs://` URIs directly with Gemini — no downloading images (per tech guide anti-pattern)
- Confidence thresholds: >= 0.8 high, 0.5-0.79 medium, < 0.5 low
- Per NFR-06: Always expose confidence and allow manual correction
- Per FP-08: If all ingredients are low confidence, UI should suggest manual entry

**Acceptance Criteria:**
- [ ] Sends up to 6 images to Gemini Flash via `gs://` URIs
- [ ] Video mode uses extracted keyframes through the same detection path
- [ ] Returns structured ingredient list with confidence scores
- [ ] Ingredients normalized for downstream matching
- [ ] Low confidence count surfaced for UI decision-making
- [ ] Scan status updated to `detected`
- [ ] p95 latency target: <= 6.0s for up to 3 images

---

### 3.3 User Ingredient Confirmation

**What:** User reviews detected ingredients, adds/removes items, and confirms the final list.

**Endpoint:** `POST /v1/inventory-scans/{scan_id}/confirm-ingredients`

```python
@router.post("/inventory-scans/{scan_id}/confirm-ingredients")
async def confirm_ingredients(
    scan_id: str,
    body: IngredientConfirmation,
    user: dict = Depends(get_current_user),
):
    doc = await db.collection("inventory_scans").document(scan_id).get()
    if not doc.exists:
        raise HTTPException(404, "Scan not found")
    scan = doc.to_dict()
    if scan["uid"] != user["uid"]:
        raise HTTPException(403, "Not your scan")
    if scan["status"] not in ("detected", "confirmed"):
        raise HTTPException(400, "Scan must be in 'detected' state first")

    from app.services.ingredients import normalize_ingredient
    confirmed = [normalize_ingredient(i) for i in body.confirmed_ingredients]

    await db.collection("inventory_scans").document(scan_id).update({
        "confirmed_ingredients": confirmed,
        "status": "confirmed",
    })

    return {"scan_id": scan_id, "confirmed_ingredients": confirmed, "status": "confirmed"}
```

**Acceptance Criteria:**
- [ ] User can pass any list (add new items, remove detected ones)
- [ ] All confirmed ingredients normalized
- [ ] Status transitions to `confirmed`
- [ ] Per NFR-06: Never auto-start cooking from unconfirmed detections

---

### 3.4 Saved Recipe Matching

**What:** Match confirmed ingredients against user's saved recipes. Return ranked suggestions with match scores and missing ingredients.

**Implementation:**

```python
from app.services.ingredients import match_ingredients

async def find_matching_saved_recipes(uid: str, confirmed_ingredients: list[str]) -> list[dict]:
    """Query user's recipes and rank by ingredient match + time fit + skill fit."""
    user_doc = await db.collection("users").document(uid).get()
    profile = user_doc.to_dict() if user_doc.exists else {}
    prefs = {
        "max_time_minutes": profile.get("max_time_minutes", 40),
        "skill_level": profile.get("skill_level", "medium"),  # easy|medium|hard
    }

    def difficulty_score(difficulty: str | None, skill_level: str) -> float:
        order = {"easy": 0, "medium": 1, "hard": 2}
        d = order.get((difficulty or "medium").lower(), 1)
        s = order.get((skill_level or "medium").lower(), 1)
        # Perfect when aligned, degrades as mismatch increases.
        return max(0.0, 1.0 - (abs(d - s) * 0.5))

    def time_score(estimated_time_min: int | None, max_time_minutes: int) -> float:
        if not estimated_time_min:
            return 0.7
        if estimated_time_min <= max_time_minutes:
            return 1.0
        over = estimated_time_min - max_time_minutes
        return max(0.0, 1.0 - (over / max(15, max_time_minutes)))

    def rank_score(match_score: float, missing_count: int, t_score: float, s_score: float) -> float:
        # FP-06 aligned: ingredient match coverage, missing ingredient count, time fit, skill fit.
        missing_penalty = max(0.0, 1.0 - (0.2 * missing_count))
        return round(
            (0.50 * match_score) +
            (0.20 * missing_penalty) +
            (0.20 * t_score) +
            (0.10 * s_score),
            3,
        )

    query = db.collection("recipes").where("uid", "==", uid)
    recipes = [doc.to_dict() async for doc in query.stream()]

    suggestions = []
    for recipe in recipes:
        result = match_ingredients(confirmed_ingredients, recipe.get("ingredients_normalized", []))

        if result["match_score"] > 0.3:  # At least 30% ingredient match
            # GE-01: Grounded explanation citing detected ingredients + match features
            matched_str = ", ".join(result["matched"][:5])
            missing_str = ", ".join(result["missing"][:3]) if result["missing"] else "nothing"
            explanation = (
                f"You have {len(result['matched'])} of {len(recipe.get('ingredients_normalized', []))} "
                f"ingredients ({matched_str}). "
                f"{'Only missing ' + missing_str + '.' if result['missing'] else 'You have everything!'}"
            )
            grounding_sources = [
                f"Matched from your confirmed scan: {matched_str}",
                f"Recipe saved on your account: {recipe['recipe_id']}",
            ]

            suggestions.append({
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
                "time_fit": time_score(recipe.get("total_time_minutes"), prefs["max_time_minutes"]),
                "skill_fit": difficulty_score(recipe.get("difficulty"), prefs["skill_level"]),
            })

    for s in suggestions:
        s["ranking_score"] = rank_score(
            s["match_score"],
            len(s["missing_ingredients"]),
            s["time_fit"],
            s["skill_fit"],
        )

    # FP-06 ranking: match coverage -> missing count -> time fit -> skill fit
    suggestions.sort(
        key=lambda s: (-s["ranking_score"], -s["match_score"], len(s["missing_ingredients"]))
    )
    return suggestions[:5]  # Top 5
```

**Acceptance Criteria:**
- [ ] Queries only the user's recipes
- [ ] Calculates match score using normalized ingredients
- [ ] Returns matched and missing ingredient lists per suggestion
- [ ] Filters out < 30% matches
- [ ] Sorted by ranking score using FP-06 factors (match, missing count, time fit, skill fit)
- [ ] Each suggestion includes grounded `explanation` citing confirmed ingredients (GE-01)
- [ ] `grounding_sources` lists the evidence (scan match + saved recipe reference)

---

### 3.5 Buddy-Generated Recipe Suggestions

**What:** Use Gemini Flash to generate 2-3 recipe ideas constrained to the confirmed ingredients.

**Implementation:**

```python
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

    import json, re
    try:
        recipes = json.loads(response.text)
    except json.JSONDecodeError:
        match = re.search(r'```(?:json)?\s*([\s\S]*?)```', response.text)
        if match:
            recipes = json.loads(match.group(1))
        else:
            return []

    suggestions = []
    for recipe in recipes:
        suggestions.append({
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
            # GE-02: Expose assumptions and grounded explanation
            "explanation": recipe.get("explanation", ""),
            "grounding_sources": [f"Generated from your confirmed ingredients: {ingredients_str}"],
            "assumptions": recipe.get("assumptions", []),
        })

    return suggestions
```

**Acceptance Criteria:**
- [ ] Generates 2-3 recipe ideas from confirmed ingredients
- [ ] Missing ingredients limited to common pantry staples
- [ ] Each suggestion has match score and structured metadata
- [ ] Each suggestion includes human-readable `explanation` of why it fits (GE-02)
- [ ] Each suggestion lists `assumptions` (e.g., "assumes basic pantry staples") (GE-02)
- [ ] Graceful fallback if Gemini returns unparseable response

---

### 3.6 Dual-Lane Suggestions Endpoint

**What:** Combine saved recipe matches and buddy-generated suggestions into a dual-lane response.

**Endpoint:** `GET /v1/inventory-scans/{scan_id}/suggestions`

```python
@router.get("/inventory-scans/{scan_id}/suggestions")
async def get_suggestions(
    scan_id: str,
    user: dict = Depends(get_current_user),
):
    doc = await db.collection("inventory_scans").document(scan_id).get()
    if not doc.exists:
        raise HTTPException(404, "Scan not found")
    scan = doc.to_dict()
    if scan["uid"] != user["uid"]:
        raise HTTPException(403, "Not your scan")
    if scan["status"] != "confirmed":
        raise HTTPException(400, "Ingredients must be confirmed first")

    confirmed = scan["confirmed_ingredients"]
    user_doc = await db.collection("users").document(user["uid"]).get()
    profile = user_doc.to_dict() if user_doc.exists else {}
    prefs = {
        "max_time_minutes": profile.get("max_time_minutes", 40),
        "skill_level": profile.get("skill_level", "medium"),
    }

    def difficulty_score(difficulty: str | None, skill_level: str) -> float:
        order = {"easy": 0, "medium": 1, "hard": 2}
        d = order.get((difficulty or "medium").lower(), 1)
        s = order.get((skill_level or "medium").lower(), 1)
        return max(0.0, 1.0 - (abs(d - s) * 0.5))

    def time_score(estimated_time_min: int | None, max_time_minutes: int) -> float:
        if not estimated_time_min:
            return 0.7
        if estimated_time_min <= max_time_minutes:
            return 1.0
        over = estimated_time_min - max_time_minutes
        return max(0.0, 1.0 - (over / max(15, max_time_minutes)))

    def rank_score(match_score: float, missing_count: int, t_score: float, s_score: float) -> float:
        missing_penalty = max(0.0, 1.0 - (0.2 * missing_count))
        return round(
            (0.50 * match_score) +
            (0.20 * missing_penalty) +
            (0.20 * t_score) +
            (0.10 * s_score),
            3,
        )

    # Run both suggestion engines in parallel
    import asyncio
    saved_task = asyncio.create_task(
        find_matching_saved_recipes(user["uid"], confirmed)
    )
    buddy_task = asyncio.create_task(
        generate_buddy_recipes(confirmed)
    )

    saved_suggestions, buddy_suggestions = await asyncio.gather(saved_task, buddy_task)

    # Apply FP-06 ranking consistently to both lanes.
    for lane in (saved_suggestions, buddy_suggestions):
        for s in lane:
            s["time_fit"] = time_score(s.get("estimated_time_min"), prefs["max_time_minutes"])
            s["skill_fit"] = difficulty_score(s.get("difficulty"), prefs["skill_level"])
            s["ranking_score"] = rank_score(
                s.get("match_score", 0.0),
                len(s.get("missing_ingredients", [])),
                s["time_fit"],
                s["skill_fit"],
            )
        lane.sort(key=lambda s: (-s["ranking_score"], -s.get("match_score", 0.0), len(s.get("missing_ingredients", []))))

    # Persist suggestions in Firestore subcollection
    all_suggestions = saved_suggestions + buddy_suggestions
    for suggestion in all_suggestions:
        await db.collection("inventory_scans").document(scan_id) \
            .collection("suggestions").document(suggestion["suggestion_id"]) \
            .set(suggestion)

    return {
        "scan_id": scan_id,
        "from_saved": saved_suggestions,
        "buddy_recipes": buddy_suggestions,
        "total_suggestions": len(all_suggestions),
    }
```

**Design Notes:**
- Saved and buddy suggestions are computed in parallel via `asyncio.gather`
- Response structure matches PRD §MO-06 dual-lane format
- Suggestions persisted in subcollection for later selection

**Acceptance Criteria:**
- [ ] Returns two lanes: `from_saved` and `buddy_recipes`
- [ ] Both computed in parallel
- [ ] Each card includes: match_score, missing_ingredients, estimated_time, difficulty, source_label
- [ ] Each card includes: explanation, grounding_sources, assumptions (GE-01, GE-02)
- [ ] Both lanes use FP-06 ranking factors (match, missing count, time fit, skill fit)
- [ ] Suggestions persisted in Firestore subcollection
- [ ] Combined p95 latency target: <= 6.0s

---

### 3.7 Start Session from Suggestion

**What:** User selects a suggestion and transitions to cooking session creation.

**Endpoint:** `POST /v1/inventory-scans/{scan_id}/start-session`

```python
from pydantic import BaseModel

class StartSessionFromSuggestionRequest(BaseModel):
    suggestion_id: str
    mode_settings: dict = {}

@router.post("/inventory-scans/{scan_id}/start-session")
async def start_session_from_scan(
    scan_id: str,
    body: StartSessionFromSuggestionRequest,
    user: dict = Depends(get_current_user),
):
    # Verify scan ownership
    scan_doc = await db.collection("inventory_scans").document(scan_id).get()
    if not scan_doc.exists:
        raise HTTPException(404, "Scan not found")
    scan = scan_doc.to_dict()
    if scan["uid"] != user["uid"]:
        raise HTTPException(403, "Not your scan")

    # Get selected suggestion
    suggestion_doc = await db.collection("inventory_scans").document(scan_id) \
        .collection("suggestions").document(body.suggestion_id).get()
    if not suggestion_doc.exists:
        raise HTTPException(404, "Suggestion not found")
    suggestion = suggestion_doc.to_dict()

    # If it's a saved recipe, use existing recipe_id
    # If it's buddy-generated, create a new recipe from the suggestion
    recipe_id = suggestion.get("recipe_id")
    if suggestion["source_type"] == "buddy_generated" and not recipe_id:
        # Generate full recipe from buddy suggestion
        recipe_id = await create_recipe_from_buddy_suggestion(
            suggestion, scan["confirmed_ingredients"], user["uid"]
        )

    # Create session directly to avoid client-side API contract mismatch.
    from app.services.sessions import create_session_record
    session = await create_session_record(
        uid=user["uid"],
        recipe_id=recipe_id,
        mode_settings=body.mode_settings,
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
```

**For buddy-generated recipes, expand into full recipe:**

```python
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
- ingredients: array of {{name, quantity, unit, preparation}}
- steps: array of {{step_number, instruction, duration_minutes, technique_tags}}

Make it practical and achievable. Use the available ingredients as much as possible.
Return ONLY valid JSON.""",
    )

    import json, re
    try:
        parsed = json.loads(response.text)
    except json.JSONDecodeError:
        match = re.search(r'```(?:json)?\s*([\s\S]*?)```', response.text)
        parsed = json.loads(match.group(1)) if match else {}

    recipe_id = str(uuid.uuid4())
    # ... create recipe document using Epic 2 creation flow
    # ... set source_type = "buddy_generated"
    return recipe_id
```

**Acceptance Criteria:**
- [ ] User can select any suggestion (saved or buddy)
- [ ] Saved recipes use existing recipe_id
- [ ] Buddy recipes expanded into full recipe with steps
- [ ] Creates session directly and returns `session_id` + activate endpoint contract
- [ ] Transitions cleanly to Epic 4 session flow

---

### 3.8 "Why This Recipe?" Explainability Endpoint

**What:** Provide an expandable explanation for any suggestion card, grounded in the user's confirmed ingredients and recipe data. This fulfills PRD §7.11 (GE-01 through GE-04) and UX-14.

**Endpoint:** `GET /v1/inventory-scans/{scan_id}/suggestions/{suggestion_id}/explain`

**Design Notes:**
- The `explanation` field is already returned inline with every suggestion (tasks 3.4 and 3.5). This endpoint provides a richer, expandable explanation on demand when the user taps "Why this recipe?" on a card.
- Per GE-03: confidence-aware language — never claim certainty for medium/low confidence detections.
- Per GE-04: demo must show this at least once.

```python
@router.get("/inventory-scans/{scan_id}/suggestions/{suggestion_id}/explain")
async def explain_suggestion(
    scan_id: str,
    suggestion_id: str,
    user: dict = Depends(get_current_user),
):
    scan_doc = await db.collection("inventory_scans").document(scan_id).get()
    if not scan_doc.exists:
        raise HTTPException(404, "Scan not found")
    scan = scan_doc.to_dict()
    if scan["uid"] != user["uid"]:
        raise HTTPException(403)

    suggestion_doc = await db.collection("inventory_scans").document(scan_id) \
        .collection("suggestions").document(suggestion_id).get()
    if not suggestion_doc.exists:
        raise HTTPException(404, "Suggestion not found")
    suggestion = suggestion_doc.to_dict()

    confirmed = scan["confirmed_ingredients"]
    confidence_map = scan.get("confidence_map", {})

    # Build grounded explanation
    matched = suggestion.get("matched_ingredients", [])
    missing = suggestion.get("missing_ingredients", [])
    assumptions = suggestion.get("assumptions", [])

    # GE-03: Flag low-confidence detections used in matching
    low_confidence_matches = [
        ing for ing in matched
        if confidence_map.get(ing, 1.0) < 0.5
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
        explanation_parts.append(
            f"Note: I wasn't fully certain about {names} from the scan — "
            f"double-check you actually have {'it' if len(low_confidence_matches) == 1 else 'them'}."
        )

    # GE-02: Surface assumptions for buddy recipes
    if assumptions:
        explanation_parts.append(
            f"I assumed: {'; '.join(assumptions)}."
        )

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
```

**Acceptance Criteria:**
- [ ] Returns grounded explanation citing confirmed ingredients (GE-01)
- [ ] Buddy recipes expose assumptions (GE-02)
- [ ] Low-confidence scan detections flagged with trust caveat (GE-03)
- [ ] Expandable "Why this recipe?" available for every suggestion card (GE-04)
- [ ] Language avoids false certainty for medium/low confidence items
- [ ] At least one explanation shown in demo (NFR-07)

---

### 3.9 Register Inventory Router

**What:** Mount inventory router in main app.

```python
from app.routers import inventory
app.include_router(inventory.router, prefix="/v1", tags=["inventory"])
```

**Acceptance Criteria:**
- [ ] All inventory endpoints accessible under `/v1/inventory-scans/...`
- [ ] All endpoints require auth

---

### 3.10 Mobile UX Implementation (Scan + Suggestions)

**What:** Build and validate mobile UX states for the full inventory-to-suggestion flow.

**Required mobile UX components:**
1. Capture entry sheet with explicit source selector (`Fridge` | `Pantry`) and mode selector (`Photos` | `Video`).
2. Capture guidance UI:
   - Photo mode: progress (`2/6 minimum`)
   - Video mode: duration guardrail (`3-10s`) and capture timer.
3. Ingredient review UI:
   - Confidence-coded chips (`high/medium/low`)
   - Fast add/remove/edit interactions
   - Sticky `Confirm Ingredients` CTA
4. Suggestion screen:
   - Two clear lanes (`From Saved`, `Buddy Recipes`)
   - Card-level `Why this recipe?` expansion
   - Visible match score, missing count, estimated time, difficulty
5. Loading/error states:
   - Skeleton cards for suggestion generation
   - Retry affordance for detect/suggestions failure
   - Explicit fallback CTA: `Enter ingredients manually`

**Acceptance Criteria:**
- [ ] Flow is completable one-handed on mobile
- [ ] User can complete scan->confirm->suggestions in <= 4 taps after media capture
- [ ] `Why this recipe?` is accessible directly from every card
- [ ] All loading states visible for operations > 400ms
- [ ] Error states always provide next action (retry, manual entry, back)

---

## End-to-End Flow Summary

```
1. POST /v1/inventory-scans          → Upload images, get scan_id
2. POST /v1/inventory-scans/{id}/detect  → Detect ingredients + confidence
3. [Mobile UI: user edits ingredient chips]
4. POST /v1/inventory-scans/{id}/confirm-ingredients  → Lock ingredient list
5. GET  /v1/inventory-scans/{id}/suggestions  → Dual-lane suggestions (with grounding)
6. [Mobile UI: user taps "Why this recipe?" on a card]
7. GET  /v1/inventory-scans/{id}/suggestions/{sid}/explain  → Grounded explanation
8. [Mobile UI: user picks a suggestion]
9. POST /v1/inventory-scans/{id}/start-session  → Creates session + returns activate contract
```

## Epic Completion Checklist

- [ ] Image upload to GCS working
- [ ] Gemini vision extracting ingredients with confidence
- [ ] User confirmation/edit flow functional
- [ ] Saved recipe matching with scores
- [ ] Buddy recipe generation with constraints
- [ ] Dual-lane suggestion response matching PRD spec
- [ ] Every suggestion includes grounded explanation and assumptions
- [ ] "Why this recipe?" endpoint returns expandable, confidence-aware explanation
- [ ] Start-session bridge to Epic 4
- [ ] Suggestions ranked using FP-06 factors (match, missing, time fit, skill fit)
- [ ] Mobile UX flow validated (capture, ingredient chips, dual-lane cards, loading/error states)
- [ ] p95 scan-to-suggestions under 6 seconds
