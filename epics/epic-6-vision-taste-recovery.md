# Epic 6: Vision, Visual Guides, Taste & Recovery

## Goal

Three specialist capabilities that make the cooking buddy truly multimodal: (1) vision-based doneness assessment with confidence tiers, (2) AI-generated target-state guide images for comparison, and (3) taste diagnostic and error recovery flows.

## Prerequisites

- Epic 4 complete (session lifecycle, WebSocket, orchestrator agent)

## PRD References

- §7.5 Vision Confidence Hierarchy (VC-01 through VC-04)
- §7.3 MO-05 AI-generated guide image output
- §7.8 Taste and Recovery (TR-01 through TR-04)
- §12.1 Vision-check, visual-guide, taste-check, recover endpoints
- NFR-01 Vision check p95 <= 3.5s

## Tech Guide References

- §1 Vertex AI — Vision analysis, Image generation (multi-turn chat)
- §2 ADK — Agent tools, specialist agents
- §7 GCS — Upload guide images, `gs://` URIs

---

## Tasks

### 6.1 Vision Assessor Agent (ADK)

**What:** Specialist agent that receives a camera frame, assesses food state, and returns a confidence-tiered response.

**Implementation:** `app/agents/vision.py`

```python
from google.adk.agents import Agent
from google.adk.tools import FunctionTool, ToolContext
from google.genai import types
from app.services.gemini import gemini_client, MODEL_FLASH
import json

async def assess_food_image(image_uri: str, current_step: dict, recipe_title: str) -> dict:
    """Analyze a food image and return confidence-tiered assessment."""
    step_context = f"Step {current_step['step_number']}: {current_step['instruction']}"
    technique = ", ".join(current_step.get("technique_tags", []))

    response = await gemini_client.aio.models.generate_content(
        model=MODEL_FLASH,
        contents=[
            types.Part.from_uri(file_uri=image_uri, mime_type="image/jpeg"),
            f"""You are assessing food being cooked for the recipe "{recipe_title}".
Current step: {step_context}
Technique: {technique}

Analyze the image and assess:
1. What food state do you see? (color, texture, doneness level)
2. How confident are you in your assessment? (0.0-1.0)
3. Is this the expected state for this step?
4. What should the user do next?

Return JSON:
{{
  "confidence": float (0.0-1.0),
  "confidence_tier": "high" | "medium" | "low" | "failed",
  "assessment": "description of what you see",
  "is_expected_state": boolean,
  "recommendation": "what to do next",
  "sensory_fallback": "smell/sound/texture cues if vision is uncertain"
}}

Confidence tiers:
- high (>= 0.8): Clear view, confident assessment
- medium (0.5-0.79): Partially visible, qualified answer
- low (0.2-0.49): Obscured/unclear, ask for reposition
- failed (< 0.2): Cannot assess, fall back entirely to non-visual guidance

Return ONLY valid JSON.""",
        ],
    )

    import re
    try:
        result = json.loads(response.text)
    except json.JSONDecodeError:
        match = re.search(r'```(?:json)?\s*([\s\S]*?)```', response.text)
        if match:
            result = json.loads(match.group(1))
        else:
            result = {
                "confidence": 0.0,
                "confidence_tier": "failed",
                "assessment": "I couldn't process the image.",
                "is_expected_state": None,
                "recommendation": "Try repositioning your camera and ask me to look again.",
                "sensory_fallback": "Check by smell, sound, and touch instead.",
            }

    return result
```

**Acceptance Criteria:**
- [ ] Accepts `gs://` image URI
- [ ] Returns confidence tier (high/medium/low/failed)
- [ ] Assessment contextualized to current recipe step
- [ ] Sensory fallback included for all tiers
- [ ] p95 response time <= 3.5s

---

### 6.2 Vision Confidence Hierarchy Response

**What:** Format the vision response differently based on confidence tier.

**Implementation:**

```python
def format_vision_response(assessment: dict) -> dict:
    """Format vision check response based on confidence tier (PRD §7.5)."""
    tier = assessment["confidence_tier"]

    if tier == "high":
        # VC-01: Direct confirmation or correction
        return {
            "type": "vision_result",
            "confidence": "high",
            "message": assessment["assessment"],
            "recommendation": assessment["recommendation"],
            "tone": "confident",
        }

    elif tier == "medium":
        # VC-02: Qualified answer + sensory check prompt
        return {
            "type": "vision_result",
            "confidence": "medium",
            "message": f"{assessment['assessment']} — but I'm not 100% sure from this angle.",
            "recommendation": assessment["recommendation"],
            "sensory_check": assessment["sensory_fallback"],
            "tone": "qualified",
        }

    elif tier == "low":
        # VC-03: Ask for reposition + sensory fallback
        return {
            "type": "vision_result",
            "confidence": "low",
            "message": "I can't see clearly enough to tell. Can you bring the camera closer or tilt the pan toward me?",
            "sensory_check": assessment["sensory_fallback"],
            "tone": "uncertain",
        }

    else:
        # VC-04: Explicit inability + non-visual guidance
        return {
            "type": "vision_result",
            "confidence": "failed",
            "message": "I can't assess this visually right now. Let's use other senses instead.",
            "sensory_check": assessment["sensory_fallback"],
            "tone": "fallback",
        }
```

**Acceptance Criteria:**
- [ ] Four distinct response formats matching PRD confidence hierarchy
- [ ] High: direct, confident
- [ ] Medium: qualified + sensory check
- [ ] Low: reposition request + sensory fallback
- [ ] Failed: explicit inability + full sensory guidance

---

### 6.3 Vision Check Endpoint

**What:** REST endpoint for vision checks (alternative to WebSocket path).

**Endpoint:** `POST /v1/sessions/{session_id}/vision-check`

```python
@router.post("/sessions/{session_id}/vision-check")
async def vision_check(
    session_id: str,
    frame: UploadFile = File(...),
    user: dict = Depends(get_current_user),
):
    session_doc = await db.collection("sessions").document(session_id).get()
    if not session_doc.exists:
        raise HTTPException(404)
    session = session_doc.to_dict()
    if session["uid"] != user["uid"]:
        raise HTTPException(403)

    # Upload frame to GCS
    content = await frame.read()
    timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    path = f"session-uploads/{user['uid']}/{session_id}/{timestamp}.jpg"
    frame_uri = upload_bytes(path, content, "image/jpeg")

    # Load current step from recipe
    recipe_doc = await db.collection("recipes").document(session["recipe_id"]).get()
    recipe = recipe_doc.to_dict()
    current_step_num = session.get("current_step", 1)
    steps = recipe.get("steps", [])
    current_step = steps[current_step_num - 1] if current_step_num <= len(steps) else steps[-1]

    # Assess
    assessment = await assess_food_image(frame_uri, current_step, recipe["title"])
    response = format_vision_response(assessment)

    # Log event
    await log_session_event(session_id, "vision_check", {
        "frame_uri": frame_uri,
        "assessment": assessment,
    })

    return response
```

**Acceptance Criteria:**
- [ ] Accepts image upload
- [ ] Stores frame in GCS
- [ ] Returns confidence-tiered assessment
- [ ] Event logged in session
- [ ] p95 <= 3.5s end-to-end

---

### 6.4 Guide Image Generator Agent (ADK)

**What:** Generates target-state visual guide images using `gemini-2.0-flash-preview-image-generation`. Maintains a single chat session per cooking session for visual style consistency.

**Implementation:** `app/agents/guide_image.py`

```python
from google.genai import types
from app.services.gemini import gemini_client, MODEL_IMAGE_GEN
from app.services.storage import upload_bytes
import asyncio, base64, uuid

class GuideImageGenerator:
    """Generates target-state visual guides with consistent style per session."""

    def __init__(self, session_id: str, recipe_title: str):
        self.session_id = session_id
        self.recipe_title = recipe_title
        # Single chat session for style consistency (per tech guide §1)
        self.chat = gemini_client.chats.create(
            model=MODEL_IMAGE_GEN,
            config=types.GenerateContentConfig(
                response_modalities=["IMAGE", "TEXT"],
                system_instruction=f"""You generate realistic food photography images
showing target cooking states for the recipe "{recipe_title}".

Style rules:
- Overhead or 45-degree angle kitchen photography style
- Natural lighting, clean kitchen background
- Focus on the food state described
- Consistent visual style across all images in this session
- Realistic, not stylized or cartoon
""",
            ),
        )

    async def generate_guide(
        self,
        step: dict,
        stage_label: str,
        source_frame_uri: str = None,
    ) -> dict:
        """Generate a target-state guide image for a specific step/stage."""
        prompt = step.get("guide_image_prompt")
        if not prompt:
            prompt = f"Show the target state for: {step['instruction']}"

        # Add stage context
        full_prompt = f"""Generate an image showing: {prompt}

Stage: {stage_label}
This is for step {step['step_number']} of {self.recipe_title}.

Also provide 1-2 short text cues (max 8 words each) that describe
the key visual indicators to look for."""

        # send_message is sync in this SDK surface; run in thread to avoid blocking event loop.
        response = await asyncio.to_thread(self.chat.send_message, full_prompt)

        # Extract generated image and text cues
        image_bytes = None
        cue_text = ""
        for part in response.candidates[0].content.parts:
            if part.inline_data:
                image_bytes = part.inline_data.data
            elif part.text:
                cue_text = part.text

        if not image_bytes:
            return {"error": "No image generated"}

        # Upload to GCS
        guide_path = f"guide-images/{step.get('recipe_id', 'unknown')}/{step['step_number']}/{stage_label}.png"
        guide_uri = upload_bytes(guide_path, image_bytes, "image/png")

        # Parse cues from text
        cue_overlays = [line.strip("- •").strip() for line in cue_text.split("\n") if line.strip()][:2]

        # Persist in Firestore
        guide_id = str(uuid.uuid4())
        guide_data = {
            "guide_id": guide_id,
            "step_number": step["step_number"],
            "stage_label": stage_label,
            "source_frame_uri": source_frame_uri,
            "generated_guide_uri": guide_uri,
            "cue_overlays": cue_overlays,
        }

        await db.collection("sessions").document(self.session_id) \
            .collection("guide_images").document(guide_id).set(guide_data)

        # Generate signed URL for mobile display
        from app.services.storage import get_signed_url
        display_url = get_signed_url(guide_path)

        return {
            "guide_id": guide_id,
            "image_url": display_url,
            "cue_overlays": cue_overlays,
            "stage_label": stage_label,
        }
```

**Design Notes:**
- Single `chat` session per cooking session maintains visual consistency (tech guide §1)
- Guide image prompts stored in recipe seed data (Epic 2.6)
- Cue overlays extracted from model text response
- Images stored in GCS and served via signed URL

**Acceptance Criteria:**
- [ ] Generates realistic food-state images via Gemini Image Gen
- [ ] Visual style consistent across session (single chat session)
- [ ] 1-2 cue overlays extracted per image
- [ ] Images stored in GCS at structured path
- [ ] Signed URLs generated for mobile display

---

### 6.5 Visual Guide Endpoint

**What:** REST endpoint to request a target-state guide image for the current step.

**Endpoint:** `POST /v1/sessions/{session_id}/visual-guide`

```python
# Per-session guide generators (keyed by session_id)
_guide_generators: dict[str, GuideImageGenerator] = {}

@router.post("/sessions/{session_id}/visual-guide")
async def generate_visual_guide(
    session_id: str,
    stage_label: str = "target",         # e.g., "light_golden", "al_dente", "emulsified"
    source_frame: UploadFile = File(None),  # Optional: user's current frame for side-by-side
    user: dict = Depends(get_current_user),
):
    session_doc = await db.collection("sessions").document(session_id).get()
    if not session_doc.exists:
        raise HTTPException(404)
    session = session_doc.to_dict()
    if session["uid"] != user["uid"]:
        raise HTTPException(403)

    # Load recipe and current step
    recipe_doc = await db.collection("recipes").document(session["recipe_id"]).get()
    recipe = recipe_doc.to_dict()
    step_num = session.get("current_step", 1)
    steps = recipe.get("steps", [])
    step = steps[step_num - 1] if step_num <= len(steps) else steps[-1]
    step["recipe_id"] = session["recipe_id"]

    # Get or create guide generator for this session
    if session_id not in _guide_generators:
        _guide_generators[session_id] = GuideImageGenerator(session_id, recipe["title"])
    generator = _guide_generators[session_id]

    # Upload source frame if provided
    source_uri = None
    if source_frame:
        content = await source_frame.read()
        path = f"session-uploads/{user['uid']}/{session_id}/guide_source_{step_num}.jpg"
        source_uri = upload_bytes(path, content, "image/jpeg")

    # Generate guide
    result = await generator.generate_guide(step, stage_label, source_uri)

    if "error" in result:
        raise HTTPException(500, result["error"])

    # Return with side-by-side data if source frame was provided
    response = {
        "type": "guide_image",
        **result,
    }
    if source_uri:
        response["source_frame_url"] = get_signed_url(
            source_uri.replace(f"gs://{settings.gcs_bucket_name}/", "")
        )

    return response
```

**Side-by-side response for mobile UI:**
```json
{
  "type": "guide_image",
  "guide_id": "abc123",
  "image_url": "https://storage.googleapis.com/signed-url...",
  "cue_overlays": ["Edges are light golden", "Oil sheen visible"],
  "stage_label": "light_golden",
  "source_frame_url": "https://storage.googleapis.com/signed-url..."
}
```

**Acceptance Criteria:**
- [ ] Generates target-state image on demand
- [ ] Supports optional source frame for side-by-side
- [ ] Returns signed URL + cue overlays
- [ ] Style consistent across session
- [ ] Guide persisted in Firestore subcollection

---

### 6.6 Taste Coach Agent (ADK)

**What:** Specialist agent for taste diagnostics. Handles prompted taste checks, "something's missing" flows, and stage-aware seasoning recommendations.

**Implementation:** `app/agents/taste.py`

```python
from google.adk.agents import Agent
from google.adk.tools import FunctionTool, ToolContext

def get_taste_dimensions(tool_context: ToolContext) -> str:
    """Get the 5 taste dimensions for current dish assessment."""
    return json.dumps({
        "dimensions": [
            {"name": "salt", "description": "Overall saltiness level"},
            {"name": "acid", "description": "Brightness/tanginess"},
            {"name": "sweet", "description": "Sweetness level"},
            {"name": "fat", "description": "Richness/mouthfeel"},
            {"name": "umami", "description": "Depth/savory intensity"},
        ],
        "current_stage": tool_context.state.get("current_step_technique", "general"),
    })

def run_diagnostic(user_response: str, tool_context: ToolContext) -> str:
    """Process user's taste description and suggest adjustments."""
    step = tool_context.state.get("current_step", {})
    technique = ", ".join(step.get("technique_tags", []))

    return json.dumps({
        "user_feedback": user_response,
        "technique_context": technique,
        "stage": "mid-cook" if step.get("step_number", 0) < tool_context.state.get("total_steps", 0) else "final",
    })

taste_coach = Agent(
    model="gemini-2.5-flash",
    name="taste_coach",
    instruction="""You are a taste diagnostic specialist for cooking.

Taste trigger order (TR-01):
1. Prompted: You suggest a taste check at appropriate moments
2. User-explicit: User says "it tastes off" or "something's missing"
3. Visual gesture fallback: User brings spoon to mouth on camera

Five dimensions (TR-02): salt, acid, sweet, fat, umami
Always consider the COOKING STAGE when recommending adjustments:
- Early: Bold adjustments are safe, flavors will meld
- Mid: Moderate adjustments, some concentration will occur
- Late/Final: Small adjustments only, what you add is what you get

"Something's missing" diagnostic flow (TR-03) — 3 questions max:
1. "Does it taste flat or dull?" → likely needs acid (lemon/vinegar) or salt
2. "Does it taste sharp or too bright?" → likely needs fat (butter/oil) or sweetness
3. "Does it taste one-note?" → likely needs umami (parmesan/soy) or contrasting element

Keep recommendations specific:
- BAD: "add some acid"
- GOOD: "squeeze half a lemon over it" or "a splash of white wine vinegar"

Always quantify: "about half a teaspoon", "a small pinch", "one tablespoon".""",
    tools=[
        FunctionTool(get_taste_dimensions),
        FunctionTool(run_diagnostic),
    ],
)
```

**Acceptance Criteria:**
- [ ] Five taste dimensions assessed with stage awareness
- [ ] "Something's missing" 3-question diagnostic flow
- [ ] Recommendations are specific (ingredient + quantity)
- [ ] Stage-aware (early/mid/late affects advice boldness)
- [ ] Trigger order: prompted > user-explicit > visual gesture

---

### 6.7 Taste Check Endpoint

**Endpoint:** `POST /v1/sessions/{session_id}/taste-check`

```python
@router.post("/sessions/{session_id}/taste-check")
async def taste_check(
    session_id: str,
    description: str = "",  # User's taste description, or empty for prompted check
    user: dict = Depends(get_current_user),
):
    session_doc = await db.collection("sessions").document(session_id).get()
    if not session_doc.exists:
        raise HTTPException(404)
    session = session_doc.to_dict()
    if session["uid"] != user["uid"]:
        raise HTTPException(403)

    recipe_doc = await db.collection("recipes").document(session["recipe_id"]).get()
    recipe = recipe_doc.to_dict()
    step_num = session.get("current_step", 1)
    current_step = recipe["steps"][step_num - 1] if step_num <= len(recipe["steps"]) else recipe["steps"][-1]

    # Determine if prompted or user-explicit
    if not description:
        # Prompted taste check
        return {
            "type": "taste_prompt",
            "message": "Good moment to taste! Take a small spoonful and tell me how it is.",
            "dimensions": ["salt", "acid", "sweet", "fat", "umami"],
        }

    # User provided feedback — run diagnostic
    response = await gemini_client.aio.models.generate_content(
        model=MODEL_FLASH,
        contents=f"""The user is cooking {recipe['title']}, currently on step {step_num}:
"{current_step['instruction']}"

They tasted and said: "{description}"

Provide a taste diagnostic:
1. What dimension likely needs adjustment?
2. What specific ingredient and quantity to add?
3. Any warning about this stage of cooking?

Be specific, warm, and brief.""",
    )

    result = {
        "type": "taste_result",
        "message": response.text,
        "step": step_num,
    }

    await log_session_event(session_id, "taste_check", {
        "description": description,
        "response": response.text,
    })

    return result
```

**Acceptance Criteria:**
- [ ] Prompted check returns taste prompt with dimensions
- [ ] User feedback analyzed in context of current step
- [ ] Specific ingredient + quantity recommendations
- [ ] Stage-aware advice

---

### 6.8 Recovery Guide Agent (ADK)

**What:** Specialist agent for handling cooking errors. Follows the structured recovery sequence: immediate action → acknowledgment → honest assessment → concrete path forward.

**Implementation:** `app/agents/recovery.py`

```python
recovery_guide = Agent(
    model="gemini-2.5-flash",
    name="recovery_guide",
    instruction="""You handle cooking mistakes and errors.

Recovery sequence (TR-04) — follow this EXACT order:
1. IMMEDIATE ACTION: Tell them what to do RIGHT NOW (remove from heat, add water, etc.)
2. ACKNOWLEDGMENT: Brief, calm acknowledgment ("That happens to everyone")
3. HONEST ASSESSMENT: Is it recoverable? Be honest but not dramatic
4. CONCRETE PATH FORWARD: Specific next steps to save the dish or adapt

Tone rules:
- Never blame or shame
- Calm urgency for the immediate action, then warm reassurance
- If truly unrecoverable, suggest a creative pivot (e.g., "burnt garlic butter actually makes a great base for...")
- Always end with a positive path forward

Example response structure:
"Quick — take the pan off the heat right now and toss in a splash of water.
It happens! The garlic got a bit too dark.
It's not ideal, but we can work with this — the edges are dark but the centers look okay.
Let's pick out the darkest pieces, add fresh oil, and continue. The slight bitterness will actually add depth to the final dish."

Keep it SHORT — this is an emergency, not a lecture.""",
    tools=[],
)
```

**Endpoint:** `POST /v1/sessions/{session_id}/recover`

```python
@router.post("/sessions/{session_id}/recover")
async def recover(
    session_id: str,
    error_description: str,
    user: dict = Depends(get_current_user),
):
    session_doc = await db.collection("sessions").document(session_id).get()
    if not session_doc.exists:
        raise HTTPException(404)
    session = session_doc.to_dict()
    if session["uid"] != user["uid"]:
        raise HTTPException(403)

    recipe_doc = await db.collection("recipes").document(session["recipe_id"]).get()
    recipe = recipe_doc.to_dict()
    step_num = session.get("current_step", 1)
    current_step = recipe["steps"][step_num - 1] if step_num <= len(recipe["steps"]) else recipe["steps"][-1]

    response = await gemini_client.aio.models.generate_content(
        model=MODEL_FLASH,
        contents=f"""COOKING ERROR RECOVERY

Recipe: {recipe['title']}
Current step {step_num}: {current_step['instruction']}
Error reported: "{error_description}"

Follow recovery sequence:
1. IMMEDIATE ACTION (what to do RIGHT NOW)
2. ACKNOWLEDGMENT (brief, calm)
3. HONEST ASSESSMENT (recoverable?)
4. CONCRETE PATH FORWARD (specific next steps)

Be calm, brief, and constructive.""",
    )

    # Update calibration — error means expand guidance for this technique
    techniques = current_step.get("technique_tags", [])

    result = {
        "type": "recovery",
        "message": response.text,
        "step": step_num,
        "techniques_affected": techniques,
    }

    await log_session_event(session_id, "error_recovery", {
        "error": error_description,
        "recovery": response.text,
        "step": step_num,
    })

    return result
```

**Acceptance Criteria:**
- [ ] Follows 4-step recovery sequence exactly
- [ ] Immediate action comes first (time-critical)
- [ ] Tone is calm and constructive, never blaming
- [ ] Honest about recoverability
- [ ] Triggers calibration expansion for affected technique
- [ ] Event logged for post-session analysis

---

### 6.9 Register Vision/Taste/Recovery Routes

**What:** Add these endpoints to the sessions router.

```python
# In app/routers/sessions.py — add vision-check, visual-guide, taste-check, recover endpoints
```

**Acceptance Criteria:**
- [ ] All 4 endpoints accessible under `/v1/sessions/{id}/...`
- [ ] All require auth
- [ ] Vision check and visual guide also routable via WebSocket

---

### 6.10 Mobile UX Implementation (Vision + Guide + Recovery)

**What:** Implement mobile-first UX patterns for high-cognitive-load cooking moments.

**Required mobile UX components:**
1. Vision check capture UX:
   - Single-tap capture while in live session
   - Visual confirmation that frame was sent
   - Inline confidence badge (`High`, `Medium`, `Low`, `Fallback`)
2. Guide image comparison UX:
   - Side-by-side or swipe compare (`Your frame` vs `Target state`)
   - Cue overlays pinned directly on guide image
   - Quick actions: `Looks right`, `Show another stage`, `Explain cues`
3. Recovery UX:
   - Emergency-style compact card with `Do this now` at top
   - Followed by short rationale and next-step options
4. Accessibility and readability:
   - High-contrast overlays for kitchen lighting glare
   - Minimum 16px body text and large action controls

**Acceptance Criteria:**
- [ ] Vision results are understandable within 2 seconds of display
- [ ] Side-by-side guide comparison usable without leaving live session
- [ ] Recovery responses always surface immediate action first in UI hierarchy
- [ ] At least one on-device test validates readability in bright kitchen lighting

---

## Demo Scenario (Aglio e Olio)

**Vision check moment:** Step 4 (garlic sauté). User asks "does this look right?" or taps vision check.
- If garlic is light golden → High confidence: "Looking perfect! Light golden edges, exactly where you want it."
- If unclear → Medium: "Looks like it's getting there, but I can't quite tell from this angle. Does it smell nutty but not bitter?"

**Guide image moment:** Step 4 or Step 6. User requests visual guide.
- Shows AI-generated image of target state (light golden garlic / emulsified sauce)
- Cue overlays: "Edges are light golden", "Oil sheen visible"
- Side-by-side with user's camera frame

**Taste check moment:** Step 6 (after combining pasta with sauce).
- Prompted: "Good time to taste! How's the balance?"
- User: "It needs something" → 3-question diagnostic

**Recovery moment:** Step 4 — garlic gets too dark.
- "Take the pan off heat NOW. Add a splash of pasta water to stop cooking."
- "Happens to the best of us. Garlic goes from golden to burnt fast."
- "It's a bit darker than ideal, but still usable."
- "Pick out the darkest pieces. The slight bitterness will actually complement the chili."

## Epic Completion Checklist

- [ ] Vision check with 4-tier confidence hierarchy
- [ ] Sensory fallback for low/failed confidence
- [ ] Guide image generation with session-consistent style
- [ ] Side-by-side display (user frame + guide image + cue overlays)
- [ ] Guide images persisted in GCS and Firestore
- [ ] Taste diagnostic with 5 dimensions and stage awareness
- [ ] "Something's missing" 3-question flow
- [ ] Error recovery following 4-step sequence
- [ ] Calibration expansion triggered by errors
- [ ] Mobile UX for vision/guide/recovery verified on device
- [ ] All endpoints functional and demo-ready
