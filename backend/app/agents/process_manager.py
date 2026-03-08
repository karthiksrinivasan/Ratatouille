"""Process Manager Agent — manages cooking process queue (Epic 5)."""

import json
import uuid
from datetime import datetime, timedelta

from google.adk.agents import Agent
from google.adk.tools import FunctionTool, ToolContext

from app.services.gemini import MODEL_FLASH

# ---------------------------------------------------------------------------
# Priority ordering helper
# ---------------------------------------------------------------------------
PRIORITY_ORDER = {"P0": 0, "P1": 1, "P2": 2, "P3": 3, "P4": 4}


def _priority_index(p: str) -> int:
    return PRIORITY_ORDER.get(p, 4)


# ---------------------------------------------------------------------------
# Agent tool functions
# ---------------------------------------------------------------------------

def create_process(
    name: str,
    step_number: int,
    duration_minutes: float,
    priority: str,
    is_parallel: bool,
    tool_context: ToolContext,
) -> str:
    """Create a new cooking process and add it to the active queue."""
    session_id = tool_context.state["session_id"]
    process_id = str(uuid.uuid4())

    process = {
        "process_id": process_id,
        "session_id": session_id,
        "name": name,
        "step_number": step_number,
        "priority": priority,
        "state": "pending",
        "started_at": None,
        "due_at": None,
        "duration_minutes": duration_minutes,
        "buddy_managed": False,
        "is_parallel": is_parallel,
    }

    processes = tool_context.state.get("processes", [])
    processes.append(process)
    tool_context.state["processes"] = processes

    return json.dumps({"process_id": process_id, "status": "created"})


def start_process(process_id: str, tool_context: ToolContext) -> str:
    """Start a process — sets timer if duration is specified."""
    processes = tool_context.state.get("processes", [])
    for p in processes:
        if p["process_id"] == process_id:
            p["state"] = "in_progress"
            p["started_at"] = datetime.utcnow().isoformat()
            if p["duration_minutes"]:
                due = datetime.utcnow() + timedelta(minutes=p["duration_minutes"])
                p["due_at"] = due.isoformat()
                p["state"] = "countdown"
            tool_context.state["processes"] = processes
            return json.dumps({
                "process_id": process_id,
                "state": p["state"],
                "due_at": p.get("due_at"),
            })
    return json.dumps({"error": "Process not found"})


def complete_process(process_id: str, tool_context: ToolContext) -> str:
    """Mark a process as complete."""
    processes = tool_context.state.get("processes", [])
    for p in processes:
        if p["process_id"] == process_id:
            p["state"] = "complete"
            tool_context.state["processes"] = processes
            return json.dumps({"process_id": process_id, "state": "complete"})
    return json.dumps({"error": "Process not found"})


def get_active_processes(tool_context: ToolContext) -> str:
    """Get all processes that are not complete or passive, sorted by priority then due_at."""
    processes = tool_context.state.get("processes", [])
    active = [p for p in processes if p["state"] not in ("complete", "passive")]
    active.sort(key=lambda p: (
        _priority_index(p.get("priority", "P4")),
        p.get("due_at") or "9999",
    ))
    return json.dumps(active)


def flag_needs_attention(process_id: str, tool_context: ToolContext) -> str:
    """Flag a process as needing user attention."""
    processes = tool_context.state.get("processes", [])
    for p in processes:
        if p["process_id"] == process_id:
            p["state"] = "needs_attention"
            tool_context.state["processes"] = processes
            return json.dumps({"process_id": process_id, "state": "needs_attention"})
    return json.dumps({"error": "Process not found"})


def delegate_to_buddy(process_id: str, tool_context: ToolContext) -> str:
    """Delegate a process to buddy monitoring (background tracking)."""
    processes = tool_context.state.get("processes", [])
    for p in processes:
        if p["process_id"] == process_id:
            p["buddy_managed"] = True
            p["state"] = "passive"
            tool_context.state["processes"] = processes
            return json.dumps({"process_id": process_id, "buddy_managed": True})
    return json.dumps({"error": "Process not found"})


# ---------------------------------------------------------------------------
# ADK Agent definition
# ---------------------------------------------------------------------------

PROCESS_MANAGER_INSTRUCTION = """You manage the cooking process queue for an active session.

Your responsibilities:
- Create processes for each recipe step that involves timing or parallel activity
- Start timers when the user begins a step
- Track countdown progress and alert when timers are due
- Flag processes that need attention
- Handle priority conflicts (P1) by presenting choices to the user
- Delegate stable processes to buddy monitoring

Priority rules:
- P0: Irreversible damage imminent — interrupt immediately
- P1: Two things need attention simultaneously — present choice
- P2: Active main task
- P3: Running but stable (simmering, resting)
- P4: Background (cooling, marinating)

When a P1 conflict occurs, clearly present both options and ask the user
which to handle first. If no response within 30 seconds, handle the more
irreversible one first."""


process_manager = Agent(
    model=MODEL_FLASH,
    name="process_manager",
    instruction=PROCESS_MANAGER_INSTRUCTION,
    tools=[
        FunctionTool(create_process),
        FunctionTool(start_process),
        FunctionTool(complete_process),
        FunctionTool(get_active_processes),
        FunctionTool(flag_needs_attention),
        FunctionTool(delegate_to_buddy),
    ],
)
