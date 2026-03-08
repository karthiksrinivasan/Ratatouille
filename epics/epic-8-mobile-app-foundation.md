# Epic 8: Mobile App Foundation & UX Integration

## Goal

Ship a production-grade mobile app shell (Flutter) with robust UX that connects cleanly to the backend APIs/WebSocket, handles degraded network conditions, and is demo-ready on real iOS and Android devices.

## Prerequisites

- Epic 1 complete (Firebase Auth, Cloud Run scaffold, base config)
- Can start in parallel with backend epics, but full integration depends on Epic 2-6 endpoint readiness

## PRD References

- §7.1 Session lifecycle
- §7.2 MI-05 (scan input)
- §7.3 MO-02/MO-05/MO-06 (visual outputs, guide image, suggestion cards)
- §7.4 VM-01..VM-04 (voice modes + barge-in)
- §7.7 Concurrency model
- §7.10 Fridge/Pantry flow
- §13 UX Requirements for Demo
- §14.4 Judging criteria alignment
- NFR-01/NFR-02/NFR-07/NFR-08

---

## Backend Contract Surface (Mobile Integration)

**REST**
- `POST /v1/inventory-scans`
- `POST /v1/inventory-scans/{id}/detect`
- `POST /v1/inventory-scans/{id}/confirm-ingredients`
- `GET /v1/inventory-scans/{id}/suggestions`
- `GET /v1/inventory-scans/{id}/suggestions/{sid}/explain`
- `POST /v1/inventory-scans/{id}/start-session`
- `POST /v1/sessions/{id}/activate`
- `POST /v1/sessions/{id}/vision-check`
- `POST /v1/sessions/{id}/visual-guide`
- `POST /v1/sessions/{id}/taste-check`
- `POST /v1/sessions/{id}/recover`
- `POST /v1/sessions/{id}/complete`

**WebSocket**
- `WS /v1/live/{session_id}`
- Required client events: `auth`, `voice_query`, `voice_audio`, `barge_in`, `vision_check`, `step_complete`, `ambient_toggle`, `resume_interrupted`, `ping`
- Required server events: `buddy_message`, `buddy_response`, `buddy_interrupted`, `process_update`, `timer_alert`, `vision_result`, `guide_image`, `mode_update`, `error`, `pong`

---

## Tasks

### 8.1 Flutter App Architecture & State Management

**What:** Establish app architecture and module boundaries so feature teams can work in parallel.

**Implementation choices:**
- Routing: `go_router`
- State management: `Riverpod` (or Bloc if team already standardized)
- Network: `dio` with typed models
- Local cache: lightweight (`hive` or `shared_preferences`) for session resume hints

**Acceptance Criteria:**
- [ ] Feature-first folder structure created (`scan`, `suggestions`, `live_session`, `vision_guide`, `post_session`)
- [ ] App-wide error boundary and loading overlay pattern defined
- [ ] Shared design tokens (spacing, typography, color roles) centralized

---

### 8.2 Firebase Auth Integration (Mobile)

**What:** Implement sign-in and token lifecycle for all backend calls.

**Acceptance Criteria:**
- [ ] Firebase sign-in works on iOS/Android
- [ ] ID token attached to every REST request (`Authorization: Bearer ...`)
- [ ] WS auth supports query token and `auth` first-message fallback
- [ ] Token refresh and re-auth retry path implemented

---

### 8.3 Typed API Client + Contract Models

**What:** Build typed request/response models for all critical endpoints and enforce strict decoding.

**Acceptance Criteria:**
- [ ] All endpoints in the contract surface mapped to typed client methods
- [ ] Contract mismatch logs include endpoint + payload + decode error
- [ ] Retry policy implemented for idempotent GET/POST paths where safe
- [ ] User-facing error mapping defined (network, auth, server, validation)

---

### 8.4 Realtime WS Client (Resilient)

**What:** Build a robust WebSocket client with reconnect/resume semantics for live cooking.

**Required behavior:**
- Heartbeat (`ping/pong`) and timeout handling
- Exponential reconnect with jitter
- Session resume from last known step/process state
- Ordered event application for `process_update` and `timer_alert`

**Acceptance Criteria:**
- [ ] Reconnect works after transient network loss without app restart
- [ ] No duplicate UI actions from duplicate WS events
- [ ] Barge-in event immediately halts buddy playback in UI

---

### 8.5 Media Capture & Upload Pipeline

**What:** Support both scan capture modes and live session media handoff.

**Implementation scope:**
- Photo capture (2-6)
- Short video capture (3-10s) for scan mode
- Frame capture for `vision-check`
- Optional source frame for `visual-guide`

**Acceptance Criteria:**
- [ ] Capture UX enforces image/video constraints before upload
- [ ] Upload progress visible for operations >400ms
- [ ] Upload cancellation/retry supported

---

### 8.6 Scan Flow UX (Entry -> Capture -> Review)

**What:** Deliver robust scan UX with confidence-aware ingredient editing.

**Required screens:**
1. Home entry (`Cook from Fridge or Pantry`)
2. Source + capture mode picker
3. Capture screen (photos/video)
4. Ingredient review chip editor with confidence states

**Acceptance Criteria:**
- [ ] User can complete scan+confirm flow quickly without keyboard by default
- [ ] Low-confidence ingredients are visually distinguishable
- [ ] Manual add/remove ingredient interaction is frictionless

---

### 8.7 Suggestions UX (Dual-Lane + Explainability)

**What:** Present `From Saved` and `Buddy Recipes` lanes with clear affordances and trust.

**Required card fields:**
- Match score
- Missing ingredients
- Estimated time
- Difficulty
- Source label
- `Why this recipe?` expandable explanation

**Acceptance Criteria:**
- [ ] Two lanes are clearly separated and scroll performant
- [ ] `Why this recipe?` expansion works on every card
- [ ] Suggestion selection transitions to session start with visible loading state

---

### 8.8 Session Setup + Activation UX

**What:** Bridge selected suggestion into session configuration and activation.

**Required behavior:**
- Display selected recipe summary
- Phone setup options and ambient opt-in
- Ingredient gate confirmation
- Activation CTA and failure recovery path

**Acceptance Criteria:**
- [ ] `start-session` response contract consumed correctly
- [ ] `activate` call success transitions into live WS screen
- [ ] Activation error state has retry + back path

---

### 8.9 Live Session UX (Voice-Primary)

**What:** Build high-quality live cooking UX that feels responsive in real kitchen conditions.

**Required UI states:**
- Listening
- Buddy speaking
- Interrupted
- Reconnecting
- Degraded mode (voice-text/text-only)

**Acceptance Criteria:**
- [ ] Ambient indicator always visible when enabled
- [ ] Barge-in visibly interrupts playback within 200ms on device
- [ ] Controls remain usable one-handed with large touch targets

---

### 8.10 Process Bar + Conflict Choice UX

**What:** Implement process-bar visualization and P1 conflict chooser.

**Acceptance Criteria:**
- [ ] Process bar updates are smooth and readable at a glance
- [ ] P0/P1 states are unmistakable
- [ ] P1 conflict chooser supports quick, clear choice under time pressure

---

### 8.11 Vision/Guide/Taste/Recovery UX

**What:** Implement integrated UX for high-value multimodal moments.

**Required interactions:**
- Vision check request and response rendering
- Side-by-side guide image comparison with cue overlays
- Taste check prompt/response
- Recovery card with immediate action hierarchy

**Acceptance Criteria:**
- [ ] User can request and interpret a guide image without leaving live session
- [ ] Recovery card always prioritizes immediate action first
- [ ] Confidence-aware copy is reflected in UI tone and labels

---

### 8.12 Post-Session UX + Memory Confirmation

**What:** Complete end-of-session UX and ensure memory confirmation gate is respected.

**Acceptance Criteria:**
- [ ] Completion beat -> wind-down interactions flow correctly
- [ ] Memory is only persisted after explicit user confirmation
- [ ] Deferred wind-down notification fallback appears on next app open

---

### 8.13 Mobile Quality Gates (Device + Accessibility + Perf)

**What:** Enforce robust UX quality before demo/final submission.

**Required validation:**
- Real-device QA: at least one iOS + one Android
- Accessibility: dynamic text, contrast checks, screen-reader labels for critical controls
- Performance:
  - Screen transition target <250ms where feasible
  - No main-thread jank during WS event bursts
  - Smooth scrolling in suggestion lanes and process bar

**Acceptance Criteria:**
- [ ] All critical flows pass on iOS + Android
- [ ] Top accessibility defects resolved on critical path screens
- [ ] No blocker-level UI/perf defects remain for demo route

---

### 8.14 Mobile-Backend Connectivity Hardening

**What:** Add reliability patterns so the app remains usable during unstable network and backend variability.

**Required implementation scope:**
- Unified request policy for REST calls:
  - timeout defaults
  - retry-with-backoff only for safe/idempotent operations
  - explicit cancellation on screen exit
- Connectivity state model:
  - `online`, `degraded`, `offline`
  - global banner + screen-level fallbacks
- WS failure fallback:
  - show actionable reconnect UI
  - preserve local session context so user does not lose current step/process visibility
- Contract verification:
  - fixture-driven decode tests for all critical REST responses and WS events
  - schema drift detection logged with endpoint/event name

**Acceptance Criteria:**
- [ ] No critical user flow dead-ends when network drops mid-session
- [ ] Retry behavior is predictable and never duplicates destructive actions
- [ ] Connectivity state is visible to user within 1 second of detection
- [ ] Contract tests cover all mobile-consumed REST endpoints and WS event types

---

## Epic Completion Checklist

- [ ] Auth + token lifecycle robust for REST and WS
- [ ] Typed API + WS clients integrated with backend contracts
- [ ] Scan and suggestion UX complete with explainability
- [ ] Live session UX complete with barge-in and reconnect
- [ ] Process bar/conflict UX complete
- [ ] Vision/guide/taste/recovery UX complete
- [ ] Post-session + memory gate UX complete
- [ ] iOS + Android real-device QA complete
- [ ] Accessibility/performance gates pass for demo-critical flows
- [ ] Connectivity hardening + contract verification complete for production-like demo stability
