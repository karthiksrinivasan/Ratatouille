import pytest
from unittest.mock import AsyncMock, MagicMock, patch

from app.agents.live_audio import LiveAudioSession


@pytest.mark.asyncio
async def test_connect_sets_audio_modality():
    """LiveAudioSession.connect() must request AUDIO response modality."""
    session = LiveAudioSession(
        recipe={"title": "Test", "steps": [{"step_number": 1, "instruction": "Boil water"}]},
        session_state={"current_step": 1},
    )

    with patch("app.agents.live_audio.gemini_client") as mock_client:
        mock_live = AsyncMock()
        mock_client.aio.live.connect = mock_live
        mock_live.return_value = AsyncMock()

        await session.connect()

        mock_live.assert_called_once()
        call_kwargs = mock_live.call_args
        config = call_kwargs.kwargs.get("config") or call_kwargs[1].get("config")
        assert "AUDIO" in config.response_modalities


@pytest.mark.asyncio
async def test_send_audio_forwards_to_gemini():
    """send_audio should forward base64 audio to Gemini Live session."""
    session = LiveAudioSession(
        recipe={"title": "Test", "steps": []},
        session_state={"current_step": 1},
    )
    session.live_session = AsyncMock()

    import base64
    test_audio = base64.b64encode(b"test_pcm_data").decode()
    await session.send_audio(test_audio)

    session.live_session.send.assert_called_once()


@pytest.mark.asyncio
async def test_close_sends_turn_complete():
    """close() should send turn_complete before closing the session."""
    session = LiveAudioSession(
        recipe={"title": "Test", "steps": []},
        session_state={"current_step": 1},
    )
    mock_live = AsyncMock()
    session.live_session = mock_live

    await session.close()

    mock_live.send.assert_called_once()
    assert session.live_session is None
