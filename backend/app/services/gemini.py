from google import genai

from app.config import settings

# Model constants — use these everywhere, never hardcode model strings
MODEL_FLASH = "gemini-3-flash-preview"
MODEL_LIVE = "gemini-live-2.5-flash-native-audio"
MODEL_IMAGE_GEN = "gemini-3-pro-image-preview"
MODEL_PRO = "gemini-3.1-pro-preview"  # Only for high-complexity reasoning escalation

_gemini_client = None


def get_gemini_client() -> genai.Client:
    global _gemini_client
    if _gemini_client is None:
        _gemini_client = genai.Client(
            vertexai=True,
            project=settings.gcp_project_id,
            location=settings.gcp_region,
        )
    return _gemini_client


class _LazyClient:
    def __getattr__(self, name):
        return getattr(get_gemini_client(), name)

gemini_client = _LazyClient()
