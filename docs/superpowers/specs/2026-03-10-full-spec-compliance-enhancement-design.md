# Ratatouille — Full Spec Compliance Enhancement Design

**Date**: 2026-03-10
**Goal**: Systematically close every gap between the implemented code and the 9 epic specifications, with full audio/video integration to deliver a "video calling your mom for cooking guidance" experience.

---

## ID Convention

Gap IDs in this document use a `D` prefix (e.g., D4.1, D9.3) to distinguish from epic task IDs (e.g., epic task 4.1 = "Session Creation Endpoint"). Design gap D4.1 refers to "microphone capture" — a completely different thing from epic task 4.1. Always use the `D` prefix when referencing items from this document.

---

## Core UX Metaphor

Every interaction during a live cooking session should feel like FaceTime with a cooking-savvy friend:

- User props phone in kitchen — camera shows their stovetop (full-screen, primary view)
- Buddy speaks naturally through the speaker — no text bubbles as primary UI
- User talks naturally — mic is always hot, no push-to-talk
- Buddy can see what the user sees — proactively comments ("your garlic is getting dark")
- User can interrupt anytime — buddy stops mid-sentence immediately
- Buddy shows reference photos mid-call — guide images slide up as overlays, camera shrinks to PIP for side-by-side comparison
- Timers and processes appear as a glanceable strip — like a kitchen timer bar
- Call chrome at the bottom — mute, flip camera, end call — familiar video call controls

---

## Approach

**Epic-by-epic sequential sweep** in dependency order: 1 → 2 → 3 → 4 → 5 → 6 → 8 → 9 → 7.

For each epic:
1. Read spec (all tasks + acceptance criteria)
2. Read every relevant code file
3. List gaps
4. Implement fixes
5. Verify acceptance criteria

**Execution strategy:**
- Parallel subagents for independent backend vs mobile work
- `/frontend-design` and `/ui-ux-pro-max` skills for all UI redesign
- Backend-first when both layers need changes (stable contract before mobile integrates)

**Constraints**: No constraints — full freedom to modify any file, add dependencies, restructure.

---

## New Flutter Dependencies

| Package | Purpose |
| --- | --- |
| `record` | Microphone capture (PCM/opus audio frames) |
| `just_audio` | Audio playback for buddy voice responses |
| `camera` | Live camera preview + frame capture for vision checks |
| `permission_handler` | Runtime permissions for mic + camera |
| `connectivity_plus` | Real network state monitoring |
| `flutter_local_notifications` | Deferred wind-down notifications |

---

## Epic 1 — Infrastructure & Platform Foundation

### Current State
Mostly solid. Config, auth, Dockerfile, cloudbuild all present and real.

### Gaps

| ID | Gap | Fix |
| --- | --- | --- |
| D1.1 | Dockerfile missing ffmpeg — video keyframe extraction will crash | Add `apt-get install -y ffmpeg` to runtime stage |
| D1.2 | Health check GCS call is synchronous (violates async-everywhere) | Wrap in `asyncio.to_thread()` |
| D1.3 | CORS allows all origins (`*`) | Add explicit origin list from config with `*` fallback for dev |

---

## Epic 2 — Recipe Management & Data Layer

### Current State
Fully implemented backend. Mobile recipe screens are stubs.

### Gaps

| ID | Gap | Fix |
| --- | --- | --- |
| D2.1 | Demo recipe seed data not verified against spec (7 steps, guide_image_prompts, P1 conflict at steps 3+4) | Audit `seed_demo.py` against Epic 2 spec, ensure all fields populated |
| D2.2 | Recipe model may be missing `checklist_gate` field | Verify and add if missing |
| D2.3 | Mobile recipe screens (list/detail/create/checklist) are stubs | Wire to real API calls |

---

## Epic 3 — Fridge/Pantry Scan & Recipe Suggestions

### Current State
Backend strong (dual-lane, ranking, grounding). Mobile scan works but has gaps.

### Gaps

| ID | Gap | Fix |
| --- | --- | --- |
| D3.1 | Mobile: Video scan captured but never analyzed | Wire video upload → GCS → backend keyframe extraction → Gemini detection |
| D3.2 | "Why this recipe?" explanation is a stub | Implement real call to explanation endpoint |
| D3.3 | No upload progress visibility (simulated 30%) | Use streaming upload with real progress callbacks |
| D3.4 | No camera permission handling UI | Add `permission_handler` checks + rationale dialog |
| D3.5 | Scan error recovery weak — no retry guidance | Add retry button + "Try manual entry" fallback |
| D3.6 | ffmpeg dependency for video keyframes | Covered by D1.1 |
| D3.7 | Manual add uses keyboard — no voice alternative | Add mic icon for speech-to-text ingredient dictation |

---

## Epic 4 — Live Cooking Session & Voice Loop

### Current State
Backend comprehensive (orchestrator, voice modes, calibration, degradation). Mobile has UI skeleton but no real audio/video.

### Design: "Call With Mom" Experience

**Live session screen layout:**
```
┌─────────────────────────┐
│                         │
│    Camera Feed          │
│    (full screen)        │
│                         │
├─────────────────────────┤
│ Listening...            │  ← connection state
│                         │
│ "Looking good! Give it  │  ← buddy caption
│  another 30 seconds"    │     (live, fades)
├─────────────────────────┤
│ ┌─────────────────────┐ │
│ │ Pasta 3:42 | Garlic │ │  ← process bar (sticky)
│ └─────────────────────┘ │
├─────────────────────────┤
│  Mute   Flip   End     │  ← call chrome
└─────────────────────────┘
```

**Guide image overlay (when buddy shows a reference):**
```
┌─────────────────────────┐
│                         │
│   Guide Image           │
│   (generated)           │
│   "Your onions should   │
│    look like this"      │
│                         │
│   ┌───────────────┐     │
│   │ Your camera   │     │  ← camera shrinks to PIP
│   │ (small PIP)   │     │
│   └───────────────┘     │
│   [ Looks right ]       │  ← quick dismiss
├─────────────────────────┤
│  Mute   Flip   End     │
└─────────────────────────┘
```

### Gaps

| ID | Gap | Fix |
| --- | --- | --- |
| **Audio Pipeline** |  |  |
| D4.1 | No microphone capture | Add `record` package. Continuous capture, encode base64, stream to WS as `voice_audio` events. Mic always hot (no push-to-talk) |
| D4.2 | No audio playback — buddy is silent | Add `just_audio`. Backend sends audio via WS; play through speaker as continuous stream |
| D4.3 | Barge-in flag set but playback never halted | On `barge_in` WS event: immediately stop player (<200ms), flush buffer, send `barge_in_ack` |
| **Video Pipeline** |  |  |
| D4.4 | No camera preview in live session | Add `camera` package. Camera feed is the primary view (full screen). Hands-busy ergonomics: large tap targets (64px+), arm's-length readable text |
| D4.5 | Vision check requires leaving live session | Capture frame from live camera, send to vision-check endpoint inline, buddy speaks result |
| **Guide Image in Call** |  |  |
| D4.16 | No guide image overlay | Guide image slides up over camera, camera moves to PIP corner for side-by-side comparison |
| D4.17 | No buddy-initiated guide showing | Buddy proactively shows guide images at recipe checkpoints |
| D4.18 | No user-initiated guide request | "What should this look like?" triggers guide image generation from current step |
| D4.19 | No quick dismiss | Tap "Looks right" or swipe down to return to full camera |
| D4.20 | No cue overlays on guide image | Render keyframe cue annotations as callout overlays |
| D4.21 | Guide image style inconsistency | Single Gemini chat session per cooking session for consistent visual style (chat object cached per-session) |
| D4.22 | No voice accompaniment with guide | Buddy narrates while showing the reference image |
| **WebSocket** |  |  |
| D4.6 | Missing WS event types for browse mode | Add handlers for `browse_observation`, `ingredient_candidates`, `browse_question` |
| D4.7 | No message validation | Add response schema validation; log contract errors |
| D4.8 | Pong timeout closes without reconnect | Trigger reconnect on pong timeout |
| **Session UX** |  |  |
| D4.9 | Only `_lastBuddyMessage` shown — no history | Buddy captions as primary (live, fading). Conversation history accessible by swipe-up, hidden by default |
| D4.10 | No actionable UI after max reconnect retries | Show "Connection lost — Tap to reconnect" button |
| D4.11 | Session resume doesn't restore UI state | On `session_state` WS response, rebuild: current step, active processes, last buddy message |
| D4.23 | Step transitions not verified as atomic | Verify backend persists step transitions atomically before sending WS update |
| **Call Chrome** |  |  |
| D4.14 | No call-like controls | Mute button, camera flip, end call — bottom bar like FaceTime |
| D4.15 | Ambient mode ("mom watching") not wired | Buddy proactively comments on camera feed. **Opt-in only** (VM-01), rate-limited (1 frame every 5s max), not always-on |
| **Backend** |  |  |
| D4.12 | Gemini Live audio streaming not verified e2e | Audit and fix `live_audio.py` for bidirectional audio |
| D4.13 | WS only sends text `buddy_message`, no audio | Add `buddy_audio` WS event type with base64 audio payload |

---

## Epic 5 — Process Management, Timers & Concurrency

### Current State
Backend fully implemented. Mobile process bar and conflict chooser partially done.

### Gaps

| ID | Gap | Fix |
| --- | --- | --- |
| D5.1 | Process bar no priority-based styling | Color-code: P0 pulsing red, P1 amber, P2 primary, P3-P4 dimmed |
| D5.2 | Conflict timeout doesn't show what was decided | Toast: "Buddy handled it — keeping garlic on low" |
| D5.3 | Timer countdown not visible on process chips | Live mm:ss countdown. 1-minute warning: amber pulse |
| D5.4 | No audio alert for timer events | Gentle tone at warning/completion + buddy vocal announcement |
| D5.5 | P0 critical interrupt no differentiation | Full-width red banner, calm-urgent buddy voice, haptic feedback |
| D5.6 | Timer completion WS events not verified | Audit `timers.py` → `live.py` flow for `timer_warning`/`timer_done` |
| D5.7 | P1 conflict resolution WS event not verified | Audit `processes.py` → WS `conflict_resolved` event |

---

## Epic 6 — Vision, Visual Guides, Taste & Recovery

### Current State
Backend fully implemented. Mobile entirely stubbed — all return hardcoded data.

### Design Change
No longer separate tabs on a separate screen. Integrated into the live call experience. Standalone VisionGuideScreen kept as degraded-mode fallback only.

### Gaps

| ID | Gap | Fix |
| --- | --- | --- |
| **Vision** |  |  |
| D6.1 | `_captureAndCheck()` returns hardcoded data | Capture frame → upload GCS → call vision-check → buddy speaks result |
| D6.2 | No inline vision in live session | Voice-triggered or buddy-initiated from active camera feed |
| D6.3 | Confidence tier UX identical for all tiers | High: confident. Medium: qualified + sensory prompt. Low: reposition request. Failed: sensory-only guidance |
| D6.11 | No bright-kitchen-lighting readability test | Test vision result UI readability in bright conditions (high contrast, large text for confidence badges) |
| **Guide Image** |  |  |
| D6.4 | `_requestGuide()` returns dummy result | Real call to visual-guide endpoint → overlay display per D4.16-D4.22 |
| D6.5 | Cue overlays not wired | Render backend-extracted cue annotations on guide image |
| **Taste** |  |  |
| D6.6 | `_submitTaste()` returns dummy | Real call to taste-check → vocal diagnostic conversation |
| D6.7 | Taste is form-based, should be conversational | Remove tab/form UX. Entirely voice dialogue within the call |
| **Recovery** |  |  |
| D6.8 | `_submitRecovery()` returns hardcoded | Real call to recover endpoint → spoken 4-step recovery sequence |
| D6.9 | Recovery should feel immediate | No spinner. Instant vocal response: "Turn off the heat NOW" → acknowledgment → assessment → path forward |
| **Fallback** |  |  |
| D6.10 | VisionGuideScreen as separate route | Keep as degraded-mode fallback. Default is integrated into call |

---

## Epic 8 — Mobile App Foundation & UX Integration

### Current State
Good architecture. Critical gaps in networking, permissions, live session design.

### Gaps

| ID | Gap | Fix |
| --- | --- | --- |
| **Networking** |  |  |
| D8.1 | No request timeouts | 10s quick calls, 30s AI endpoints, 5s WS pings |
| D8.2 | No request cancellation on screen exit | Cancel in-flight requests on dispose |
| D8.3 | No real connectivity monitoring | Add `connectivity_plus`, auto-trigger WS reconnect on recovery |
| D8.4 | No retry for transient 5xx | Exponential backoff for 502/503/504 (idempotent only) |
| **Permissions** |  |  |
| D8.5 | No runtime permission handling | `permission_handler` for mic + camera. Rationale dialog. Graceful degradation if denied |
| **Live Session** |  |  |
| D8.6 | Text-message style live session | Full redesign: camera full-screen, buddy captions, call chrome |
| D8.7 | No audio pipeline | `record` for capture → WS. WS buddy audio → `just_audio` |
| D8.8 | No camera pipeline | `camera` for continuous preview + frame capture |
| **Routes** |  |  |
| D8.9 | Hardcoded route strings | Replace with `AppRoutes` constants throughout |
| D8.10 | Scan → suggestions → live transition not smooth | Seamless flow: confirm → suggestions load → "Start Cooking" → call screen |
| **Recipes** |  |  |
| D8.11 | Recipe screens are stubs | Wire to real API |
| D8.12 | No ingredient checklist gate | Checklist confirmation before recipe-guided session activation |
| **Error & Degradation** |  |  |
| D8.13 | No error boundary | Error boundary widget catches unhandled errors, shows friendly UI |
| D8.14 | Degradation transitions not visible | Toast: "Video unavailable — switching to voice only". Buddy announces vocally |
| **Accessibility** |  |  |
| D8.17 | No accessibility validation | Dynamic text scaling, contrast checks, screen-reader labels for critical controls (mute, end call, process bar) |
| **Contract Tests** |  |  |
| D8.18 | No fixture-driven contract/decode tests | Contract tests covering all mobile-consumed REST endpoints and WS event types with fixture data |
| **Polish** |  |  |
| D8.15 | Inconsistent loading states | Skeleton loaders for content, subtle spinner for actions, never block call UI |
| D8.16 | ConnectivityBanner dismissal not persisted | Remember per session |

---

## Epic 9 — Zero-Setup "Seasoned Chef Buddy" Mode

### Current State
Backend supports freestyle. Good "Cook Now" CTA. Voice-first mandate has gaps.

### Gaps

| ID | Gap | Fix |
| --- | --- | --- |
| **Voice-First** |  |  |
| D9.1 | "Type Instead" button visible in call UI | Remove from default chrome. Only in degraded mode |
| D9.2 | Degraded text input keyboard obscures camera | Floating minimal input overlay, or speech-to-text primary |
| D9.3 | Manual ingredient entry via keyboard | Add voice dictation (mic icon) |
| **Freestyle Bootstrap** |  |  |
| D9.4 | Bootstrap flow not verified e2e | Verify: Cook Now → create freestyle session → activate → WS → buddy greets vocally |
| D9.5 | ≤2 tap entry not verified | Audit: Home → Cook Now → Start Cooking = 2 taps max |
| D9.13 | In-session context capture uses text fields | Context capture must work without any text field or keyboard. Voice-only or tap-based options |
| **Live Browse** |  |  |
| D9.6 | Missing WS handlers for browse events | Add `browse_observation`, `ingredient_candidates`, `browse_question` handlers |
| D9.7 | Browse mode UX not implemented | Buddy narrates what it sees. Floating ingredient labels over camera. User confirms vocally |
| D9.8 | Browse → cooking transition | Buddy suggests recipe from what it saw → user agrees → cooking begins in same call |
| D9.14 | No browse fallback for poor video quality | When video quality is poor during browse, ask for still capture or verbal confirmation instead |
| **Metrics** |  |  |
| D9.11 | Zero-setup funnel metrics not emitted | Emit: `zero_setup_entry_tapped`, `zero_setup_session_created`, `time_to_first_instruction_ms` per Epic 9 spec |
| **Safety & Audit** |  |  |
| D9.9 | Safety constraints not verified in freestyle | Verify high-risk keyword detection in freestyle voice responses |
| D9.10 | Text input audit not run against mobile | Audit every `TextField` — produce formal audit matrix: Keep / Replace / Optional for each text input point |
| D9.12 | Demo script missing zero-setup segment | Verify demo script (Epic 7 §7.9) includes at least one zero-setup segment showing the Cook Now flow |

---

## Epic 7 — Post-Session, Observability & Demo Hardening

### Current State
Backend analytics/metrics/logging present. Mobile memory gate has no persistence.

### Gaps

| ID | Gap | Fix |
| --- | --- | --- |
| **Post-Session** |  |  |
| 7.1 | Memory gate never calls backend | Wire to memory persistence endpoint |
| 7.2 | Wind-down ≤3 interaction limit not enforced | Counter enforced client-side + backend |
| 7.3 | Session summary field mismatches | Validate `CompleteResponse` model against backend |
| 7.4 | No deferred wind-down notification | `flutter_local_notifications` — 30min reminder if session abandoned |
| **Observability** |  |  |
| 7.5 | Product events not verified | Verify all spec events emitted: session_started, vision_check_requested, barge_in_triggered, etc. |
| 7.6 | No correlation ID across WS events | Add `session_id` + `event_id` to all log entries |
| **Degradation Hardening** |  |  |
| 7.7 | Degradation paths not tested e2e | Verify: Gemini timeout → fallback, vision failure → sensory, audio failure → text, WS disconnect → reconnect |
| 7.8 | Degradation notice not surfaced | Buddy announces vocally + toast UI |
| **Demo** |  |  |
| 7.9 | Demo script not validated against code | Walk through acts 0-4 against actual code |
| 7.10 | Demo recipe checkpoints not verified in seed data | Cross-reference seed_demo.py against demo script |
| 7.11 | Architecture diagram not generated | Create spec-matching diagram |
| 7.12 | README gaps | Verify Devpost checklist completeness |

---

## Scope Summary

| Epic | Backend | Mobile | Skills |
| --- | --- | --- | --- |
| 1 | 3 fixes | 0 | Subagent |
| 2 | 1 audit | 2 fixes | Subagent |
| 3 | 1 dep | 6 fixes | `/frontend-design` |
| 4 | 2 fixes | 22 items (full redesign) | `/frontend-design` + `/ui-ux-pro-max` |
| 5 | 2 verifications | 5 fixes | `/frontend-design` |
| 6 | 0 | 11 (stubs → real + readability) | Subagent |
| 7 | 2 fixes | 7 fixes + demo validation | Subagent |
| 8 | 0 | 18 (infra + accessibility + contracts) | `/frontend-design` + `/ui-ux-pro-max` |
| 9 | 1 audit | 16 fixes (+ metrics, browse fallback, audit matrix) | Subagent |
| **Total** | **~12** | **~90** |  |
