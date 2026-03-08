from datetime import datetime
from typing import Optional
import uuid

from pydantic import BaseModel, Field


class DetectedIngredient(BaseModel):
    name: str  # e.g., "red bell pepper"
    name_normalized: str  # e.g., "red bell pepper"
    confidence: float  # 0.0 - 1.0
    source_image_index: int  # Which uploaded image it was spotted in


class InventoryScanCreate(BaseModel):
    source: str  # "fridge" | "pantry"


class InventoryScan(BaseModel):
    """Firestore: inventory_scans/{scan_id}"""

    scan_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    uid: str
    source: str
    capture_mode: str = "images"  # images | video
    image_uris: list[str] = Field(default_factory=list)
    detected_ingredients: list[DetectedIngredient] = Field(default_factory=list)
    confidence_map: dict[str, float] = Field(default_factory=dict)
    confirmed_ingredients: list[str] = Field(default_factory=list)
    status: str = "pending"  # pending | detected | confirmed
    created_at: datetime = Field(default_factory=datetime.utcnow)


class IngredientConfirmation(BaseModel):
    confirmed_ingredients: list[str]  # User-edited final list


class RecipeSuggestion(BaseModel):
    """Firestore: inventory_scans/{scan_id}/suggestions/{suggestion_id}"""

    suggestion_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    source_type: str  # "saved_recipe" | "buddy_generated"
    recipe_id: Optional[str] = None
    title: str
    description: Optional[str] = None
    match_score: float  # 0.0 - 1.0
    matched_ingredients: list[str] = Field(default_factory=list)
    missing_ingredients: list[str] = Field(default_factory=list)
    estimated_time_min: Optional[int] = None
    difficulty: Optional[str] = None
    cuisine: Optional[str] = None
    source_label: str  # "Saved" | "Buddy"
    # Grounding & explainability (§7.11)
    explanation: str = ""
    grounding_sources: list[str] = Field(default_factory=list)
    assumptions: list[str] = Field(default_factory=list)


class StartSessionFromSuggestionRequest(BaseModel):
    suggestion_id: str
    mode_settings: dict = Field(default_factory=dict)
