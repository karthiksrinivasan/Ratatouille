from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import firebase_admin

app = FastAPI(title="Ratatouille API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Lock down post-hackathon
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize Firebase Admin SDK once
firebase_admin.initialize_app()


@app.get("/health")
async def health():
    return {"status": "ok"}


# Router mounts (added as epics are completed)
from app.routers import recipes

app.include_router(recipes.router, prefix="/v1", tags=["recipes"])

from app.routers import inventory

app.include_router(inventory.router, prefix="/v1", tags=["inventory"])
# from app.routers import sessions, live
# app.include_router(sessions.router, prefix="/v1", tags=["sessions"])
