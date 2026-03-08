from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
import uuid


class Ingredient(BaseModel):
    name: str  # e.g., "onion"
    name_normalized: str = ""  # e.g., "onion" (lowercase, singular)
    quantity: Optional[str] = None  # e.g., "2 medium"
    unit: Optional[str] = None  # e.g., "cups"
    preparation: Optional[str] = None  # e.g., "diced"
    category: Optional[str] = None  # e.g., "vegetable"


class RecipeStep(BaseModel):
    step_number: int
    instruction: str
    technique_tags: list[str] = Field(default_factory=list)  # e.g., ["saute", "deglaze"]
    duration_minutes: Optional[float] = None
    is_parallel: bool = False  # Can run alongside other steps
    reference_image_uri: Optional[str] = None  # gs:// URI for visual checkpoint
    guide_image_prompt: Optional[str] = None  # Prompt for generating target-state image


class RecipeCreate(BaseModel):
    title: str
    description: Optional[str] = None
    source_type: str = "manual"  # "manual" | "url_parsed" | "buddy_generated"
    source_url: Optional[str] = None
    servings: Optional[int] = None
    total_time_minutes: Optional[int] = None
    difficulty: Optional[str] = None  # "easy" | "medium" | "hard"
    cuisine: Optional[str] = None
    ingredients: list[Ingredient] = Field(default_factory=list)
    steps: list[RecipeStep] = Field(default_factory=list)


class RecipeFromURLRequest(BaseModel):
    url: str


class IngredientCheck(BaseModel):
    ingredient: str
    has_it: bool


class IngredientChecklist(BaseModel):
    recipe_id: str
    checks: list[IngredientCheck]
    all_available: bool = False  # True when all checks are True

    @property
    def missing(self) -> list[str]:
        return [c.ingredient for c in self.checks if not c.has_it]

    def model_post_init(self, __context) -> None:
        self.all_available = all(c.has_it for c in self.checks)


class Recipe(RecipeCreate):
    recipe_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    uid: str = ""  # Owner user ID
    technique_tags: list[str] = Field(default_factory=list)  # Aggregated from all steps
    ingredients_normalized: list[str] = Field(default_factory=list)  # Flat list for matching
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
