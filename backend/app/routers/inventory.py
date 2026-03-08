"""Inventory scan & recipe suggestion endpoints (Epic 3)."""

import json
import re
import uuid

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from google.cloud import firestore
from google.genai import types

from app.auth.firebase import get_current_user
from app.models.inventory import IngredientConfirmation
from app.services.firestore import db
from app.services.gemini import MODEL_FLASH, gemini_client
from app.services.ingredients import normalize_ingredient
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


async def extract_ingredients_from_images(
    image_uris: list[str], source: str
) -> list[dict]:
    """Use Gemini Flash to detect ingredients from fridge/pantry images."""
    parts = []
    for uri in image_uris:
        parts.append(types.Part.from_uri(file_uri=uri, mime_type="image/jpeg"))

    parts.append(
        f"""Analyze these {source} images and identify all visible food ingredients.

For each ingredient, provide:
- name: common ingredient name (e.g., "red bell pepper", "whole milk", "cheddar cheese")
- confidence: float 0.0-1.0 indicating how certain you are of the identification
- source_image_index: which image (0-indexed) the ingredient is most visible in

Rules:
- Only identify actual food ingredients, not containers, utensils, or non-food items
- If an item is partially obscured, lower the confidence
- If you can see a label, use the label name
- Provide confidence >= 0.8 only when clearly visible and identifiable
- Provide confidence 0.5-0.79 when partially visible or ambiguous
- Provide confidence < 0.5 when guessing from context

Return ONLY a JSON array of objects with the fields above."""
    )

    response = await gemini_client.aio.models.generate_content(
        model=MODEL_FLASH,
        contents=parts,
    )

    try:
        ingredients = json.loads(response.text)
    except json.JSONDecodeError:
        match = re.search(r"```(?:json)?\s*([\s\S]*?)```", response.text)
        if match:
            ingredients = json.loads(match.group(1))
        else:
            return []

    return ingredients


@router.post("/inventory-scans/{scan_id}/detect")
async def detect_ingredients(
    scan_id: str,
    user: dict = Depends(get_current_user),
):
    """Process uploaded images through Gemini Flash to detect ingredients."""
    doc = await db.collection("inventory_scans").document(scan_id).get()
    if not doc.exists:
        raise HTTPException(404, "Scan not found")
    scan = doc.to_dict()
    if scan["uid"] != user["uid"]:
        raise HTTPException(403, "Not your scan")

    raw_ingredients = await extract_ingredients_from_images(
        scan["image_uris"], scan["source"]
    )

    detected = []
    confidence_map = {}
    for item in raw_ingredients:
        name = item.get("name", "")
        norm = normalize_ingredient(name)
        confidence = min(max(item.get("confidence", 0.5), 0.0), 1.0)
        detected.append(
            {
                "name": name,
                "name_normalized": norm,
                "confidence": confidence,
                "source_image_index": item.get("source_image_index", 0),
            }
        )
        confidence_map[norm] = confidence

    detected.sort(key=lambda x: x["confidence"], reverse=True)

    await db.collection("inventory_scans").document(scan_id).update(
        {
            "detected_ingredients": detected,
            "confidence_map": confidence_map,
            "status": "detected",
        }
    )

    return {
        "scan_id": scan_id,
        "detected_ingredients": detected,
        "status": "detected",
        "low_confidence_count": sum(1 for d in detected if d["confidence"] < 0.5),
    }


@router.post("/inventory-scans/{scan_id}/confirm-ingredients")
async def confirm_ingredients(
    scan_id: str,
    body: IngredientConfirmation,
    user: dict = Depends(get_current_user),
):
    """User reviews detected ingredients, adds/removes items, confirms final list."""
    doc = await db.collection("inventory_scans").document(scan_id).get()
    if not doc.exists:
        raise HTTPException(404, "Scan not found")
    scan = doc.to_dict()
    if scan["uid"] != user["uid"]:
        raise HTTPException(403, "Not your scan")
    if scan["status"] not in ("detected", "confirmed"):
        raise HTTPException(400, "Scan must be in 'detected' state first")

    confirmed = [normalize_ingredient(i) for i in body.confirmed_ingredients]

    await db.collection("inventory_scans").document(scan_id).update(
        {
            "confirmed_ingredients": confirmed,
            "status": "confirmed",
        }
    )

    return {
        "scan_id": scan_id,
        "confirmed_ingredients": confirmed,
        "status": "confirmed",
    }
