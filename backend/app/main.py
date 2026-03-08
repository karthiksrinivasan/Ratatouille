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
    checks = {}
    try:
        from app.services.firestore import db
        await db.collection("_health").document("check").get()
        checks["firestore"] = "ok"
    except Exception:
        checks["firestore"] = "error"

    try:
        from app.services.storage import bucket
        bucket.blob("_health/check.txt").exists()
        checks["gcs"] = "ok"
    except Exception:
        checks["gcs"] = "error"

    status = "ok" if all(v == "ok" for v in checks.values()) else "degraded"
    return {"status": status, "checks": checks}


@app.on_event("startup")
async def warmup():
    import asyncio

    async def _warmup_gemini():
        try:
            from app.services.gemini import gemini_client, MODEL_FLASH
            await gemini_client.aio.models.generate_content(
                model=MODEL_FLASH, contents="Hello"
            )
            logger.info("Gemini client warmed up")
        except Exception as e:
            logger.warning(f"Warmup call failed (non-critical): {e}")

    # Run warmup in background so the server starts accepting requests immediately
    asyncio.create_task(_warmup_gemini())


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

from app.routers import sessions, live, vision, users

app.include_router(sessions.router, prefix="/v1", tags=["sessions"])
app.include_router(live.router, prefix="/v1", tags=["live"])
app.include_router(vision.router, prefix="/v1", tags=["vision"])
app.include_router(users.router, prefix="/v1", tags=["users"])
