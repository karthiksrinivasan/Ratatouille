import time

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
import firebase_admin

from app.config import settings
from app.services.logging import logger, setup_logging

# Configure structured logging before anything else
setup_logging()

app = FastAPI(title="Ratatouille API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Lock down post-hackathon
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def log_request(request: Request, call_next):
    """Log every HTTP request with method, path, status, and latency."""
    start = time.time()
    response = await call_next(request)
    latency_ms = (time.time() - start) * 1000

    # Skip noisy health checks from load balancers
    if request.url.path != "/health":
        logger.info(
            f"{request.method} {request.url.path} {response.status_code}",
            extra={
                "endpoint": request.url.path,
                "latency_ms": round(latency_ms, 2),
                "status_code": response.status_code,
            },
        )
    return response


# Initialize Firebase Admin SDK once
_firebase_opts = {}
if settings.firebase_project_id:
    _firebase_opts["projectId"] = settings.firebase_project_id
firebase_admin.initialize_app(options=_firebase_opts)


@app.get("/health")
async def health():
    return {"status": "ok"}


# Internal metrics endpoint (admin only)
from app.auth.firebase import require_admin
from app.services.metrics import metrics


@app.get("/internal/metrics", dependencies=[Depends(require_admin)])
async def get_metrics():
    """Return in-memory metrics summary. Admin-only, disabled in production unless explicitly enabled."""
    if settings.environment == "production" and not settings.enable_internal_metrics:
        raise HTTPException(404, "Not found")
    return metrics.get_summary()


# Router mounts (added as epics are completed)
from app.routers import recipes

app.include_router(recipes.router, prefix="/v1", tags=["recipes"])

from app.routers import inventory

app.include_router(inventory.router, prefix="/v1", tags=["inventory"])

from app.routers import sessions, live, vision

app.include_router(sessions.router, prefix="/v1", tags=["sessions"])
app.include_router(live.router, prefix="/v1", tags=["live"])
app.include_router(vision.router, prefix="/v1", tags=["vision"])
