"""Tests for Epic 5 — Process Management, Timers & Concurrency."""

import asyncio
import os
import json
import pytest

os.environ.setdefault("GCP_PROJECT_ID", "test-project")
os.environ.setdefault("GCS_BUCKET_NAME", "test-bucket")
os.environ.setdefault("ENVIRONMENT", "testing")

from app.models.process import Process, ProcessCreate, ProcessBarState


# ---------------------------------------------------------------------------
# 5.1 — Process Models
# ---------------------------------------------------------------------------


class TestProcessModels:
    """Pydantic model validation for process models."""

    def test_process_create(self):
        pc = ProcessCreate(name="Boil water", step_number=1, duration_minutes=8.0)
        assert pc.name == "Boil water"
        assert pc.step_number == 1
        assert pc.duration_minutes == 8.0
        assert pc.is_parallel is False

    def test_process_create_parallel(self):
        pc = ProcessCreate(name="Slice garlic", step_number=2, is_parallel=True)
        assert pc.is_parallel is True
        assert pc.duration_minutes is None

    def test_process_defaults(self):
        p = Process(session_id="s1", name="Test", step_number=1)
        assert p.process_id  # auto-generated UUID
        assert p.priority == "P2"
        assert p.state == "pending"
        assert p.started_at is None
        assert p.due_at is None
        assert p.buddy_managed is False
        assert p.is_parallel is False

    def test_process_all_fields(self):
        from datetime import datetime
        now = datetime.utcnow()
        p = Process(
            process_id="pid-1",
            session_id="s1",
            name="Cook pasta",
            step_number=3,
            priority="P1",
            state="countdown",
            started_at=now,
            due_at=now,
            duration_minutes=9.0,
            buddy_managed=False,
            is_parallel=True,
        )
        assert p.priority == "P1"
        assert p.state == "countdown"
        assert p.duration_minutes == 9.0

    def test_process_bar_state(self):
        p1 = Process(session_id="s1", name="A", step_number=1, state="countdown")
        p2 = Process(session_id="s1", name="B", step_number=2, state="needs_attention")
        bar = ProcessBarState(
            processes=[p1, p2],
            active_count=2,
            attention_needed=[p2.process_id],
            next_due=p1,
        )
        assert bar.active_count == 2
        assert len(bar.attention_needed) == 1
        assert bar.next_due.name == "A"

    def test_process_bar_state_empty(self):
        bar = ProcessBarState(
            processes=[],
            active_count=0,
            attention_needed=[],
        )
        assert bar.next_due is None


# ---------------------------------------------------------------------------
# 5.1 — Process Manager Agent tool functions
# ---------------------------------------------------------------------------


class _FakeToolContext:
    """Minimal mock for ToolContext with state dict."""

    def __init__(self, state: dict):
        self.state = state


class TestProcessManagerTools:
    """Test ADK tool functions for process management."""

    def test_create_process(self):
        from app.agents.process_manager import create_process
        ctx = _FakeToolContext({"session_id": "s1", "processes": []})
        result = json.loads(create_process(
            name="Boil water",
            step_number=1,
            duration_minutes=8.0,
            priority="P2",
            is_parallel=False,
            tool_context=ctx,
        ))
        assert result["status"] == "created"
        assert "process_id" in result
        assert len(ctx.state["processes"]) == 1
        assert ctx.state["processes"][0]["name"] == "Boil water"

    def test_start_process_with_duration(self):
        from app.agents.process_manager import create_process, start_process
        ctx = _FakeToolContext({"session_id": "s1", "processes": []})
        created = json.loads(create_process(
            name="Boil water", step_number=1,
            duration_minutes=8.0, priority="P2", is_parallel=False,
            tool_context=ctx,
        ))
        pid = created["process_id"]

        result = json.loads(start_process(pid, ctx))
        assert result["state"] == "countdown"
        assert result["due_at"] is not None

    def test_start_process_without_duration(self):
        from app.agents.process_manager import create_process, start_process
        ctx = _FakeToolContext({"session_id": "s1", "processes": []})
        created = json.loads(create_process(
            name="Slice garlic", step_number=2,
            duration_minutes=0, priority="P2", is_parallel=True,
            tool_context=ctx,
        ))
        pid = created["process_id"]

        result = json.loads(start_process(pid, ctx))
        assert result["state"] == "in_progress"
        assert result["due_at"] is None

    def test_start_process_not_found(self):
        from app.agents.process_manager import start_process
        ctx = _FakeToolContext({"session_id": "s1", "processes": []})
        result = json.loads(start_process("nonexistent", ctx))
        assert "error" in result

    def test_complete_process(self):
        from app.agents.process_manager import create_process, complete_process
        ctx = _FakeToolContext({"session_id": "s1", "processes": []})
        created = json.loads(create_process(
            name="Test", step_number=1,
            duration_minutes=1.0, priority="P2", is_parallel=False,
            tool_context=ctx,
        ))
        pid = created["process_id"]

        result = json.loads(complete_process(pid, ctx))
        assert result["state"] == "complete"
        assert ctx.state["processes"][0]["state"] == "complete"

    def test_complete_process_not_found(self):
        from app.agents.process_manager import complete_process
        ctx = _FakeToolContext({"session_id": "s1", "processes": []})
        result = json.loads(complete_process("nonexistent", ctx))
        assert "error" in result

    def test_get_active_processes_sorted(self):
        from app.agents.process_manager import get_active_processes
        ctx = _FakeToolContext({
            "session_id": "s1",
            "processes": [
                {"process_id": "a", "priority": "P3", "state": "in_progress", "due_at": None},
                {"process_id": "b", "priority": "P0", "state": "needs_attention", "due_at": "2024-01-01T00:00:00"},
                {"process_id": "c", "priority": "P2", "state": "countdown", "due_at": "2024-01-01T00:05:00"},
                {"process_id": "d", "priority": "P2", "state": "complete", "due_at": None},  # excluded
                {"process_id": "e", "priority": "P4", "state": "passive", "due_at": None},  # excluded
            ],
        })
        result = json.loads(get_active_processes(ctx))
        assert len(result) == 3
        assert result[0]["process_id"] == "b"  # P0 first
        assert result[1]["process_id"] == "c"  # P2
        assert result[2]["process_id"] == "a"  # P3

    def test_flag_needs_attention(self):
        from app.agents.process_manager import flag_needs_attention
        ctx = _FakeToolContext({
            "session_id": "s1",
            "processes": [
                {"process_id": "a", "state": "countdown"},
            ],
        })
        result = json.loads(flag_needs_attention("a", ctx))
        assert result["state"] == "needs_attention"
        assert ctx.state["processes"][0]["state"] == "needs_attention"

    def test_flag_needs_attention_not_found(self):
        from app.agents.process_manager import flag_needs_attention
        ctx = _FakeToolContext({"session_id": "s1", "processes": []})
        result = json.loads(flag_needs_attention("nope", ctx))
        assert "error" in result

    def test_delegate_to_buddy(self):
        from app.agents.process_manager import delegate_to_buddy
        ctx = _FakeToolContext({
            "session_id": "s1",
            "processes": [
                {"process_id": "a", "state": "in_progress", "buddy_managed": False},
            ],
        })
        result = json.loads(delegate_to_buddy("a", ctx))
        assert result["buddy_managed"] is True
        assert ctx.state["processes"][0]["state"] == "passive"
        assert ctx.state["processes"][0]["buddy_managed"] is True

    def test_delegate_to_buddy_not_found(self):
        from app.agents.process_manager import delegate_to_buddy
        ctx = _FakeToolContext({"session_id": "s1", "processes": []})
        result = json.loads(delegate_to_buddy("nope", ctx))
        assert "error" in result

    def test_multiple_processes_lifecycle(self):
        """Full lifecycle: create → start → complete multiple processes."""
        from app.agents.process_manager import (
            create_process, start_process, complete_process, get_active_processes,
        )
        ctx = _FakeToolContext({"session_id": "s1", "processes": []})

        # Create two processes
        p1 = json.loads(create_process("Boil water", 1, 8.0, "P2", False, ctx))
        p2 = json.loads(create_process("Slice garlic", 2, 0, "P2", True, ctx))
        assert len(ctx.state["processes"]) == 2

        # Start both
        json.loads(start_process(p1["process_id"], ctx))
        json.loads(start_process(p2["process_id"], ctx))

        # Both active
        active = json.loads(get_active_processes(ctx))
        assert len(active) == 2

        # Complete one
        json.loads(complete_process(p1["process_id"], ctx))
        active = json.loads(get_active_processes(ctx))
        assert len(active) == 1
        assert active[0]["process_id"] == p2["process_id"]


# ---------------------------------------------------------------------------
# 5.2 — Timer System
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
class TestTimerSystem:
    """Test async timer system for cooking processes."""

    async def test_short_timer_fires_due(self):
        """Timer <= 2min fires due callback without warning."""
        from app.services.timers import TimerSystem
        due_events = []
        warning_events = []

        async def on_due(pid, name):
            due_events.append((pid, name))

        async def on_warn(pid, name, remaining):
            warning_events.append((pid, name, remaining))

        ts = TimerSystem(on_timer_due=on_due, on_timer_warning=on_warn)
        await ts.start_timer("p1", 0.01, "Quick task")  # 0.6 seconds
        await asyncio.sleep(1.5)

        assert len(due_events) == 1
        assert due_events[0] == ("p1", "Quick task")
        assert len(warning_events) == 0  # no warning for short timer

    async def test_cancel_timer(self):
        from app.services.timers import TimerSystem
        due_events = []

        async def on_due(pid, name):
            due_events.append(pid)

        async def on_warn(pid, name, remaining):
            pass

        ts = TimerSystem(on_timer_due=on_due, on_timer_warning=on_warn)
        await ts.start_timer("p1", 0.05, "Cancelled task")
        assert ts.has_timer("p1")

        ts.cancel_timer("p1")
        assert not ts.has_timer("p1")

        await asyncio.sleep(4)
        assert len(due_events) == 0  # never fired

    async def test_cancel_all(self):
        from app.services.timers import TimerSystem

        async def noop(pid, name):
            pass

        async def noop_warn(pid, name, remaining):
            pass

        ts = TimerSystem(on_timer_due=noop, on_timer_warning=noop_warn)
        await ts.start_timer("p1", 1.0, "A")
        await ts.start_timer("p2", 1.0, "B")
        assert ts.active_timer_count() == 2

        ts.cancel_all()
        assert ts.active_timer_count() == 0

    async def test_multiple_concurrent_timers(self):
        from app.services.timers import TimerSystem
        due_events = []

        async def on_due(pid, name):
            due_events.append(pid)

        async def on_warn(pid, name, remaining):
            pass

        ts = TimerSystem(on_timer_due=on_due, on_timer_warning=on_warn)
        await ts.start_timer("p1", 0.01, "A")  # 0.6s
        await ts.start_timer("p2", 0.02, "B")  # 1.2s
        assert ts.active_timer_count() == 2

        await asyncio.sleep(2.5)
        assert len(due_events) == 2
        assert "p1" in due_events
        assert "p2" in due_events

    async def test_restart_timer_replaces_existing(self):
        from app.services.timers import TimerSystem
        due_events = []

        async def on_due(pid, name):
            due_events.append(name)

        async def on_warn(pid, name, remaining):
            pass

        ts = TimerSystem(on_timer_due=on_due, on_timer_warning=on_warn)
        await ts.start_timer("p1", 10.0, "Old")  # long timer
        await ts.start_timer("p1", 0.01, "New")   # replaced with short timer

        assert ts.active_timer_count() == 1
        await asyncio.sleep(1.5)
        assert due_events == ["New"]

    async def test_cancel_nonexistent_is_safe(self):
        from app.services.timers import TimerSystem

        async def noop(pid, name):
            pass

        async def noop_warn(pid, name, remaining):
            pass

        ts = TimerSystem(on_timer_due=noop, on_timer_warning=noop_warn)
        ts.cancel_timer("nonexistent")  # should not raise


# ---------------------------------------------------------------------------
# 5.3 — Process Bar State Push
# ---------------------------------------------------------------------------


class _FakeWebSocket:
    """Mock WebSocket for testing send/receive."""

    def __init__(self, receive_data=None):
        self.sent: list[dict] = []
        self._receive_data = receive_data

    async def send_json(self, data: dict):
        self.sent.append(data)

    async def receive_json(self) -> dict:
        if self._receive_data is not None:
            return self._receive_data
        # Simulate timeout by waiting forever
        await asyncio.sleep(9999)


@pytest.mark.asyncio
class TestProcessBarStatePush:
    """Test process bar state building and push."""

    async def test_build_bar_state_empty(self):
        from app.services.processes import build_process_bar_state
        bar = await build_process_bar_state([])
        assert bar["type"] == "process_update"
        assert bar["active_count"] == 0
        assert bar["attention_needed"] == []
        assert bar["next_due"] is None

    async def test_build_bar_state_filters_complete(self):
        from app.services.processes import build_process_bar_state
        processes = [
            {"process_id": "a", "state": "countdown", "priority": "P2", "due_at": "2024-01-01T00:10:00"},
            {"process_id": "b", "state": "complete", "priority": "P2", "due_at": None},
        ]
        bar = await build_process_bar_state(processes)
        assert bar["active_count"] == 1
        assert bar["processes"][0]["process_id"] == "a"

    async def test_build_bar_state_attention_needed(self):
        from app.services.processes import build_process_bar_state
        processes = [
            {"process_id": "a", "state": "needs_attention", "priority": "P1"},
            {"process_id": "b", "state": "in_progress", "priority": "P2"},
        ]
        bar = await build_process_bar_state(processes)
        assert bar["attention_needed"] == ["a"]

    async def test_build_bar_state_next_due(self):
        from app.services.processes import build_process_bar_state
        processes = [
            {"process_id": "a", "state": "countdown", "priority": "P2", "due_at": "2024-01-01T00:15:00"},
            {"process_id": "b", "state": "countdown", "priority": "P2", "due_at": "2024-01-01T00:10:00"},
        ]
        bar = await build_process_bar_state(processes)
        assert bar["next_due"]["process_id"] == "b"  # earlier due_at

    async def test_build_bar_state_sorted_by_priority(self):
        from app.services.processes import build_process_bar_state
        processes = [
            {"process_id": "a", "state": "in_progress", "priority": "P3"},
            {"process_id": "b", "state": "needs_attention", "priority": "P0"},
            {"process_id": "c", "state": "countdown", "priority": "P2", "due_at": "2024-01-01T00:10:00"},
        ]
        bar = await build_process_bar_state(processes)
        assert [p["process_id"] for p in bar["processes"]] == ["b", "c", "a"]

    async def test_push_process_bar(self):
        from app.services.processes import push_process_bar
        ws = _FakeWebSocket()
        processes = [
            {"process_id": "a", "state": "countdown", "priority": "P2", "due_at": "2024-01-01T00:10:00"},
        ]
        await push_process_bar(ws, processes)
        assert len(ws.sent) == 1
        assert ws.sent[0]["type"] == "process_update"
        assert ws.sent[0]["active_count"] == 1
