import pytest
from pydantic import ValidationError

from app.models.ws_events import IncomingWsEvent


def test_valid_voice_query():
    event = IncomingWsEvent(type="voice_query", text="How long to boil?")
    assert event.type == "voice_query"


def test_invalid_event_type():
    with pytest.raises(ValidationError):
        IncomingWsEvent(type="invalid_type_xyz", text="")


def test_step_complete_requires_step():
    event = IncomingWsEvent(type="step_complete", step=3)
    assert event.step == 3


def test_valid_browse_start():
    event = IncomingWsEvent(type="browse_start", source="fridge")
    assert event.source == "fridge"


def test_valid_add_timer():
    event = IncomingWsEvent(type="add_timer", name="Boil pasta", duration_minutes=10.0)
    assert event.duration_minutes == 10.0


def test_valid_auth():
    event = IncomingWsEvent(type="auth", token="some_token")
    assert event.token == "some_token"


def test_valid_ping():
    event = IncomingWsEvent(type="ping")
    assert event.type == "ping"
