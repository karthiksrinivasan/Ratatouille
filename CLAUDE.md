# Ratatouille — Project Instructions for Claude

## Project Overview
Ratatouille is a live cooking companion app (mobile + backend). A hackathon MVP using Google Cloud services, Gemini AI, and Flutter.

## Architecture
- **Backend:** Python 3.11 + FastAPI on Cloud Run
- **Database:** Firestore (AsyncClient, Native mode)
- **Storage:** GCS — always pass `gs://` URIs to Gemini, never download-and-reupload
- **AI:** Gemini via Vertex AI, orchestrated with Google ADK
- **Auth:** Firebase Auth with server-side token verification
- **Mobile:** Flutter (cross-platform)

## Code Conventions
1. **Async everywhere** — Use `AsyncClient` for Firestore, `async def` for all route handlers, `aio` for Gemini Live.
2. **Pydantic v2 models** — All request/response bodies defined as Pydantic v2 models in `app/models/`.
3. **Auth on every endpoint** — `Depends(get_current_user)` on all protected routes.
4. **GCS URIs** — Always pass `gs://` URIs to Gemini, never raw URLs.
5. **Error responses** — Use FastAPI `HTTPException` with structured detail messages.
6. **Agent state** — Use ADK `ToolContext.state` for inter-tool communication within agents.
7. **No hardcoded project IDs** — All GCP identifiers come from `app/config.py` via environment variables.
8. **No extra dependencies** — Do not add packages beyond `requirements.txt` without documenting why.
9. **No structure changes** — Follow the project structure defined in `epics/index.md`. Do not reorganize.
10. **Simplest interpretation** — If a task is ambiguous, implement a robust, secure implementation that fits the product narrative.

## Project Structure
```
backend/
├── app/
│   ├── main.py                  # FastAPI app, middleware, router mount
│   ├── config.py                # Environment config
│   ├── auth/firebase.py         # Token verification dependency
│   ├── routers/                 # REST + WebSocket endpoints
│   ├── agents/                  # ADK agents
│   ├── services/                # Firestore, GCS, Gemini clients
│   └── models/                  # Pydantic models
├── Dockerfile
├── requirements.txt
└── cloudbuild.yaml
```

## Git Commit Convention
- One commit per task: `feat(epic-N): task N.M — short description`
- Validation fixes: `fix(epic-N): address validation findings`
- Cleanup: `chore(epic-N): final cleanup and wiring`
- Always stage specific files — never `git add -A` or `git add .`

## Key Reference Files
- `epics/index.md` — Architecture overview, dependency graph, conventions
- `RATATOUILLE_HACKATHON_PRD.md` — Product requirements
- `GOOGLE_CLOUD_TECH_GUIDE.md` — Implementation patterns for GCP services
- `epics/epic-N-*.md` — Individual epic specifications with tasks and acceptance criteria

## GCP Infrastructure Notes
- GCP commands (gcloud, gsutil) are for reference — create the code artifacts but note that infra provisioning is done separately.
- Model constants are defined in `app/services/gemini.py` — do not hardcode model strings elsewhere.

## Testing
- After implementing code, verify it imports correctly: `cd backend && python -c "from app.main import app"`
- Write basic tests where the epic calls for them.
