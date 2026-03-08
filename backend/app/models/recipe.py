from pydantic import BaseModel, Field


class RecipeStep(BaseModel):
    step_number: int
    instruction: str
    duration_minutes: float | None = None
    technique: str | None = None


class Recipe(BaseModel):
    """Firestore: recipes/{recipe_id}"""

    recipe_id: str | None = None
    title: str
    source_type: str = "manual"  # manual | url | photo
    parsed_steps: list[RecipeStep] = Field(default_factory=list)
    technique_tags: list[str] = Field(default_factory=list)
    ingredients_normalized: list[str] = Field(default_factory=list)
    reference_image_uris: list[str] = Field(default_factory=list)
    guide_image_prompts: list[str] = Field(default_factory=list)
    servings: int | None = None
    estimated_time_min: int | None = None
    difficulty: str | None = None
