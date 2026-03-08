"""Inventory scan & recipe suggestion endpoints (Epic 3)."""

import uuid

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from google.cloud import firestore

from app.auth.firebase import get_current_user
from app.services.firestore import db
from app.services.media import extract_keyframes_to_gcs
from app.services.storage import upload_bytes

router = APIRouter()


@router.post("/inventory-scans")
async def create_inventory_scan(
    source: str = Form(...),
    images: list[UploadFile] | None = File(default=None),
    video: UploadFile | None = File(default=None),
    user: dict = Depends(get_current_user),
):
    """Accept 2-6 fridge/pantry images or 1 short video, upload to GCS, create scan record."""
    images = images or []
    if source not in ("fridge", "pantry"):
        raise HTTPException(400, "source must be 'fridge' or 'pantry'")

    has_images = len(images) > 0
    has_video = video is not None
    if has_images == has_video:
        raise HTTPException(400, "Provide either 2-6 images or 1 short video")
    if has_images and not 2 <= len(images) <= 6:
        raise HTTPException(400, "Upload 2-6 images")

    scan_id = str(uuid.uuid4())
    uid = user["uid"]
    image_uris = []
    capture_mode = "images"

    if has_images:
        for i, image in enumerate(images):
            content = await image.read()
            content_type = image.content_type or "image/jpeg"
            path = f"inventory-scans/{uid}/{scan_id}/{i}.jpg"
            uri = upload_bytes(path, content, content_type)
            image_uris.append(uri)
    else:
        capture_mode = "video"
        if not (video.content_type or "").startswith("video/"):
            raise HTTPException(400, "video must be a valid video content type")
        video_bytes = await video.read()
        video_uri = upload_bytes(
            f"inventory-scans/{uid}/{scan_id}/raw.mp4",
            video_bytes,
            video.content_type or "video/mp4",
        )
        image_uris = await extract_keyframes_to_gcs(
            video_uri=video_uri,
            uid=uid,
            scan_id=scan_id,
            frame_count=3,
        )

    scan_data = {
        "scan_id": scan_id,
        "uid": uid,
        "source": source,
        "capture_mode": capture_mode,
        "image_uris": image_uris,
        "detected_ingredients": [],
        "confidence_map": {},
        "confirmed_ingredients": [],
        "status": "pending",
        "created_at": firestore.SERVER_TIMESTAMP,
    }
    await db.collection("inventory_scans").document(scan_id).set(scan_data)

    return {
        "scan_id": scan_id,
        "capture_mode": capture_mode,
        "image_count": len(image_uris),
        "status": "pending",
    }
