# Epic 7: Post-Session, Observability & Demo Hardening

## Goal

Clean session wind-down with memory persistence, structured observability, submission-ready artifacts, and a reliable end-to-end demo that hits all 6 hackathon success criteria plus judging-alignment targets.

## Prerequisites

- All previous epics (1-6) substantially complete
- Demo recipe seeded and functional through full flow
- Epic 8 critical UX paths complete and validated on real devices
- Epic 9 zero-setup path complete if included in final demo narrative

## PRD References

- §7.9 Post-Session (PS-01 through PS-04)
- §13 UX Requirements for Demo (all 14 points, including UX-13 barge-in and UX-14 "Why this recipe?")
- §14 Observability and Success Metrics
- §14.3 Hackathon Success Criteria
- §14.4 Judging Criteria Alignment (weighted scorecard)
- §15 Security, Privacy, and Trust
- §21 Devpost Submission Checklist
- NFR-07 Judging-ready demo behavior
- NFR-08 Submission compliance

---

## Tasks

### 7.1 Session Completion Flow

**What:** End the cooking session with a completion beat, brief verbal send-off, and transition to wind-down.

**Endpoint:** `POST /v1/sessions/{session_id}/complete`

```python
@router.post("/sessions/{session_id}/complete")
async def complete_session(
    session_id: str,
    user: dict = Depends(get_current_user),
):
    session_doc = await db.collection("sessions").document(session_id).get()
    if not session_doc.exists:
        raise HTTPException(404)
    session = session_doc.to_dict()
    if session["uid"] != user["uid"]:
        raise HTTPException(403)
    if session["status"] != "active":
        raise HTTPException(400, "Session is not active")

    recipe_doc = await db.collection("recipes").document(session["recipe_id"]).get()
    recipe = recipe_doc.to_dict()

    # PS-01: Completion beat with intentional pause
    completion_message = await generate_completion_message(recipe["title"])

    # Update session status
    await db.collection("sessions").document(session_id).update({
        "status": "completed",
        "ended_at": firestore.SERVER_TIMESTAMP,
    })

    # Clean up guide image generators
    if session_id in _guide_generators:
        del _guide_generators[session_id]

    return {
        "type": "session_complete",
        "message": completion_message,
        "wind_down": {
            "max_interactions": 3,
            "options": [
                {"id": "difficulty", "prompt": "How did that feel?", "type": "emoji_scale"},
                {"id": "memory", "prompt": "Anything I should remember for next time?", "type": "memory_confirm"},
                {"id": "photo", "prompt": "Want to snap a photo of your creation?", "type": "photo_capture"},
            ],
        },
    }

async def generate_completion_message(recipe_title: str) -> str:
    response = await gemini_client.aio.models.generate_content(
        model=MODEL_FLASH,
        contents=f"""Generate a warm, brief completion message for finishing cooking "{recipe_title}".
One short sentence of congratulations + one sentence about enjoying the meal.
Be warm but not over-the-top. Max 2 sentences total.""",
    )
    return response.text
```

**Acceptance Criteria:**
- [ ] Session status set to `completed` with `ended_at`
- [ ] Warm completion message generated
- [ ] Max 3 wind-down interaction options returned
- [ ] Timer system cleaned up
- [ ] Guide generator cleaned up

---

### 7.2 Wind-Down Interactions

**What:** Handle the 1-3 optional post-session interactions: difficulty rating, memory confirmation, and optional photo.

**Implementation:**

```python
@router.post("/sessions/{session_id}/wind-down/{interaction_id}")
async def wind_down_interaction(
    session_id: str,
    interaction_id: str,
    payload: dict,
    user: dict = Depends(get_current_user),
):
    session_doc = await db.collection("sessions").document(session_id).get()
    if not session_doc.exists:
        raise HTTPException(404)
    session = session_doc.to_dict()
    if session["uid"] != user["uid"]:
        raise HTTPException(403)

    if interaction_id == "difficulty":
        # PS-02: Difficulty emoji rating
        emoji = payload.get("rating")  # e.g., "😊", "😅", "🔥"
        await log_session_event(session_id, "difficulty_rating", {"rating": emoji})
        return {"message": "Got it! Thanks for the feedback."}

    elif interaction_id == "memory":
        # PS-03: Memory confirmation gate
        observations = payload.get("observations", [])
        confirmed = payload.get("confirmed", False)

        if confirmed and observations:
            # Only persist memories that user explicitly confirms
            for obs in observations:
                memory_id = str(uuid.uuid4())
                await db.collection("users").document(user["uid"]) \
                    .collection("memories").document(memory_id).set({
                        "observation": obs,
                        "confirmed": True,
                        "confidence": 1.0,
                        "source_session_id": session_id,
                        "created_at": firestore.SERVER_TIMESTAMP,
                    })
            return {"message": f"I'll remember {len(observations)} thing(s) for next time!"}
        return {"message": "No worries, we'll figure it out together next time."}

    elif interaction_id == "photo":
        # Optional photo capture — just acknowledge
        return {"message": "Nice! Enjoy your meal."}

    raise HTTPException(400, f"Unknown interaction: {interaction_id}")
```

**Memory examples the system might propose for confirmation:**
- "You prefer garlic on the lighter side of golden"
- "You like extra chili flakes"
- "The saute technique clicked — we can go faster next time"
- "You needed help with emulsifying — we'll cover that more next time"

**Acceptance Criteria:**
- [ ] Max 3 wind-down interactions (PS-02)
- [ ] Difficulty emoji rating captured
- [ ] Memory confirmation gate — memories ONLY persisted after explicit user consent (PS-03)
- [ ] Memories stored in `users/{uid}/memories/{memory_id}`
- [ ] Each interaction is short and fast
- [ ] Session can end without any wind-down (skip all)

---

### 7.3 Deferred Wind-Down Notification

**What:** If user leaves before completing wind-down, offer a gentle follow-up later.

**Implementation:**

```python
# PS-04: Deferred wind-down
# In a production system, this would be a Cloud Task or push notification.
# For hackathon, use in-app fallback.

async def schedule_deferred_winddown(session_id: str, uid: str):
    """Schedule a follow-up for incomplete wind-down."""
    await db.collection("users").document(uid).collection("notifications").add({
        "type": "deferred_wind_down",
        "session_id": session_id,
        "message": "How was your cooking session? Tap to share quick feedback.",
        "created_at": firestore.SERVER_TIMESTAMP,
        "read": False,
    })
```

**Acceptance Criteria:**
- [ ] Deferred notification stored for users who skip wind-down
- [ ] In-app fallback (notification document in Firestore)
- [ ] Non-intrusive — single follow-up, not repeated

---

### 7.4 Structured Logging

**What:** Add structured JSON logging across all Cloud Run endpoints for debugging and observability.

**Implementation:**

```python
import logging
import json
from datetime import datetime

class StructuredFormatter(logging.Formatter):
    def format(self, record):
        log_entry = {
            "severity": record.levelname,
            "message": record.getMessage(),
            "timestamp": datetime.utcnow().isoformat(),
            "component": record.name,
        }
        if hasattr(record, "session_id"):
            log_entry["session_id"] = record.session_id
        if hasattr(record, "endpoint"):
            log_entry["endpoint"] = record.endpoint
        if hasattr(record, "latency_ms"):
            log_entry["latency_ms"] = record.latency_ms
        return json.dumps(log_entry)

# Configure at app startup
handler = logging.StreamHandler()
handler.setFormatter(StructuredFormatter())
logging.root.handlers = [handler]
logging.root.setLevel(logging.INFO)
logger = logging.getLogger("ratatouille")
```

**Add request timing middleware:**

```python
from fastapi import Request
import time

@app.middleware("http")
async def log_request(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    latency_ms = (time.time() - start) * 1000

    logger.info(
        f"{request.method} {request.url.path} {response.status_code}",
        extra={
            "endpoint": request.url.path,
            "latency_ms": round(latency_ms, 2),
        },
    )
    return response
```

**Acceptance Criteria:**
- [ ] All requests logged with method, path, status, latency
- [ ] Session ID included where available
- [ ] JSON format compatible with Cloud Logging
- [ ] No sensitive data logged (no tokens, no user audio)

---

### 7.5 Technical Metrics Instrumentation

**What:** Track the key latency and reliability metrics defined in PRD §14.2.

**Metrics to track:**

| Metric | Target | How |
|--------|--------|-----|
| Voice response latency (p50/p95) | <= 1.8s p95 | Timer from WS receive to WS send |
| Vision assessment latency (p50/p95) | <= 3.5s p95 | Timer from frame upload to response |
| Guide image generation latency (p50/p95) | N/A (best effort) | Timer from request to image URL return |
| Scan-to-suggestions latency (p50/p95) | <= 6.0s p95 | Timer from scan detect to suggestions |
| Process bar update latency | <= 500ms | Timer from state change to WS push |
| WebSocket disconnect rate | Low | Count disconnects / total sessions |
| Cloud Run error rate | Low | HTTP 5xx responses / total |

**Implementation:**

```python
from collections import defaultdict
import statistics
from datetime import datetime
from fastapi import Depends, HTTPException
from app.auth.firebase import require_admin
from app.config import settings
from app.services.firestore import db
from google.cloud import firestore

class MetricsCollector:
    """Hybrid metrics collector: in-memory for quick local summaries + Firestore for multi-instance durability."""

    def __init__(self):
        self.latencies: dict[str, list[float]] = defaultdict(list)
        self.counters: dict[str, int] = defaultdict(int)

    async def record_latency(self, metric_name: str, latency_ms: float):
        self.latencies[metric_name].append(latency_ms)
        # Multi-instance durable write (minute bucket)
        minute_bucket = datetime.utcnow().strftime("%Y%m%d%H%M")
        await db.collection("metrics_minute").document(f"{metric_name}:{minute_bucket}").set(
            {
                "metric_name": metric_name,
                "minute_bucket": minute_bucket,
                "count": firestore.Increment(1),
                "sum_ms": firestore.Increment(float(latency_ms)),
                "max_ms": float(latency_ms),  # best-effort max for hackathon
                "updated_at": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )

    async def increment(self, counter_name: str):
        self.counters[counter_name] += 1
        await db.collection("metrics_counters").document(counter_name).set(
            {
                "name": counter_name,
                "count": firestore.Increment(1),
                "updated_at": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )

    def get_summary(self) -> dict:
        summary = {}
        for name, values in self.latencies.items():
            if values:
                sorted_vals = sorted(values)
                summary[name] = {
                    "count": len(values),
                    "p50": round(sorted_vals[len(sorted_vals) // 2], 2),
                    "p95": round(sorted_vals[int(len(sorted_vals) * 0.95)], 2) if len(sorted_vals) >= 20 else round(max(sorted_vals), 2),
                    "mean": round(statistics.mean(values), 2),
                }
        summary["counters"] = dict(self.counters)
        return summary

metrics = MetricsCollector()

# Expose metrics endpoint (admin only, never public)
@app.get("/internal/metrics", dependencies=[Depends(require_admin)])
async def get_metrics():
    # Defense-in-depth: keep endpoint disabled in production unless explicitly enabled.
    if settings.environment == "production" and not getattr(settings, "enable_internal_metrics", False):
        raise HTTPException(404, "Not found")
    return metrics.get_summary()
```

**Usage pattern:**
```python
start = time.time()
result = await assess_food_image(...)
await metrics.record_latency("vision_assessment_ms", (time.time() - start) * 1000)
```

**Acceptance Criteria:**
- [ ] All key latencies tracked (voice, vision, scan, guide image, process bar)
- [ ] p50/p95 computable from collected data
- [ ] Metrics endpoint accessible at `/internal/metrics` for admins only
- [ ] Firestore-backed metric writes support multi-instance Cloud Run execution
- [ ] Error counts tracked
- [ ] WebSocket disconnect count tracked

---

### 7.6 Product Metrics Events

**What:** Emit product analytics events for the metrics defined in PRD §14.1.

**Events to emit:**

```python
# Event types and when they fire:
PRODUCT_EVENTS = {
    "scan_started": "User initiates fridge/pantry scan",
    "scan_completed": "Ingredients detected from scan",
    "scan_confirmed": "User confirms ingredient list",
    "suggestions_viewed": "Dual-lane suggestions displayed",
    "suggestion_selected": "User picks a recipe suggestion",
    "session_started": "Cooking session activated",
    "session_completed": "Session reaches completion",
    "session_abandoned": "Session abandoned mid-cook",
    "vision_check": "User performs vision check",
    "guide_image_requested": "User requests visual guide",
    "guide_image_feedback": "User gives thumbs up/down on guide",
    "taste_check": "Taste diagnostic performed",
    "error_recovery": "Error recovery triggered",
    "user_override": "User says 'I know' or skips",
    "memory_confirmed": "User confirms preference memory",
    "memory_rejected": "User rejects preference memory",
}
```

**Implementation:**

```python
async def emit_product_event(event_type: str, uid: str, metadata: dict = None):
    """Emit a product analytics event."""
    event = {
        "event_type": event_type,
        "uid": uid,
        "timestamp": firestore.SERVER_TIMESTAMP,
        "metadata": metadata or {},
    }

    # Store in Firestore for now (BigQuery sink is optional stretch)
    await db.collection("analytics_events").add(event)
    await metrics.increment(f"event_{event_type}")
```

**Acceptance Criteria:**
- [ ] All listed product events emitted at correct trigger points
- [ ] Events include uid and timestamp
- [ ] Metadata includes relevant context (suggestion source type, confidence tier, etc.)
- [ ] Counts visible in metrics endpoint

---

### 7.7 Graceful Degradation Hardening

**What:** Verify and harden all fallback paths so the demo doesn't break on partial failures.

**Degradation scenarios to test and harden:**

| Failure | Fallback | Verification |
|---------|----------|--------------|
| Vision model returns error | Sensory fallback language | Test with invalid image |
| Guide image generation fails | Text-only description of target state | Test with blocked model |
| Audio stream drops | Text-only responses via WebSocket | Test with no audio |
| Gemini rate limit | Queue and retry with backoff | Test with burst requests |
| Firestore write fails | Log error, continue session in memory | Test with invalid doc |
| GCS upload fails | Continue without persisted artifacts | Test with bad credentials |

**Implementation — add retry wrapper:**

```python
import asyncio

async def with_retry(coro_func, max_retries=2, backoff_base=1.0):
    """Retry an async function with exponential backoff."""
    for attempt in range(max_retries + 1):
        try:
            return await coro_func()
        except Exception as e:
            if attempt == max_retries:
                logger.error(f"Failed after {max_retries + 1} attempts: {e}")
                raise
            wait = backoff_base * (2 ** attempt)
            logger.warning(f"Attempt {attempt + 1} failed, retrying in {wait}s: {e}")
            await asyncio.sleep(wait)
```

**Acceptance Criteria:**
- [ ] Every external call (Gemini, Firestore, GCS) has a fallback path
- [ ] No unhandled exceptions crash the session
- [ ] Degradation clearly communicated to user
- [ ] Session continues functioning in degraded mode
- [ ] Retry wrapper used for transient failures

---

### 7.8 Privacy Controls Verification

**What:** Verify all privacy constraints are visible in UX and enforced in backend.

**Checklist:**

- [ ] Ambient mode requires explicit opt-in (toggle in session creation)
- [ ] Ambient mode has visible indicator pushed to client
- [ ] No ambient raw audio/video persisted
- [ ] Only user-triggered artifacts stored (confirmed photos, confirmed memories)
- [ ] Firebase Auth verified on every endpoint
- [ ] Memory confirmation gate blocks automatic preference persistence
- [ ] No PII in logs (tokens, audio, personal data)

---

### 7.9 Demo Script & Recipe Validation

**What:** Create a scripted demo that exercises all 6 hackathon success criteria, all 14 UX requirements, and aligns with the §14.4 judging scorecard. Include a short zero-setup proof beat if Epic 9 is in scope. Demo video must stay under 4 minutes (NFR-08).

**Demo Script:**

```markdown
## Demo Flow (Ratatouille — Aglio e Olio) — Target: 3:30-3:50

### Act 0: Zero-Setup Proof (0:20-0:30, optional but recommended)
1. Open app → tap `Cook Now (Seasoned Chef Buddy)` with no saved recipe selection.
2. Say: "I want something quick with eggs."
3. Buddy gives immediate first action + timer suggestion.
4. Exit and continue main scripted flow below.

### Act 1: Entry & Scan (1:00-1:15)
1. Open app → Home screen with "Cook from Fridge or Pantry" [UX-1]
2. Tap "Scan Fridge" → Take 2-3 photos [UX-2]
3. Detected ingredients appear as chips → Edit one (remove/add) [UX-3]
4. Confirm ingredients → Dual-lane suggestions appear [UX-4]
   - "From Saved": Demo Aglio e Olio (95% match)
   - "Buddy Recipes": 2-3 AI suggestions
5. **Tap "Why this recipe?" on Aglio e Olio card** → Grounded explanation expands [UX-14, NFR-07]
   - "You have 7 of 8 ingredients (spaghetti, garlic, olive oil...). Only missing parmesan."
   - Shows grounding sources and low-confidence warnings if any
6. Select Aglio e Olio → Session setup [Success Criteria 2]

### Act 2: Session Setup (0:20-0:30)
7. Ingredient checklist — confirm all available [UX-6]
8. Choose phone setup: "Counter (leaning)" [UX-5]
9. Toggle ambient listen ON → Indicator appears [UX-7]
10. Tap "Start Cooking" [Success Criteria 6 — privacy visible]

### Act 3: Live Cooking (1:30-2:00)
11. Buddy greets: "Let's make Aglio e Olio!" (note: warm persona, not robotic)
12. Step 1: "Bring water to boil" — Timer starts (8 min) [UX-8]
13. Step 2: "Slice garlic while water heats" — Parallel process shown
14. Buddy is explaining slicing technique and **USER INTERRUPTS mid-sentence**:
    "Wait — how much oil should I use?" [UX-13, NFR-07]
    - Buddy stops immediately: "Sure — about 80ml, or roughly 5-6 tablespoons."
    - User: "Go on" → Buddy gives concise summary of interrupted slicing guidance
    - (This demonstrates natural barge-in handling for Live Agents judging)
15. Step 3: Pasta in water — Timer starts (9 min)
16. Step 4: Garlic in oil — Timer starts (4 min)
    - **P1 Conflict**: Pasta and garlic timers converge [UX-9]
    - User chooses garlic first (more irreversible)
17. Voice: "Does this look right?" → Vision check [UX-10, Success Criteria 3]
    - High confidence: "That's a gorgeous golden — pull it off now!"
    - OR Medium: "Looking good from here, but give it a smell — nutty means done, bitter means too far."
18. "Show me what it should look like" → Guide image generated [UX-11, Success Criteria 5]
    - Side-by-side: user frame + target state
    - Cue: "Edges are light golden"
19. **Error recovery demo**: "I think the garlic got too dark"
    - "Off the heat — now." → Recovery sequence [Success Criteria 4]

### Act 4: Taste & Completion (0:40-0:50)
20. Step 6: Combine pasta + sauce
    - Prompted taste check: "This is the moment — give it a taste."
    - User: "It needs something" → Diagnostic flow [Success Criteria 4]
21. Step 7: Plate → Completion beat [UX-12]
    - "That looks fantastic. Enjoy every bite."
    - Difficulty emoji: 😊
    - Memory confirmation: "Remember: you like garlic on the lighter side" [Success Criteria 1]

### Success Criteria Verification
✅ 1. Full session without backend intervention
✅ 2. Fridge scan → ingredient detection → dual-lane suggestions
✅ 3. Multimodal: voice + vision + UI state in real time
✅ 4. Error recovery + taste diagnostic demonstrated
✅ 5. Generated visual guide shown in-session
✅ 6. Privacy: ambient indicator + consent visible

### Judging Criteria Alignment (§14.4)
✅ Innovation/UX (40%): Multimodal loop (scan→voice→vision→guide image), distinct persona, barge-in
✅ Technical (30%): Cloud Run + Firestore + Vertex AI, grounded explanations, confidence-aware fallbacks
✅ Demo/Presentation (30%): Tight 3:45 arc, every moment purposeful, no dead air
```

**Acceptance Criteria:**
- [ ] Demo script covers all 6 success criteria (§14.3)
- [ ] Demo script covers all 14 UX requirements (§13), including UX-13 (barge-in) and UX-14 ("Why this recipe?")
- [ ] Zero-setup proof segment included or explicitly documented as deferred
- [ ] Demo runtime fits within 3:50 (leaving 10s margin under 4:00 cap)
- [ ] Barge-in moment is natural and clearly demonstrates interruption handling (NFR-07)
- [ ] "Why this recipe?" explanation is grounded in confirmed ingredients (NFR-07)
- [ ] Buddy persona is consistent throughout — warm friend, never generic assistant
- [ ] Demo recipe pre-loaded in Firestore and GCS
- [ ] Scripted checkpoints identified for each critical moment
- [ ] Fallback talking points if something fails during demo

---

### 7.10 Submission Artifacts (§21 Devpost Checklist)

**What:** Produce all required submission assets per PRD §21 and NFR-08.

**Artifacts:**

1. **Demo video (< 4 minutes)**
   - Record final demo following Act 1-4 script above
   - Must show real working software, not mockups
   - Must include: scan, suggestions with "Why this recipe?", live voice interaction, barge-in, guide image, recovery moment
   - Target runtime: 3:30-3:50

2. **Architecture diagram**
   - Must match implemented system — no speculative boxes (NFR-08)
   - Show: Mobile → Cloud Run → Vertex AI / Firestore / GCS flow
   - Highlight agent orchestration (ADK agents and their roles)
   - Highlight multimodal data flow (voice in/out, vision in, guide image out)
   - Format: PNG/SVG suitable for Devpost upload

3. **Cloud deployment proof**
   - Separate short recording or screenshot showing live Cloud Run service URL
   - Or code evidence (deployment logs, `gcloud run services describe` output)

4. **Public repository README**
   - Reproducible setup instructions (from zero to running)
   - Required environment variables listed
   - `gcloud` commands for GCP setup
   - Docker build and deploy commands
   - Architecture diagram embedded
   - Clear explanation of what is novel and why it matters

**Devpost Submission Checklist (§21):**
- [ ] Category: `Live Agents` selected
- [ ] Demo video uploaded, runtime verified < 4:00
- [ ] Demo shows: scan, suggestions, live cooking, barge-in, guide image
- [ ] Public repo link works, README has setup/deploy instructions
- [ ] Architecture diagram attached, consistent with implementation
- [ ] Cloud deployment proof included
- [ ] Project description states novelty and judging-criteria alignment

**Acceptance Criteria:**
- [ ] All 7 checklist items from §21 satisfied
- [ ] Demo video runtime < 4:00
- [ ] Architecture diagram is accurate (no unimplemented boxes)
- [ ] README is tested by someone who hasn't seen the code before
- [ ] Cloud deployment proof artifact produced

---

### 7.11 Production Readiness

**What:** Final deployment hardening for demo stability.

**Tasks:**

1. **Cloud Run min-instances=1** — Eliminate cold starts during demo:
```bash
gcloud run services update ratatouille-api --min-instances=1 --region=us-central1
```

2. **Pre-warm models** — Make a throwaway Gemini call at startup to warm connections:
```python
@app.on_event("startup")
async def warmup():
    try:
        await gemini_client.aio.models.generate_content(
            model=MODEL_FLASH, contents="Hello"
        )
        logger.info("Gemini client warmed up")
    except Exception as e:
        logger.warning(f"Warmup call failed (non-critical): {e}")
```

3. **Pre-load demo assets** — Ensure demo recipe reference images are in GCS.

4. **Health check enhanced:**
```python
@app.get("/health")
async def health():
    checks = {}
    try:
        # Firestore connectivity
        test = await db.collection("_health").document("check").get()
        checks["firestore"] = "ok"
    except Exception:
        checks["firestore"] = "error"

    try:
        # GCS connectivity
        bucket.blob("_health/check.txt").exists()
        checks["gcs"] = "ok"
    except Exception:
        checks["gcs"] = "error"

    status = "ok" if all(v == "ok" for v in checks.values()) else "degraded"
    return {"status": status, "checks": checks}
```

5. **Deploy final build:**
```bash
gcloud builds submit --config=cloudbuild.yaml ./backend
```

**Acceptance Criteria:**
- [ ] Cloud Run min-instances=1 set
- [ ] Gemini pre-warmed on startup
- [ ] Demo recipe and assets pre-loaded
- [ ] Health check validates Firestore + GCS connectivity
- [ ] Final deployment successful and stable
- [ ] Full demo flow runs without errors

---

### 7.12 Mobile UX QA and Hardening

**What:** Validate end-to-end mobile UX quality on real devices before submission.

**Scope:**
1. Test matrix:
   - At least 1 iOS device
   - At least 1 Android device
2. Critical UX flows:
   - Scan capture/edit/suggestions
   - Start-session handoff + activation
   - Live session with barge-in
   - Vision check + guide image side-by-side
   - Recovery card and post-session interactions
3. UX quality gates:
   - No dead-end UI states
   - All long operations show progress/skeletons
   - Error states provide explicit recovery action
   - Core controls reachable one-handed

**Acceptance Criteria:**
- [ ] Full demo script passes on both iOS and Android
- [ ] No blocking UI regressions in critical path flows
- [ ] Top 5 UX defects fixed or explicitly documented with workaround
- [ ] Video recording reflects real mobile UX (not desktop simulation)

---

## Epic Completion Checklist

- [ ] Session completion with warm send-off
- [ ] Wind-down flow (max 3 interactions)
- [ ] Memory confirmation gate enforced
- [ ] Deferred wind-down notification
- [ ] Structured logging across all endpoints
- [ ] Technical metrics (latency, errors, disconnects)
- [ ] Product analytics events emitted
- [ ] Graceful degradation hardened
- [ ] Privacy controls verified
- [ ] Demo script validated end-to-end (all 14 UX points, including barge-in + "Why this recipe?")
- [ ] Mobile UX QA complete on iOS + Android
- [ ] Submission artifacts complete (video, architecture diagram, cloud proof, README)
- [ ] Demo video under 4 minutes
- [ ] Production deployment stable with min-instances=1

---

## Hackathon Success Criteria (Final Verification)

| # | Criterion | Epic(s) | Status |
|---|-----------|---------|--------|
| 1 | Full session without backend intervention | All | [ ] |
| 2 | Scan → detection → dual-lane suggestions | Epic 3 | [ ] |
| 3 | Multimodal interactions in real time | Epic 4, 5 | [ ] |
| 4 | Error recovery + taste diagnostic | Epic 6 | [ ] |
| 5 | Generated visual guide in-session | Epic 6 | [ ] |
| 6 | Privacy constraints visible in UX | Epic 4, 7 | [ ] |

## Judging-Alignment Targets (§14.4 + NFR-07)

| Target | Evidence | Epic(s) | Status |
|--------|----------|---------|--------|
| Barge-in interruption handled naturally | Demo Act 3, step 14 | Epic 4 | [ ] |
| Distinct buddy persona, never breaks character | All buddy outputs | Epic 4 | [ ] |
| Grounded "Why this recipe?" explanation | Demo Act 1, step 5 | Epic 3 | [ ] |
| Confidence-aware language (no false certainty) | Vision + scan flows | Epic 3, 6 | [ ] |
| Demo under 4 minutes with tight story arc | Submission video | Epic 7 | [ ] |
| Architecture diagram matches implementation | Submission artifact | Epic 7 | [ ] |
| Deployed and reproducible from public repo | README + cloud proof | Epic 7 | [ ] |

## Devpost Submission Checklist (§21)

- [ ] Category: `Live Agents`
- [ ] Demo video < 4:00 showing scan, suggestions, live cooking, barge-in, guide image
- [ ] Public repo with reproducible setup/deploy instructions
- [ ] Architecture diagram consistent with implementation
- [ ] Cloud deployment proof artifact
- [ ] Project description states novelty and judging alignment
