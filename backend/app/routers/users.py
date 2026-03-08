from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.auth.firebase import get_current_user
from app.services.firestore import get_db

router = APIRouter()


class UserProfileResponse(BaseModel):
    uid: str
    display_name: Optional[str] = None
    email: Optional[str] = None
    preferences: dict = {}
    calibration_summary: dict = {}
    created_at: Optional[str] = None


class UserProfileUpdate(BaseModel):
    display_name: Optional[str] = None
    preferences: Optional[dict] = None


@router.get("/users/me", response_model=UserProfileResponse)
async def get_my_profile(user: dict = Depends(get_current_user)):
    """Get the current user's profile, creating it if it doesn't exist."""
    uid = user["uid"]
    db = get_db()
    doc_ref = db.collection("users").document(uid)
    doc = await doc_ref.get()

    if doc.exists:
        data = doc.to_dict()
        data["uid"] = uid
        if "created_at" in data and data["created_at"]:
            data["created_at"] = data["created_at"].isoformat()
        return UserProfileResponse(**data)

    # Auto-create profile on first access.
    now = datetime.now(timezone.utc)
    profile = {
        "display_name": user.get("name") or user.get("email", "").split("@")[0] or None,
        "email": user.get("email"),
        "preferences": {},
        "calibration_summary": {},
        "created_at": now,
    }
    await doc_ref.set(profile)
    profile["uid"] = uid
    profile["created_at"] = now.isoformat()
    return UserProfileResponse(**profile)


@router.put("/users/me", response_model=UserProfileResponse)
async def update_my_profile(
    body: UserProfileUpdate,
    user: dict = Depends(get_current_user),
):
    """Update the current user's profile."""
    uid = user["uid"]
    db = get_db()
    doc_ref = db.collection("users").document(uid)

    updates = {}
    if body.display_name is not None:
        updates["display_name"] = body.display_name
    if body.preferences is not None:
        updates["preferences"] = body.preferences

    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")

    doc = await doc_ref.get()
    if not doc.exists:
        # Create the profile first.
        now = datetime.now(timezone.utc)
        profile = {
            "display_name": body.display_name or user.get("email", "").split("@")[0],
            "email": user.get("email"),
            "preferences": body.preferences or {},
            "calibration_summary": {},
            "created_at": now,
        }
        await doc_ref.set(profile)
        profile["uid"] = uid
        profile["created_at"] = now.isoformat()
        return UserProfileResponse(**profile)

    await doc_ref.update(updates)
    updated = await doc_ref.get()
    data = updated.to_dict()
    data["uid"] = uid
    if "created_at" in data and data["created_at"]:
        data["created_at"] = data["created_at"].isoformat()
    return UserProfileResponse(**data)


@router.delete("/users/me")
async def delete_my_profile(user: dict = Depends(get_current_user)):
    """Delete the current user's profile and associated data."""
    uid = user["uid"]
    db = get_db()

    # Delete user memories subcollection.
    memories_ref = db.collection("users").document(uid).collection("memories")
    async for memory_doc in memories_ref.stream():
        await memory_doc.reference.delete()

    # Delete user profile document.
    await db.collection("users").document(uid).delete()

    return {"status": "deleted", "uid": uid}
