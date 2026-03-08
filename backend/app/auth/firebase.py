from fastapi import Header, HTTPException
from firebase_admin import auth


async def get_current_user(authorization: str = Header(...)) -> dict:
    """FastAPI dependency — extracts and verifies Firebase ID token.

    Returns the decoded token dict containing uid, email, etc.
    Use as: Depends(get_current_user) on all protected routes.
    """
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
