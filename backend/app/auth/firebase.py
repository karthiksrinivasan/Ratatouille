import logging
from typing import Optional

from fastapi import Header, HTTPException
from firebase_admin import auth

from app.config import settings

logger = logging.getLogger(__name__)


async def get_current_user(authorization: Optional[str] = Header(None)) -> dict:
    """FastAPI dependency — extracts and verifies Firebase ID token.

    Returns the decoded token dict containing uid, email, etc.
    Use as: Depends(get_current_user) on all protected routes.

    In development mode, if no Authorization header is provided,
    returns a stub user to allow local testing without Firebase Auth.
    """
    # Dev-mode bypass: allow unauthenticated requests locally.
    if not authorization:
        if settings.environment == "development":
            logger.warning("No auth header — using dev stub user")
            return {"uid": "dev-local-user", "email": "dev@localhost"}
        raise HTTPException(status_code=401, detail="Authorization header required")

    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization header")
    token = authorization[7:]
    try:
        decoded = auth.verify_id_token(token)
        return decoded
    except auth.InvalidIdTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")
    except auth.ExpiredIdTokenError:
        raise HTTPException(status_code=401, detail="Token expired")
    except Exception:
        raise HTTPException(status_code=401, detail="Authentication failed")
