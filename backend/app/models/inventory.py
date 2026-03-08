from datetime import datetime

from pydantic import BaseModel, Field


class InventoryScan(BaseModel):
    """Firestore: inventory_scans/{scan_id}"""

    scan_id: str | None = None
    uid: str
    source: str = "photo"  # photo | manual
    image_uris: list[str] = Field(default_factory=list)
    detected_ingredients: list[str] = Field(default_factory=list)
    confidence_map: dict[str, float] = Field(default_factory=dict)
    confirmed_ingredients: list[str] = Field(default_factory=list)
    created_at: datetime | None = None


class RecipeSuggestion(BaseModel):
    """Firestore: inventory_scans/{scan_id}/suggestions/{suggestion_id}"""

    suggestion_id: str | None = None
    source_type: str = "inventory_match"
    recipe_id: str | None = None
    title: str
    match_score: float = 0.0
    missing_ingredients: list[str] = Field(default_factory=list)
    estimated_time_min: int | None = None
    difficulty: str | None = None
