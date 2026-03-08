from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import firebase_admin
from firebase_admin import credentials

from app.config import settings

app = FastAPI(title="Ratatouille API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Lock down post-hackathon
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize Firebase Admin SDK once
_firebase_opts = {}
if settings.firebase_project_id:
    _firebase_opts["projectId"] = settings.firebase_project_id
firebase_admin.initialize_app(options=_firebase_opts)


@app.get("/health")
async def health():
    return {"status": "ok"}


# Router mounts (added as epics are completed)
from app.routers import recipes

app.include_router(recipes.router, prefix="/v1", tags=["recipes"])

from app.routers import inventory

app.include_router(inventory.router, prefix="/v1", tags=["inventory"])

from app.routers import sessions, live, vision

app.include_router(sessions.router, prefix="/v1", tags=["sessions"])
app.include_router(live.router, prefix="/v1", tags=["live"])
app.include_router(vision.router, prefix="/v1", tags=["vision"])
