# Ratatouille — Epic Index

## How to Use This Guide

Each epic is a self-contained unit of work with clear inputs, outputs, and acceptance criteria. Epics are ordered by dependency — earlier epics produce artifacts that later epics consume.

**For agents executing these epics:**
1. Read this index to understand the full system and dependency graph.
2. Read the specific epic file before starting any task within it.
3. Cross-reference `RATATOUILLE_HACKATHON_PRD.md` for product requirements and `GOOGLE_CLOUD_TECH_GUIDE.md` for implementation patterns.
4. Each epic lists prerequisite epics — do not start work until prerequisites are met.
5. Each task has acceptance criteria — verify all before marking complete.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│                    Mobile App (Flutter)                    │
│  ┌─────────┐ ┌──────────┐ ┌───────────┐ ┌─────────────┐ │
│  │Home/Scan│ │Recipe     │ │Live Session│ │Post-Session │ │
│  │Flow     │ │Selection  │ │Voice + UI  │ │Wind-down    │ │
│  └────┬────┘ └─────┬─────┘ └─────┬──────┘ └──────┬──────┘ │
└───────┼────────────┼─────────────┼───────────────┼────────┘
        │            │             │               │
   REST API     REST API    WebSocket (WS)    REST API
        │            │             │               │
┌───────┴────────────┴─────────────┴───────────────┴────────┐
│                Cloud Run (FastAPI Backend)                  │
│  ┌──────────┐ ┌──────────┐ ┌───────────┐ ┌─────────────┐ │
│  │Auth      │ │Scan &    │ │Session &  │ │Post-Session │ │
│  │Middleware│ │Suggestion│ │Live Loop  │ │& Memory     │ │
│  └──────────┘ └──────────┘ └───────────┘ └─────────────┘ │
│  ┌──────────────────────────────────────────────────────┐ │
│  │           AI Orchestration Layer (ADK)                │ │
│  │  SessionOrchestrator | VisionAssessor | ProcessMgr   │ │
│  │  InventoryExtractor | RecipeSuggester | GuideImageGen│ │
│  │  TasteCoach | RecoveryGuide                          │ │
│  └──────────────────────────────────────────────────────┘ │
└──────────┬──────────────┬────────────────┬────────────────┘
           │              │                │
    ┌──────┴──────┐ ┌─────┴─────┐  ┌───────┴───────┐
    │  Firestore  │ │    GCS    │  │  Vertex AI    │
    │  (state)    │ │  (media)  │  │  (Gemini)     │
    └─────────────┘ └───────────┘  └───────────────┘
```

---

## Technology Decisions

| Layer | Choice | Rationale |
|-------|--------|-----------|
| Mobile | Flutter | Cross-platform, strong voice/camera plugin ecosystem |
| Backend | Python + FastAPI on Cloud Run | Async-native, Gemini SDK is Python-first, WebSocket support |
| Database | Firestore (AsyncClient) | Real-time, serverless, document model matches PRD schema |
| Storage | GCS | Direct `gs://` URI integration with Gemini, signed URLs for mobile |
| AI Models | Gemini Flash/Live/Image-Gen via Vertex AI | See model routing table in Epic 4 |
| AI Orchestration | Google ADK | Multi-agent, tool use, state management built-in |
| Auth | Firebase Auth | Mobile SDK + server-side token verification |
| CI/CD | Cloud Build + Artifact Registry | Native GCP integration |

---

## Epic Dependency Graph

```
Epic 1: Infrastructure & Platform Foundation
  │
  ├──→ Epic 2: Recipe Management & Data Layer
  │      │
  │      ├──→ Epic 3: Fridge/Pantry Scan & Recipe Suggestions
  │      │
  │      └──→ Epic 4: Live Cooking Session & Voice Loop
  │             │
  │             ├──→ Epic 5: Process Management, Timers & Concurrency
  │             │
  │             └──→ Epic 6: Vision, Visual Guides, Taste & Recovery
  │
  ├──→ Epic 8: Mobile App Foundation & UX Integration
  │      │
  │      ├──→ Integrates Epic 2 recipe library/detail/checklist APIs
  │      ├──→ Integrates Epic 3 scan/suggestions APIs
  │      ├──→ Integrates Epic 4 live-session WS APIs
  │      ├──→ Integrates Epic 5 process bar/timer events
  │      └──→ Integrates Epic 6 vision/guide/taste/recovery UX
  │
  ├──→ Epic 9: Zero-Setup "Seasoned Chef Buddy" Mode
  │      │
  │      ├──→ Extends Epic 4 session contracts for freestyle mode
  │      ├──→ Extends Epic 8 home/live UX with no-setup entry
  │      └──→ Feeds Epic 7 demo and judging evidence
  │
  └──→ Epic 7: Post-Session, Observability & Demo Hardening
```

**Critical path:** Epic 1 → Epic 2 → Epic 4 → Epic 8 → Epic 9 → Epic 7

**Parallel tracks** (after Epic 2):
- Track A: Epic 3 (recipe/scan/suggestion pipeline)
- Track B: Epic 4 → Epic 5 + Epic 6 (live session core)
- Track C: Epic 8 (mobile app foundation, backend integration, UX hardening)
- Track D: Epic 9 (zero-setup, no-recipe live mode on top of core session stack)
- Track E: Epic 7 (integration, polish, demo — depends on all others)

## Mobile UX Track (First-Class, Not Optional)

Mobile UX quality is a judging-critical workstream, not polish at the end.

Required UX deliverables across epics:
1. Epic 2: saved recipe library/detail UX with ingredient checklist gate and reliable session handoff.
2. Epic 3: fast scan capture/edit flow, low-friction suggestion cards, grounded "Why this recipe?" expansion.
3. Epic 4: resilient live session UI (ambient indicator, barge-in UI state, reconnect/resume UX).
4. Epic 5: glanceable process bar with conflict-choice interaction under time pressure.
5. Epic 6: side-by-side visual comparison UX (camera frame vs generated guide + cue overlays).
6. Epic 9: zero-setup `Cook Now` flow (no saved recipe required) with <=2 tap live-session entry.
7. Epic 7: full-device UX QA on at least one iOS and one Android test device.

---

## Epic Summary

| # | Epic | Tasks | Prerequisites | Owner Hint |
|---|------|-------|---------------|------------|
| 1 | [Infrastructure & Platform Foundation](./epic-1-infrastructure.md) | 9 | None | Engineer D (Infra) |
| 2 | [Recipe Management & Data Layer](./epic-2-recipes.md) | 8 | Epic 1 | Engineer B (Backend) + Engineer A (Mobile) |
| 3 | [Fridge/Pantry Scan & Recipe Suggestions](./epic-3-scan-suggestions.md) | 10 | Epic 1, Epic 2 | Engineer A + B + C |
| 4 | [Live Cooking Session & Voice Loop](./epic-4-live-session.md) | 11 | Epic 1, Epic 2 | Engineer A + C |
| 5 | [Process Management, Timers & Concurrency](./epic-5-process-timers.md) | 8 | Epic 4 | Engineer A + C |
| 6 | [Vision, Visual Guides, Taste & Recovery](./epic-6-vision-taste-recovery.md) | 10 | Epic 4 | Engineer A + C |
| 7 | [Post-Session, Observability & Demo](./epic-7-post-session-demo.md) | 12 | All epics | All engineers |
| 8 | [Mobile App Foundation & UX Integration](./epic-8-mobile-app-foundation.md) | 15 | Epic 1 (start), integrates Epic 2-6 | Engineer A (Mobile Lead) + support |
| 9 | [Zero-Setup \"Seasoned Chef Buddy\" Mode](./epic-9-zero-setup-chef-buddy.md) | 10 | Epic 4, Epic 8 | Engineer A + C + B |

---

## Project Structure (Target)

```
ratatouille/
├── backend/
│   ├── app/
│   │   ├── main.py                  # FastAPI app, middleware, router mount
│   │   ├── config.py                # Environment config, GCP project settings
│   │   ├── auth/
│   │   │   └── firebase.py          # Token verification dependency
│   │   ├── routers/
│   │   │   ├── recipes.py           # Epic 2 endpoints
│   │   │   ├── inventory.py         # Epic 3 endpoints
│   │   │   ├── sessions.py          # Epic 4 endpoints
│   │   │   └── live.py              # Epic 4 WebSocket endpoint
│   │   ├── agents/
│   │   │   ├── orchestrator.py      # SessionOrchestrator (ADK)
│   │   │   ├── vision.py            # VisionAssessor (ADK)
│   │   │   ├── inventory.py         # InventoryVisionExtractor (ADK)
│   │   │   ├── suggester.py         # RecipeSuggester (ADK)
│   │   │   ├── guide_image.py       # GuideImageGenerator (ADK)
│   │   │   ├── process_manager.py   # ProcessManager (ADK)
│   │   │   ├── taste.py             # TasteCoach (ADK)
│   │   │   └── recovery.py          # RecoveryGuide (ADK)
│   │   ├── services/
│   │   │   ├── firestore.py         # Firestore client + CRUD helpers
│   │   │   ├── storage.py           # GCS client + upload/signed-URL helpers
│   │   │   └── gemini.py            # Vertex AI client initialization
│   │   └── models/
│   │       ├── recipe.py            # Pydantic models for recipes
│   │       ├── session.py           # Pydantic models for sessions
│   │       ├── inventory.py         # Pydantic models for scans
│   │       └── process.py           # Pydantic models for processes
│   ├── Dockerfile
│   ├── requirements.txt
│   └── cloudbuild.yaml
├── mobile/                          # Flutter app (first-class scope with UX acceptance in each epic)
│   ├── lib/
│   │   ├── app/                     # app shell, routing, theming
│   │   ├── core/                    # networking, auth, ws, error handling
│   │   ├── features/
│   │   │   ├── scan/                # fridge/pantry scan flow
│   │   │   ├── suggestions/         # dual-lane recipe suggestions
│   │   │   ├── live_session/        # live cooking UI + process bar
│   │   │   ├── vision_guide/        # side-by-side visual guide UX
│   │   │   └── post_session/        # completion + wind-down
│   │   └── shared/                  # reusable widgets/components
│   ├── test/                        # widget/integration tests
│   └── integration_test/            # end-to-end backend-connected tests
├── epics/                           # This folder
├── RATATOUILLE_HACKATHON_PRD.md
└── GOOGLE_CLOUD_TECH_GUIDE.md
```

---

## Key Conventions

1. **Async everywhere** — Use `AsyncClient` for Firestore, `async def` for all route handlers, `aio` for Gemini Live.
2. **Pydantic models** — All request/response bodies defined as Pydantic v2 models in `app/models/`.
3. **Auth on every endpoint** — `Depends(get_current_user)` on all protected routes.
4. **GCS URIs** — Always pass `gs://` URIs to Gemini, never download-and-reupload.
5. **Error responses** — Use FastAPI `HTTPException` with structured detail messages.
6. **Agent state** — Use ADK `ToolContext.state` for inter-tool communication within agents.
7. **No hardcoded project IDs** — All GCP identifiers come from `app/config.py` via environment variables.
8. **Async Gemini calls** — Use `gemini_client.aio` or `asyncio.to_thread(...)` wrappers to avoid blocking the event loop.
9. **WebSocket auth required** — Validate Firebase ID token before processing any live event.
10. **Mobile UX budgets** — Screen transition <250ms where feasible; visible loading states for operations >400ms.
11. **Mobile-backend contract tests** — Every critical endpoint/WS event used by mobile must have a tested client contract.
