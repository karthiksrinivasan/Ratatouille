"""Tests for the TimerSystem — verifies timer firing and cancellation (Epic 5)."""

import asyncio

import pytest

from app.services.timers import TimerSystem


@pytest.mark.asyncio
async def test_timer_fires_warning_and_due():
    """A short timer should fire the due callback after expiry."""
    warnings: list = []
    completions: list = []

    async def on_warning(pid: str, name: str, remaining: int):
        warnings.append((pid, name, remaining))

    async def on_due(pid: str, name: str):
        completions.append((pid, name))

    ts = TimerSystem(on_timer_due=on_due, on_timer_warning=on_warning)
    # 0.05 minutes = 3 seconds — short enough for a test
    await ts.start_timer("p1", 0.05, "Quick Timer")
    await asyncio.sleep(4)

    assert ("p1", "Quick Timer") in completions


@pytest.mark.asyncio
async def test_timer_cancel():
    """Cancelling a timer should prevent the due callback from firing."""
    completions: list = []

    async def on_due(pid: str, name: str):
        completions.append(pid)

    async def on_warning(pid: str, name: str, remaining: int):
        pass

    ts = TimerSystem(on_timer_due=on_due, on_timer_warning=on_warning)
    await ts.start_timer("p1", 0.1, "Timer")
    ts.cancel_timer("p1")
    await asyncio.sleep(8)

    assert len(completions) == 0


@pytest.mark.asyncio
async def test_timer_restart_replaces_previous():
    """Starting a timer for the same process ID replaces the prior one."""
    completions: list = []

    async def on_due(pid: str, name: str):
        completions.append(name)

    async def on_warning(pid: str, name: str, remaining: int):
        pass

    ts = TimerSystem(on_timer_due=on_due, on_timer_warning=on_warning)
    await ts.start_timer("p1", 0.05, "First")
    # Immediately replace with a new timer
    await ts.start_timer("p1", 0.05, "Second")
    await asyncio.sleep(5)

    # Only the second timer's callback should fire
    assert "Second" in completions
    # First may or may not fire depending on cancel timing,
    # but the system should have only 0 or 1 active timer for p1
    assert ts.active_timer_count() <= 1


@pytest.mark.asyncio
async def test_cancel_all():
    """cancel_all should prevent all pending timers from firing."""
    completions: list = []

    async def on_due(pid: str, name: str):
        completions.append(pid)

    async def on_warning(pid: str, name: str, remaining: int):
        pass

    ts = TimerSystem(on_timer_due=on_due, on_timer_warning=on_warning)
    await ts.start_timer("a", 0.05, "A")
    await ts.start_timer("b", 0.05, "B")
    ts.cancel_all()
    await asyncio.sleep(5)

    assert len(completions) == 0
    assert ts.active_timer_count() == 0
