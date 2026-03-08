# Epic 9: Zero-Setup "Seasoned Chef Buddy" Mode

## Goal

Let users launch directly into a live cooking session with no saved recipe and no mandatory setup. A first-time user should be able to open Ratatouille, tap `Cook Now`, and get practical, stepwise coaching from the buddy in under 30 seconds.

## Prerequisites

- Epic 1 complete (auth, backend scaffold, deployment)
- Epic 4 complete (session lifecycle + WebSocket live loop)
- Epic 8 baseline complete (mobile shell, auth, resilient WS client)

## Completed-Epic Change Capture Rule

Epics 1-6 are already completed. Any required changes to those delivered artifacts must be executed under Epic 9 tasks (not by reopening or editing the old epic plans).

Changes owned by Epic 9:
- Epic 4 artifact updates: session create/activate/live contracts to support `freestyle` mode (Tasks 9.2, 9.3, 9.4)
- Epic 5 artifact updates: dynamic process/timer initialization for no-recipe sessions (Task 9.6)
- Epic 6 artifact updates (if needed): reuse vision/taste/recovery endpoints in freestyle mode without recipe-bound assumptions (Tasks 9.5, 9.8)
- Epic 3 + Epic 4 artifact updates: fridge/pantry live browse video chat path for in-session ingredient discovery (Task 9.11)

## PRD References

- §7.1 Session lifecycle
- §7.2 Multimodal inputs (voice + optional camera)
- §7.3 Multimodal outputs (voice/text + visual guidance)
- §7.4 Voice modes and barge-in behavior
- §7.10 Fridge/Pantry flow
- §7.6 Calibration/adaptation behavior
- §13 UX requirements for demo (fast entry, interruption handling)
- §14.4 judging criteria (innovation + product UX quality)
- NFR-01/NFR-02/NFR-07

## Tech Guide References

- §1 Vertex AI (Gemini Live + Flash)
- §2 ADK agent orchestration and state
- §10 Cloud Run WebSocket behavior

---

## Data Model Deltas

### Session model extension (`app/models/session.py`)

```python
from pydantic import BaseModel
from typing import Optional

class FreestyleContext(BaseModel):
    dish_goal: Optional[str] = None              # e.g., "quick dinner", "something spicy"
    available_ingredients: list[str] = []
    equipment: list[str] = []                    # e.g., ["pan", "oven"]
    time_budget_minutes: Optional[int] = None
    skill_self_rating: Optional[str] = None      # beginner | intermediate | advanced

class SessionCreate(BaseModel):
    session_mode: str = "recipe_guided"         # recipe_guided | freestyle
    recipe_id: Optional[str] = None
    mode_settings: Optional[ModeSettings] = None
    freestyle_context: Optional[FreestyleContext] = None
```

Validation rule:
- `session_mode == "recipe_guided"` requires `recipe_id`
- `session_mode == "freestyle"` does not require saved recipes

---

## Tasks

### 9.1 Zero-Setup Entry Point

**What:** Add a top-level app entry path that does not require scan, saved recipes, or onboarding data.

**Mobile UX deliverable:** Home screen has two primary CTAs:
- `Cook from Fridge or Pantry`
- `Cook Now (Seasoned Chef Buddy)`

**Acceptance Criteria:**
- [ ] User can enter freestyle mode in 1 tap from home
- [ ] No account content prerequisites (saved recipe/inventory) block entry
- [ ] Entry event logged for analytics (`zero_setup_entry_tapped`)

---

### 9.2 Unified Session Creation Contract (Recipe-Guided + Freestyle)

**What:** Patch completed Epic 4 session-create artifact so `POST /v1/sessions` supports both modes through one contract.

**Endpoint:** `POST /v1/sessions`

```python
@router.post("/sessions")
async def create_session(body: SessionCreate, user: dict = Depends(get_current_user)):
    if body.session_mode == "recipe_guided":
        if not body.recipe_id:
            raise HTTPException(422, "recipe_id required for recipe_guided mode")
        recipe_doc = await db.collection("recipes").document(body.recipe_id).get()
        if not recipe_doc.exists:
            raise HTTPException(404, "Recipe not found")

    return await create_session_record(
        uid=user["uid"],
        session_mode=body.session_mode,
        recipe_id=body.recipe_id,
        mode_settings=(body.mode_settings or ModeSettings()).model_dump(),
        freestyle_context=(body.freestyle_context.model_dump() if body.freestyle_context else {}),
    )
```

**Acceptance Criteria:**
- [ ] `recipe_guided` validation behavior preserved
- [ ] `freestyle` creation succeeds without `recipe_id`
- [ ] Session record persists `session_mode` and `freestyle_context`
- [ ] Existing scan/suggestion start-session flow remains backward compatible

---

### 9.3 Freestyle Activation Bootstrap

**What:** Patch completed Epic 4 session-activate artifact so `POST /v1/sessions/{id}/activate` works when no recipe is attached.

**Freestyle activation behavior:**
- Generate a short initial plan (2-4 concrete steps)
- Ask at most 1-2 clarification questions if needed
- Initialize process/timer state from inferred plan

**Acceptance Criteria:**
- [ ] Activation works when `recipe_id` is null and `session_mode == "freestyle"`
- [ ] Response includes an initial plan payload suitable for mobile rendering
- [ ] User hears/reads first actionable instruction immediately after activation

---

### 9.4 Freestyle Orchestrator Behavior

**What:** Patch completed Epic 4 live-loop/orchestrator behavior with a no-recipe coaching mode.

**Required behavior:**
- Maintain buddy persona and confident kitchen guidance tone
- Prefer concrete actions over long explanations
- Dynamically create/adjust steps as user reports progress
- Handle interruption (`barge_in`) identically to recipe-guided mode

**Acceptance Criteria:**
- [ ] Freestyle sessions can progress through multiple steps without recipe document lookup
- [ ] Barge-in and resume remain stable in freestyle mode
- [ ] Guidance remains stage-aware (prep, heat, doneness, seasoning)

---

### 9.5 In-Session Context Capture (Optional, Not Blocking)

**What:** Allow users to add context during freestyle session without leaving live mode.

**Supported inputs:**
- Voice: "I have eggs, spinach, and cheese"
- Quick chips: time budget, equipment, dietary constraints
- Optional camera check for doneness verification

**Acceptance Criteria:**
- [ ] Context updates can be applied mid-session with no restart
- [ ] Updated context changes subsequent guidance decisions
- [ ] Missing context never blocks continuation

---

### 9.6 Process/Timer Compatibility for Freestyle

**What:** Patch completed Epic 5 process manager so freestyle sessions can run with dynamically generated process entries.

**Acceptance Criteria:**
- [ ] Process bar shows inferred active processes in freestyle mode
- [ ] Timer alerts and conflict chooser continue to work
- [ ] State persists and resumes after reconnect

---

### 9.7 Mobile UX: Fast Start + Low Friction

**What:** Define mobile UX for zero-setup flow with minimal typing and no dead ends.

**Required flow:**
1. Home -> tap `Cook Now (Seasoned Chef Buddy)`
2. Optional quick context sheet (all fields skippable)
3. Enter live session immediately

**Acceptance Criteria:**
- [ ] User reaches live session in <= 2 taps from home (if skipping context)
- [ ] Quick context sheet has explicit `Skip for now`
- [ ] All loading/error states provide retry and back paths

---

### 9.8 Safety + Confidence Constraints in Freestyle

**What:** Ensure advice remains useful and safe even without structured recipe constraints.

**Rules:**
- If confidence is low, ask clarifying question instead of asserting certainty
- Prioritize irreversible-risk warnings (burning oil, overcooking, food safety)
- Keep advice grounded in user-provided context and observed state

**Acceptance Criteria:**
- [ ] Low-confidence states are explicit in response language
- [ ] High-risk moments trigger concise warning + immediate action
- [ ] No fabricated references to non-existent recipe steps

---

### 9.9 Metrics + Judging Alignment for Zero-Setup Path

**What:** Track whether zero-setup path improves activation and demo performance.

**Events/KPIs:**
- `zero_setup_entry_tapped`
- `zero_setup_session_created`
- `zero_setup_session_activated`
- `time_to_first_instruction_ms`
- `zero_setup_session_completed`

**Acceptance Criteria:**
- [ ] Metrics emitted for all zero-setup funnel steps
- [ ] Time-to-first-instruction measurable and reported in demo metrics
- [ ] Zero-setup path included in judging-alignment evidence pack

---

### 9.10 Demo Coverage

**What:** Add an alternate demo segment showing first-time-user immediate value.

**Demo beat (20-30s):**
- Open app -> `Cook Now`
- Say: "I want something quick with eggs"
- Buddy gives first actionable step and timer suggestion

**Acceptance Criteria:**
- [ ] Demo script includes at least one zero-setup segment
- [ ] Segment demonstrates no dependency on saved recipe data
- [ ] Segment still shows persona quality and interruption handling

---

### 9.11 Fridge/Pantry Live Browse Video Chat

**What:** Add a live video chat path where users can start in scan mode and let the agent browse fridge/pantry in real time during session setup or early live session.

**Ownership note:** This task patches completed Epic 3 scan artifacts and Epic 4 WebSocket live artifacts under Epic 9 governance.

**Required UX flow:**
1. User enters `Cook from Fridge or Pantry`.
2. User chooses `Live Browse with Buddy` (instead of only photo/video upload).
3. App opens live session camera + voice channel and streams frames/events.
4. Buddy narrates findings, asks concise clarification questions, and builds ingredient list progressively.
5. User can continue to:
   - Recipe suggestions flow, or
   - Immediate freestyle cooking guidance.

**Realtime contract additions (patch of existing WS contracts):**
- Client events:
  - `browse_start` (`source`: `fridge` | `pantry`)
  - `browse_frame` (`frame_uri` or encoded frame payload)
  - `browse_stop`
- Server events:
  - `browse_observation` (what the buddy sees + confidence)
  - `ingredient_candidates` (incremental detected list + confidence tiers)
  - `browse_question` (targeted clarification prompt)

**Acceptance Criteria:**
- [ ] User can start live browse from both fridge and pantry entry points
- [ ] Agent can process sequential frames and update ingredient candidates incrementally
- [ ] Buddy output is multimodal in real time (voice/text + ingredient list updates)
- [ ] User can convert browse results into either suggestions or freestyle session without re-entry
- [ ] Fallback exists when video quality is poor (ask for still capture or verbal confirmation)

---

## Epic Completion Checklist

- [ ] Zero-setup entry CTA available on home screen
- [ ] `POST /v1/sessions` supports `freestyle` mode without `recipe_id`
- [ ] Activation bootstrap works for freestyle sessions
- [ ] Live orchestrator supports freestyle coaching + barge-in
- [ ] In-session context capture works and remains optional
- [ ] Process/timer system functions in freestyle mode
- [ ] Mobile flow reaches live session with minimal friction
- [ ] Safety/confidence guardrails verified for no-recipe guidance
- [ ] Metrics captured for zero-setup funnel and latency
- [ ] Demo script includes zero-setup proof path
- [ ] Fridge/pantry live browse video chat works and transitions cleanly to suggestions or freestyle
