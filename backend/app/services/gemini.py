from google import genai

from app.config import settings

# Single client instance — always use Vertex AI backend for production
gemini_client = genai.Client(
    vertexai=True,
    project=settings.gcp_project_id,
    location=settings.gcp_region,
)

# Model constants — use these everywhere, never hardcode model strings
MODEL_FLASH = "gemini-2.5-flash"
MODEL_LIVE = "gemini-live-2.5-flash-preview-native-audio"
MODEL_IMAGE_GEN = "gemini-2.0-flash-preview-image-generation"
MODEL_PRO = "gemini-2.5-pro"  # Only for high-complexity reasoning escalation
