# Ratatouille Hackathon PRD

## 0. Document Meta

- Product: `Ratatouille` mobile app
- Focus: `Live Cooking Buddy` (voice-primary, vision-assisted, multimodal)
- PRD type: Hackathon MVP + implementation plan
- Date: March 8, 2026
- Inputs used: `product.md`, `GOOGLE_CLOUD_TECH_GUIDE.md`

---

## 1. Executive Summary

Ratatouille is a mobile cooking companion that watches what the user is doing and adapts guidance in real time. The hackathon goal is to ship a functional, demo-ready MVP of the live cooking companion using Google services, with multimodal input/output as the core differentiator.

Multimodal is explicitly bidirectional in this PRD:
- Input: voice + camera + touch + timing context
- Output: voice + text + UI states + AI-generated visual guide images for target food states

The MVP must prove this loop end-to-end:
1. User starts from a saved recipe or scans fridge/pantry to discover what to cook.
2. User interacts by voice and optional camera.
3. Buddy responds with adaptive spoken guidance plus contextual visual UI.
4. Buddy handles timing, parallel cooking processes, taste adjustments, and recoverable mistakes.
5. Session ends with a lightweight post-cook feedback/memory step.

---

## 2. Problem Statement

Most recipe apps are static instructions. Real cooking is dynamic, concurrent, and messy:
- Hands are busy or wet; screen interaction is inconvenient.
- Doneness and timing are visual/sensory, not text-only.
- Users have varying skill levels by technique, not a single global skill tier.
- Errors happen and need immediate, calm recovery guidance.

Ratatouille solves this by combining voice + vision + timing context into a live companion experience.

---

## 3. Product Vision and Positioning

- Vision: "The cooking companion that watches what you're doing and adjusts guidance to match."
- Hero experience: Pillar 3 `Live Cooking Buddy` (80% product investment).
- Persona: Experienced friend in the kitchen.
- Relationship promise: Session 1 introduces support; by Session 5, guidance is personalized and lighter.

---

## 4. Hackathon Goals and Non-Goals

### 4.1 Goals

1. Demonstrate multimodal live cooking companion on mobile with low-friction voice interaction.
2. Demonstrate multimodal output beyond text/voice by generating visual target-state guides (for example, saute/doneness consistency cards) during live cooking.
3. Implement a "Fridge or Pantry" scan entry flow that suggests what to cook from detected ingredients using:
   - User's saved recipes
   - Buddy-generated recipes
4. Implement the three voice modes:
   - Ambient Listen (opt-in, session-scoped)
   - Active Query
   - Vision Check
5. Implement adaptive guidance:
   - Onboarding calibration
   - Per-recipe guidance tuning
   - In-session recalibration signals
6. Support at least one realistic multi-process recipe session with timers and step prioritization.
7. Deliver a live demo with reliable cloud deployment and observability.

### 4.2 Non-Goals (Hackathon)

- Full grocery shopping extension (Phase 2).
- Full pantry inventory system.
- Social sharing or multi-user households.
- Advanced long-term personalization (Session 20+ depth).
- Full production-grade safety/compliance certification.

---

## 5. Users and Core Jobs-to-be-Done

### 5.1 Primary Persona

- Home cook using a phone at counter height.
- Comfortable following recipes but wants help with timing, doneness, and rescue moments.

### 5.2 Core Jobs

1. "Help me cook this dish without constantly touching my phone."
2. "Tell me if this looks right before I overcook it."
3. "Keep track of parallel tasks so I do not miss critical moments."
4. "Help me fix mistakes quickly."
5. "Learn how much help I need and adjust."

---

## 6. Scope (Hackathon MVP)

### 6.1 In Scope

- Pillar 1: Recipe collection (limited MVP)
  - Manual recipe entry + one URL parse path (best effort)
  - Technique tag extraction for coaching moments
  - Fridge or pantry scan to detect ingredients and suggest recipes
- Pillar 2: Ingredient checklist
  - "Have / Don't have" gate before session start
- Pillar 3: Live Cooking Buddy
  - 3 voice modes
  - Vision confidence hierarchy with graceful fallback
  - Active Process Bar + priority queue
  - Taste adjustment mini-flow
  - Error recovery sequence
  - Post-session 1-3 interaction wind-down

### 6.2 Out of Scope

- Grocery store navigation and integrations
- Cross-device sync hardening
- Comprehensive recipe ingestion reliability for all sources

---

## 7. Detailed Product Requirements

## 7.1 Session Lifecycle

1. Entry:
   - Select saved recipe, or
   - Scan fridge/pantry to discover recipe options
2. Pre-session:
   - Confirm detected ingredients (if scan path used)
   - Choose suggested recipe (saved recipe or buddy-generated recipe)
   - Confirm ingredients checklist
   - Choose phone setup mode
3. Live session:
   - Voice and/or camera interactions
   - Step-by-step adaptive guidance
   - Timer/process management
4. Post-session:
   - Completion beat
   - Optional quick feedback + memory confirmation

## 7.2 Multimodal Input Requirements

- `MI-01` Voice input:
  - Always available via Active Query
  - Ambient Listen requires explicit opt-in per session
- `MI-02` Vision input:
  - Triggered by explicit command ("look at this") or tap
  - Ambient vision monitors only food-state signals (color, smoke-like signals, boilover risk)
- `MI-03` Manual touch input:
  - Start/pause session
  - Confirm step completion
  - Select between competing priorities
- `MI-04` Context input:
  - Timer state
  - Current step and active process list
  - User calibration state
- `MI-05` Inventory scan input (fridge/pantry):
  - Capture 2-6 photos or short video clip
  - Detect visible ingredients with confidence
  - Let user confirm/edit detected ingredient list before suggestions

## 7.3 Multimodal Output Requirements

- `MO-01` Voice output:
  - Primary response channel for guidance
  - Alert register overrides tone in critical windows
- `MO-02` Visual output:
  - Active Process Bar states:
    - In progress
    - Countdown
    - Complete/passive
    - Needs attention
  - Annotated visual crop for relevant vision checks
- `MO-03` Text output:
  - Short, glanceable instructions only
- `MO-04` Notification output:
  - Deferred wind-down follow-up
  - In-app fallback if push not engaged
- `MO-05` AI-generated guide image output:
  - On demand, generate "target state" guide images for current step (for example, onion saute stages, sauce thickness, dough texture)
  - Present side-by-side:
    - User current frame
    - Generated target-state guide
  - Overlay 1-2 concrete cues (for example, "edges are light golden," "oil sheen visible")
  - Keep style consistent across session using a single image-generation chat/session context
- `MO-06` Recipe suggestion output from inventory scan:
  - Show dual-lane suggestions:
    - `From your saved recipes`
    - `Buddy recipe ideas`
  - Each card includes:
    - Match score
    - Missing ingredients
    - Estimated time and difficulty
    - Source label (`Saved` or `Buddy`)

## 7.4 Voice Modes Behavior

- `VM-01 Ambient Listen`
  - Session-scoped opt-in
  - Persistent indicator visible while active
  - No ambient raw media persistence
- `VM-02 Active Query`
  - Direct user ask via voice or tap
  - Fast response priority
- `VM-03 Vision Check`
  - Capture frame/video snippet
  - Return confidence-based response
  - If confidence low, provide sensory fallback

## 7.5 Vision Confidence Hierarchy

- `VC-01 High`: Direct confirmation/correction
- `VC-02 Medium`: Qualified answer + sensory check prompt
- `VC-03 Low`: Ask for reposition + fallback to smell/sound/texture cues
- `VC-04 Failed`: Explicitly state inability to assess and fallback to non-visual guidance

## 7.6 Calibration and Adaptation

- `CA-01` Onboarding calibration micro-session (low-stakes recipe)
- `CA-02` Per-recipe technique compression/expansion
- `CA-03` In-session recalibration triggers:
  - Clarification asks
  - Skips/"I know" intent
  - Recoverable errors
  - "Why" questions
- `CA-04` Alert override in critical moments

## 7.7 Concurrency Model

- `CM-01` Track multiple active processes simultaneously.
- `CM-02` Maintain priority queue `P0-P4`.
- `CM-03` Offer user choice for P1 conflicts.
- `CM-04` Timeout triage by irreversibility if no response.
- `CM-05` Show buddy-managed delegated monitoring state.

## 7.8 Taste and Recovery

- `TR-01` Taste trigger order:
  - Prompted
  - User-explicit
  - Visual gesture fallback
- `TR-02` Five-dimension taste guidance with stage awareness.
- `TR-03` "Something's missing" diagnostic mini-flow (3 questions).
- `TR-04` Error recovery sequence:
  - Immediate action
  - Acknowledgment
  - Honest assessment
  - Concrete path forward

## 7.9 Post-Session

- `PS-01` Completion beat with brief intentional pause + short verbal send-off.
- `PS-02` Max 3 optional wind-down interactions (short and fast).
- `PS-03` Memory confirmation gate required before preference persistence.
- `PS-04` Deferred wind-down with in-app fallback for notification non-engagement.

## 7.10 Fridge/Pantry-to-Recipe Flow

- `FP-01` Home entry includes `Cook from Fridge or Pantry`.
- `FP-02` User can choose scan source: `Fridge` or `Pantry`.
- `FP-03` System extracts ingredient candidates and confidence from scan media.
- `FP-04` User can edit the detected ingredient list before recommendation.
- `FP-05` Suggestion engine returns:
  - Matching saved recipes
  - Buddy-generated recipes constrained to detected ingredients
- `FP-06` Suggestion ranking prioritizes:
  - Ingredient match coverage
  - Missing ingredient count
  - Estimated time and skill fit
- `FP-07` Selecting a suggestion transitions directly to session setup.
- `FP-08` If scan confidence is low, system falls back to manual ingredient entry.

---

## 8. Non-Functional Requirements

- `NFR-01 Latency`
  - Voice query p95 response start: <= 1.8s
  - Vision check p95 response: <= 3.5s
  - Fridge/pantry scan-to-suggestions p95: <= 6.0s (up to 3 images)
  - Process-bar state updates: <= 500ms backend-to-client
- `NFR-02 Reliability`
  - Session continuity despite vision failures
  - Graceful degradation to voice-only
- `NFR-03 Privacy`
  - Ambient mode requires explicit opt-in and visible indicator
  - No long-term storage of ambient frames/audio by default
  - User-triggered artifacts only (optional photo, confirmed memories)
- `NFR-04 Cost`
  - Use `gemini-2.5-flash` default
  - Route expensive reasoning to `gemini-2.5-pro` only when needed
- `NFR-05 Security`
  - Firebase Auth token verification server-side
  - Least-privilege service accounts
- `NFR-06 Scan Quality and Trust`
  - Always expose ingredient confidence and allow manual correction
  - Never auto-start cooking from unconfirmed ingredient detections

---

## 9. Google Cloud Architecture

## 9.1 Core Services and Rationale

1. Vertex AI (Gemini):
   - `gemini-live-2.5-flash-preview-native-audio` for real-time multimodal interaction
   - `gemini-2.5-flash` for step guidance, taste reasoning, vision checks, and fridge/pantry ingredient extraction
   - `gemini-2.0-flash-preview-image-generation` for on-demand visual guide generation
2. Cloud Run:
   - Containerized backend APIs and WebSocket/SSE realtime gateway
3. Firestore:
   - User/session/recipe state and live process metadata
4. Cloud Storage (GCS):
   - Recipe reference images, annotated crops, session artifacts
   - Use `gs://` URIs directly with Gemini
5. Firebase Auth:
   - Mobile authentication + backend token verification
6. Firebase Storage (optional client uploads):
   - User-facing uploads with auth rules
7. BigQuery (optional analytics track):
   - Event analytics and post-demo dashboards
8. Cloud Build + Artifact Registry:
   - CI/CD for backend deployments
9. IAM + Service Accounts:
   - Least privilege and environment isolation

## 9.2 High-Level System Flow

1. Mobile app authenticates user via Firebase Auth.
2. User chooses entry path:
   - Select saved recipe, or
   - Scan fridge/pantry to discover recipe options
3. For scan path, Cloud Run extracts ingredient candidates from images and asks user to confirm/edit.
4. Recommendation engine returns two lanes:
   - Matching saved recipes
   - Buddy-generated recipes from confirmed ingredients
5. User selects a suggestion and app starts a cooking session.
6. Cloud Run orchestrates live interaction with Vertex AI Gemini Live.
7. Vision frames and recipe reference assets are read from `gs://` URIs when needed.
8. On request, Cloud Run generates a step-specific guide image (target consistency/state) and returns it with cue overlays.
9. Session state, calibration, process queue, memory confirmations, and scan artifacts are persisted in Firestore/GCS.
10. Optional session events stream to BigQuery for analytics.

---

## 10. Data Model (Firestore)

## 10.1 Collections

- `users/{uid}`
  - profile, preferences, calibration_summary, created_at
- `recipes/{recipe_id}`
  - source_type, parsed_steps, technique_tags, ingredients_normalized, reference_image_uris, guide_image_prompts
- `inventory_scans/{scan_id}`
  - uid, source (`fridge` or `pantry`), image_uris, detected_ingredients, confidence_map, confirmed_ingredients, created_at
- `inventory_scans/{scan_id}/suggestions/{suggestion_id}`
  - source_type (`saved_recipe` or `buddy_generated`), recipe_id, title, match_score, missing_ingredients, estimated_time_min, difficulty, created_at
- `sessions/{session_id}`
  - uid, recipe_id, status, started_at, ended_at, mode_settings
- `sessions/{session_id}/processes/{process_id}`
  - name, priority, state, due_at, buddy_managed
- `sessions/{session_id}/events/{event_id}`
  - type, timestamp, payload
- `sessions/{session_id}/guide_images/{guide_id}`
  - step_id, stage_label, source_frame_uri, generated_guide_uri, cue_overlays, created_at
- `users/{uid}/memories/{memory_id}`
  - observation, confirmed, confidence, source_session_id

## 10.2 Storage Objects (GCS/Firebase Storage)

- `reference-crops/{recipe_id}/{step_id}.png`
- `session-uploads/{uid}/{session_id}/{timestamp}.jpg`
- `session-annotations/{session_id}/{event_id}.png`
- `guide-images/{recipe_id}/{step_id}/{stage}.png`
- `inventory-scans/{uid}/{scan_id}/{timestamp}.jpg`

---

## 11. AI Orchestration Design

## 11.1 Agent Roles (ADK-style, optional but recommended)

- `SessionOrchestrator`:
  - Primary turn manager and response composer
- `VisionAssessor`:
  - Confidence scoring + fallback routing
- `InventoryVisionExtractor`:
  - Extracts and normalizes ingredient candidates from fridge/pantry images
- `RecipeSuggester`:
  - Ranks saved recipes and generates buddy recipes from confirmed ingredients
- `GuideImageGenerator`:
  - Generates target-state visual guides and keeps visual style consistent across a session
- `ProcessManager`:
  - Active Process Bar state and priority queue logic
- `TasteCoach`:
  - Dimension + stage-aware taste recommendations
- `RecoveryGuide`:
  - Enforces recovery sequence and direct next-action output

## 11.2 Tooling Pattern

- Firestore tools: read/write session/process/memory state
- Inventory tools: scan persistence, ingredient normalization, suggestion ranking
- Timer tools: schedule and trigger priority events
- GCS tools: fetch reference signal crops
- Guide image tools: create/store target-state image guides
- Notification tool: deferred wind-down follow-up

## 11.3 Model Routing Policy

- Default: `gemini-2.5-flash`
- Ingredient extraction from fridge/pantry images: `gemini-2.5-flash`
- Realtime conversation/audio: Gemini Live model
- Image generation (guide output): `gemini-2.0-flash-preview-image-generation`
- Escalation to `gemini-2.5-pro` only for high-complexity reasoning (optional in hackathon)

---

## 12. API Surface (Cloud Run)

## 12.1 REST Endpoints

- `POST /v1/inventory-scans`
  - Upload fridge/pantry images and return detected ingredient candidates + `scan_id`
- `POST /v1/inventory-scans/{id}/confirm-ingredients`
  - User confirms/edits ingredient list for recommendation
- `GET /v1/inventory-scans/{id}/suggestions`
  - Return dual-lane recipe suggestions (`saved_recipe` + `buddy_generated`)
- `POST /v1/inventory-scans/{id}/start-session`
  - Select suggestion and create cooking session
- `POST /v1/sessions`
  - Create session and initialize mode state
- `POST /v1/sessions/{id}/activate`
  - Start live cooking flow
- `POST /v1/sessions/{id}/vision-check`
  - Upload frame reference or URI; return assessment
- `POST /v1/sessions/{id}/visual-guide`
  - Generate target-state guide image for current step and return guide URI + cue overlays
- `POST /v1/sessions/{id}/taste-check`
  - Run taste diagnostic flow
- `POST /v1/sessions/{id}/recover`
  - Trigger structured recovery sequence
- `POST /v1/sessions/{id}/complete`
  - Finalize session and trigger wind-down

## 12.2 Realtime Channel

- `WS /v1/live/{session_id}` or SSE fallback
  - Bi-directional event stream for voice events, process updates, and buddy outputs

---

## 13. UX Requirements for Demo

1. Home entry includes `Cook from Fridge or Pantry`.
2. Scan flow supports either fridge or pantry with quick retake.
3. Detected ingredients screen supports chip-level edit before suggestions.
4. Suggestion view shows two lanes: `From Saved` and `Buddy Recipes`.
5. Session setup screen with three phone setup options.
6. Session activation CTA after ingredient gate.
7. Persistent ambient mode indicator when enabled.
8. Active Process Bar always visible during session.
9. At least one P1 conflict prompt with user choice.
10. At least one vision-check response with confidence-based behavior.
11. At least one generated guide image shown for doneness/consistency comparison.
12. Post-session difficulty emoji + memory confirmation prompt.

---

## 14. Observability and Success Metrics

## 14.1 Product Metrics

- Inventory scan start rate (home -> scan started)
- Scan-to-suggestion completion rate
- Suggestion-to-session conversion rate
- Saved vs buddy-generated recipe selection split
- Ingredient detection edit rate (how often user corrects detected list)
- Session start rate from ingredient-ready screen
- Session completion rate
- Number of successful vision checks per session
- Number of generated guide-image requests per session
- Guide-image acceptance/helpfulness signal (quick thumbs up/down)
- Frequency of user override ("I know", skip) and adaptation response
- Memory confirmation acceptance rate

## 14.2 Technical Metrics

- p50/p95 inventory scan processing latency
- p50/p95 suggestion generation latency
- p50/p95 voice response latency
- p50/p95 vision assessment latency
- p50/p95 guide-image generation latency
- WebSocket disconnect rate
- Cloud Run error rate and cold start impact
- Firestore write/read error rates

## 14.3 Hackathon Success Criteria

1. Live demo completes full session without manual backend intervention.
2. Fridge/pantry scan path demonstrates ingredient detection and dual-lane recipe suggestions.
3. Multimodal interactions function in real time (voice + vision + UI state).
4. At least one error recovery and one taste diagnostic path demonstrated.
5. At least one generated visual guide output demonstrated in-session.
6. Privacy constraints visible in UX (ambient indicator + explicit mode consent).

---

## 15. Security, Privacy, and Trust

- Enforce Firebase Auth token verification on every protected backend endpoint.
- Use dedicated service account for backend with least-privilege roles.
- Do not persist ambient raw media by default.
- Store only user-consented artifacts (photo, confirmed preference memories).
- Include explicit smoke-detection disclaimer: informational only, not a safety alarm.

---

## 16. Hackathon Delivery Plan (48 Hours)

## 16.1 Day 0 / Setup (2-4h)

1. Create GCP project and enable APIs.
2. Set up service account and IAM roles.
3. Initialize Cloud Run backend and Firebase project.
4. Set up Firestore and Storage buckets.

## 16.2 Day 1 / Core Build (14-18h)

1. Implement auth and inventory scan creation.
2. Implement ingredient extraction + user confirmation endpoint.
3. Implement recipe suggestion endpoints (saved + buddy-generated).
4. Implement session creation from selected suggestion.
5. Implement live voice loop with Gemini Live.
6. Implement Active Process Bar state engine.
7. Implement Vision Check endpoint with confidence hierarchy.
8. Implement visual-guide image generation endpoint and GCS persistence.
9. Implement taste diagnostic and error recovery routes.

## 16.3 Day 2 / Polish + Demo (14-18h)

1. Integrate post-session flow and memory confirmation.
2. Add logs/metrics dashboards.
3. Harden fallback paths (voice-only degradation).
4. Finalize scripted demo with one primary recipe.
5. Deploy stable build via Cloud Build to Cloud Run.

---

## 17. Team Split (Suggested)

- Engineer A (Mobile): session UX, voice/vision triggers, process bar UI
- Engineer B (Backend): Cloud Run APIs, Firestore schema, inventory scan + suggestion logic
- Engineer C (AI): prompts, model routing, ingredient extraction, confidence/fallback behavior
- Engineer D (Infra): auth, IAM, CI/CD, observability, demo reliability

---

## 18. Risks and Mitigations

1. Realtime latency spikes
   - Mitigation: keep min Cloud Run instances at 1; stream partial responses
2. Vision false confidence
   - Mitigation: strict confidence thresholds + explicit fallback language
3. Demo instability due to network
   - Mitigation: preloaded recipe assets in GCS and scripted checkpoints
4. Ingredient misdetection from cluttered fridge/pantry images
   - Mitigation: confidence scores + mandatory user confirmation/edit screen
5. Scope creep
   - Mitigation: lock feature set to Pillar 3 core loop and single high-quality scenario
6. Privacy concerns with ambient mode
   - Mitigation: explicit opt-in, visible indicator, no ambient persistence

---

## 19. Open Decisions to Lock Before Build

1. Choose mobile stack (`Flutter` vs `React Native`) based on team strength.
2. Decide realtime transport (`WebSocket` primary, SSE fallback).
3. Confirm push-notification fallback behavior for deferred wind-down.
4. Confirm suggestion ranking formula (ingredient match vs time vs skill fit).
5. Confirm one canonical demo recipe with known visual checkpoints.

---

## 20. Post-Hackathon Roadmap

1. Improve parser reliability for YouTube/Instagram URLs and fridge/pantry ingredient detection quality.
2. Expand personalization depth beyond Session 7.
3. Add BigQuery analytics dashboards and A/B testing hooks.
4. Start Phase 2 planning for grocery extension after core loop validation.
