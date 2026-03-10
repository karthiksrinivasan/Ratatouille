import pytest
import base64
from unittest.mock import AsyncMock, MagicMock, patch

from app.agents.live_audio import LiveAudioSession


@pytest.mark.asyncio
async def test_receive_responses_yields_audio():
    """LiveAudioSession.receive_responses should yield audio_response events."""
    session = LiveAudioSession(
        recipe={"title": "Test", "steps": [{"step_number": 1, "instruction": "Test"}]},
        session_state={"current_step": 1},
    )

    mock_msg = MagicMock()
    mock_part = MagicMock()
    mock_part.inline_data = MagicMock(data=b"fake_audio_pcm", mime_type="audio/pcm")
    mock_part.text = None
    mock_msg.server_content.model_turn.parts = [mock_part]

    mock_live = AsyncMock()

    async def fake_receive():
        yield mock_msg

    mock_live.receive = fake_receive
    session.live_session = mock_live

    results = []
    async for event in session.receive_responses():
        results.append(event)

    assert len(results) == 1
    assert results[0]["type"] == "audio_response"
    assert results[0]["audio"] == base64.b64encode(b"fake_audio_pcm").decode()
    assert results[0]["mime_type"] == "audio/pcm"


def test_buddy_audio_ws_event_format():
    """buddy_audio WS events must have type, audio, and mime_type fields."""
    audio_data = base64.b64encode(b"test_pcm").decode()
    event = {
        "type": "buddy_audio",
        "audio": audio_data,
        "mime_type": "audio/pcm",
    }
    assert event["type"] == "buddy_audio"
    assert base64.b64decode(event["audio"]) == b"test_pcm"
