"""Process management service — bar state push, conflict resolution, delegation (Epic 5)."""

import asyncio
import uuid
from typing import Optional, Protocol

from app.services.firestore import db


class WebSocketLike(Protocol):
    """Minimal interface for WebSocket send — enables testing without real WS."""

    async def send_json(self, data: dict) -> None: ...

    async def receive_json(self) -> dict: ...


# ---------------------------------------------------------------------------
# 5.3 — Process Bar State Push
# ---------------------------------------------------------------------------

async def build_process_bar_state(processes: list[dict]) -> dict:
    """Build the Active Process Bar state dict from process list.

    Returns a dict ready to be sent as a WebSocket message.
    """
    active = [p for p in processes if p.get("state") != "complete"]
    # Sort by priority then due_at
    priority_order = {"P0": 0, "P1": 1, "P2": 2, "P3": 3, "P4": 4}
    active.sort(key=lambda p: (
        priority_order.get(p.get("priority", "P4"), 4),
        p.get("due_at") or "9999",
    ))

    attention = [
        p["process_id"]
        for p in active
        if p.get("state") == "needs_attention"
    ]

    # Find next timer to expire
    countdown_processes = [
        p for p in active
        if p.get("state") == "countdown" and p.get("due_at")
    ]
    next_due = None
    if countdown_processes:
        countdown_processes.sort(key=lambda p: p["due_at"])
        next_due = countdown_processes[0]

    return {
        "type": "process_update",
        "processes": active,
        "active_count": len(active),
        "attention_needed": attention,
        "next_due": next_due,
    }


async def push_process_bar(websocket: WebSocketLike, processes: list[dict]):
    """Send updated process bar state to client."""
    bar_state = await build_process_bar_state(processes)
    await websocket.send_json(bar_state)


# ---------------------------------------------------------------------------
# 5.4 — P1 Conflict Resolution
# ---------------------------------------------------------------------------

async def handle_p1_conflict(
    websocket: WebSocketLike,
    process_a: dict,
    process_b: dict,
    timeout_seconds: int = 30,
) -> str:
    """Present P1 conflict to user and wait for choice.

    Returns the chosen process_id. On timeout, picks the more irreversible
    process (lower priority number = more critical).
    """
    await websocket.send_json({
        "type": "priority_conflict",
        "priority": "P1",
        "options": [
            {
                "process_id": process_a["process_id"],
                "name": process_a["name"],
                "urgency": _describe_urgency(process_a),
            },
            {
                "process_id": process_b["process_id"],
                "name": process_b["name"],
                "urgency": _describe_urgency(process_b),
            },
        ],
        "message": "Two things need your attention! Which should we handle first?",
        "timeout_seconds": timeout_seconds,
    })

    try:
        response = await asyncio.wait_for(
            websocket.receive_json(),
            timeout=timeout_seconds,
        )
        chosen_id = response.get("chosen_process_id")
        if chosen_id in (process_a["process_id"], process_b["process_id"]):
            return chosen_id
        # Invalid choice — fall through to triage
    except asyncio.TimeoutError:
        pass

    # Timeout triage: handle the more irreversible process first
    return _triage_by_irreversibility(process_a, process_b)


def _describe_urgency(process: dict) -> str:
    """Generate a human-readable urgency description for a process."""
    name = process.get("name", "Unknown process")
    state = process.get("state", "")
    if state == "needs_attention":
        return f"{name} needs attention now."
    if state == "countdown":
        return f"{name} timer is almost up."
    return f"{name} is waiting."


def _triage_by_irreversibility(process_a: dict, process_b: dict) -> str:
    """Pick the more irreversible/critical process on timeout."""
    priority_order = {"P0": 0, "P1": 1, "P2": 2, "P3": 3, "P4": 4}
    a_priority = priority_order.get(process_a.get("priority", "P4"), 4)
    b_priority = priority_order.get(process_b.get("priority", "P4"), 4)
    if a_priority <= b_priority:
        return process_a["process_id"]
    return process_b["process_id"]


# ---------------------------------------------------------------------------
# 5.6 — Buddy-Managed Delegation
# ---------------------------------------------------------------------------

def auto_delegate_stable_processes(processes: list[dict], active_step: int) -> list[str]:
    """Auto-delegate P3/P4 processes when user moves to a new active step.

    Returns list of process_ids that were delegated.
    """
    delegated = []
    for p in processes:
        if (
            p.get("state") == "in_progress"
            and p.get("step_number") != active_step
            and p.get("priority") in ("P3", "P4")
        ):
            p["buddy_managed"] = True
            p["state"] = "passive"
            delegated.append(p["process_id"])
    return delegated


def undelegate_process(processes: list[dict], process_id: str) -> bool:
    """Remove buddy delegation from a process, returning it to active tracking.

    Returns True if found and undelegated.
    """
    for p in processes:
        if p["process_id"] == process_id and p.get("buddy_managed"):
            p["buddy_managed"] = False
            p["state"] = "in_progress"
            return True
    return False


def escalate_passive_process(processes: list[dict], process_id: str) -> bool:
    """Re-escalate a passive process to needs_attention (e.g. timer fired).

    Returns True if found and escalated.
    """
    for p in processes:
        if p["process_id"] == process_id and p.get("state") == "passive":
            p["state"] = "needs_attention"
            p["buddy_managed"] = False
            return True
    return False


# ---------------------------------------------------------------------------
# 5.5 — Recipe Process Initialization
# ---------------------------------------------------------------------------

async def initialize_processes_from_recipe(
    session_id: str,
    recipe: dict,
) -> list[dict]:
    """Create process entries for recipe steps that need timing or parallel tracking.

    Persists each process to Firestore subcollection sessions/{session_id}/processes/.
    Returns list of process dicts.
    """
    processes = []
    for step in recipe.get("steps", []):
        if step.get("duration_minutes") or step.get("is_parallel"):
            instruction = step.get("instruction", "")
            truncated = instruction[:50] + ("..." if len(instruction) > 50 else "")
            process = {
                "process_id": str(uuid.uuid4()),
                "session_id": session_id,
                "name": f"Step {step['step_number']}: {truncated}",
                "step_number": step["step_number"],
                "priority": "P2",
                "state": "pending",
                "started_at": None,
                "due_at": None,
                "duration_minutes": step.get("duration_minutes"),
                "buddy_managed": False,
                "is_parallel": step.get("is_parallel", False),
            }
            processes.append(process)

            # Persist to Firestore
            await db.collection("sessions").document(session_id) \
                .collection("processes").document(process["process_id"]).set(process)

    return processes


# ---------------------------------------------------------------------------
# 5.7 — Process State Persistence
# ---------------------------------------------------------------------------

async def persist_process_state(session_id: str, process_id: str, updates: dict):
    """Persist a process state change to Firestore."""
    await db.collection("sessions").document(session_id) \
        .collection("processes").document(process_id).update(updates)


async def load_processes(session_id: str) -> list[dict]:
    """Load all processes for a session from Firestore (for session resume)."""
    docs = db.collection("sessions").document(session_id) \
        .collection("processes").stream()
    processes = []
    async for doc in docs:
        processes.append(doc.to_dict())
    return processes


# ---------------------------------------------------------------------------
# 9.6 — Dynamic Process Creation for Freestyle
# ---------------------------------------------------------------------------

async def create_dynamic_process(
    session_id: str,
    name: str,
    duration_minutes: Optional[float] = None,
    step_number: int = 0,
    priority: str = "P2",
) -> dict:
    """Create a process entry dynamically during a freestyle session.

    Used when the buddy infers a timed process (e.g., 'boil pasta for 10 min').
    Returns the process dict.
    """
    process = {
        "process_id": str(uuid.uuid4()),
        "session_id": session_id,
        "name": name,
        "step_number": step_number,
        "priority": priority,
        "state": "pending",
        "started_at": None,
        "due_at": None,
        "duration_minutes": duration_minutes,
        "buddy_managed": False,
        "is_parallel": False,
        "dynamic": True,  # Flag to identify dynamically created processes
    }

    await db.collection("sessions").document(session_id) \
        .collection("processes").document(process["process_id"]).set(process)

    return process
