# Epic 5: Process Management, Timers & Concurrency

## Goal

Track multiple active cooking processes simultaneously with a priority queue. Surface the Active Process Bar to the client, handle timer alerts, resolve priority conflicts, and support buddy-managed delegated monitoring.

## Prerequisites

- Epic 4 complete (session lifecycle, WebSocket channel, orchestrator agent)
- Coordinate with Epic 8 task 8.10 for process bar + conflict chooser mobile UX

## PRD References

- §7.7 Concurrency Model (CM-01 through CM-05)
- §7.3 MO-02 Active Process Bar states
- §12.2 Realtime Channel (process updates via WebSocket)
- NFR-01 Process-bar state updates <= 500ms

## Tech Guide References

- §2 ADK — Agent tools, state management
- §5 Firestore — real-time updates, atomic operations

---

## Data Model

### Pydantic Models — `app/models/process.py`

```python
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
import uuid

class ProcessCreate(BaseModel):
    name: str                          # e.g., "Boil pasta water"
    step_number: int                   # Which recipe step this belongs to
    duration_minutes: Optional[float] = None
    is_parallel: bool = False          # Can run alongside other processes

class Process(BaseModel):
    process_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    session_id: str
    name: str
    step_number: int
    priority: str = "P2"              # P0 (critical) to P4 (background)
    state: str = "pending"            # pending | in_progress | countdown | needs_attention | complete | passive
    started_at: Optional[datetime] = None
    due_at: Optional[datetime] = None  # When timer expires
    duration_minutes: Optional[float] = None
    buddy_managed: bool = False        # Buddy is monitoring this in background
    is_parallel: bool = False

class ProcessBarState(BaseModel):
    """Full state of the Active Process Bar, pushed to client."""
    processes: list[Process]
    active_count: int
    attention_needed: list[str]        # process_ids needing user action
    next_due: Optional[Process] = None # Soonest timer expiring
```

### Priority Levels

| Priority | Label | Description | Example |
|----------|-------|-------------|---------|
| P0 | Critical | Irreversible damage imminent | Oil about to smoke point, pasta overcooking |
| P1 | Urgent | Needs attention soon, user choice required | Two things ready simultaneously |
| P2 | Active | Currently being worked on | Main step in progress |
| P3 | Monitoring | Running but stable | Water simmering, dough resting |
| P4 | Background | No action needed | Passive cooling, marinating |

### Process State Machine

```
pending → in_progress → countdown → complete
                    ↓          ↓
              needs_attention  needs_attention
                    ↓          ↓
                 complete    complete

Any state → passive (buddy-managed background monitoring)
```

---

## Tasks

### 5.1 Process Manager Agent (ADK)

**What:** ADK agent that manages the process queue. Creates, updates, and queries processes.

**Implementation:** `app/agents/process_manager.py`

```python
from google.adk.agents import Agent
from google.adk.tools import FunctionTool, ToolContext
from app.services.firestore import db
from google.cloud import firestore
from datetime import datetime, timedelta
import json, uuid

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

    # Add to state for immediate access
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
            return json.dumps({"process_id": process_id, "state": p["state"], "due_at": p.get("due_at")})
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
    """Get all processes that are not complete or passive."""
    processes = tool_context.state.get("processes", [])
    active = [p for p in processes if p["state"] not in ("complete", "passive")]
    active.sort(key=lambda p: ("P0 P1 P2 P3 P4".split().index(p["priority"]), p.get("due_at") or "9999"))
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

process_manager = Agent(
    model="gemini-2.5-flash",
    name="process_manager",
    instruction="""You manage the cooking process queue for an active session.

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
irreversible one first.""",
    tools=[
        FunctionTool(create_process),
        FunctionTool(start_process),
        FunctionTool(complete_process),
        FunctionTool(get_active_processes),
        FunctionTool(flag_needs_attention),
        FunctionTool(delegate_to_buddy),
    ],
)
```

**Acceptance Criteria:**
- [ ] Processes created, started, completed, flagged
- [ ] Priority queue maintained (P0 highest)
- [ ] Timer countdown tracked with `due_at`
- [ ] Buddy delegation marks process as passive
- [ ] All operations update shared agent state

---

### 5.2 Timer System

**What:** Background timer tracking that fires alerts when processes are due.

**Implementation:**

```python
import asyncio
from datetime import datetime

class TimerSystem:
    """Manages countdown timers for active processes."""

    def __init__(self, on_timer_due, on_timer_warning):
        self.timers: dict[str, asyncio.Task] = {}
        self.on_timer_due = on_timer_due        # Callback when timer expires
        self.on_timer_warning = on_timer_warning  # Callback for pre-expiry warning

    async def start_timer(self, process_id: str, duration_minutes: float, process_name: str):
        """Start a countdown timer for a process."""
        if process_id in self.timers:
            self.timers[process_id].cancel()

        async def _countdown():
            total_seconds = duration_minutes * 60

            # Warning at 1 minute remaining (if timer > 2 min)
            if total_seconds > 120:
                await asyncio.sleep(total_seconds - 60)
                await self.on_timer_warning(process_id, process_name, remaining_seconds=60)
                await asyncio.sleep(60)
            else:
                await asyncio.sleep(total_seconds)

            await self.on_timer_due(process_id, process_name)

        self.timers[process_id] = asyncio.create_task(_countdown())

    def cancel_timer(self, process_id: str):
        if process_id in self.timers:
            self.timers[process_id].cancel()
            del self.timers[process_id]

    def cancel_all(self):
        for task in self.timers.values():
            task.cancel()
        self.timers.clear()
```

**Integration with WebSocket:**
```python
async def on_timer_due(process_id, process_name):
    await websocket.send_json({
        "type": "timer_alert",
        "process_id": process_id,
        "process_name": process_name,
        "priority": "P0",
        "message": f"{process_name} is done! Time to check.",
    })

async def on_timer_warning(process_id, process_name, remaining_seconds):
    await websocket.send_json({
        "type": "timer_warning",
        "process_id": process_id,
        "process_name": process_name,
        "remaining_seconds": remaining_seconds,
        "message": f"{process_name} — about 1 minute left.",
    })
```

**Acceptance Criteria:**
- [ ] Timers start when process enters countdown state
- [ ] 1-minute warning for timers > 2 minutes
- [ ] Timer expiry sends P0 alert via WebSocket
- [ ] Timers cancellable (process completed early or abandoned)
- [ ] Multiple timers run concurrently

---

### 5.3 Process Bar State Push

**What:** Push the full Active Process Bar state to client on every process state change.

**Implementation:**

```python
async def push_process_bar(websocket, processes: list[dict]):
    """Send updated process bar state to client."""
    active = [p for p in processes if p["state"] != "complete"]
    attention = [p["process_id"] for p in active if p["state"] == "needs_attention"]

    # Find next timer to expire
    countdown_processes = [p for p in active if p["state"] == "countdown" and p.get("due_at")]
    next_due = None
    if countdown_processes:
        countdown_processes.sort(key=lambda p: p["due_at"])
        next_due = countdown_processes[0]

    bar_state = {
        "type": "process_update",
        "processes": active,
        "active_count": len(active),
        "attention_needed": attention,
        "next_due": next_due,
    }

    await websocket.send_json(bar_state)
```

**Process bar visual states (for client rendering):**
- `in_progress` — Blue, animated pulse
- `countdown` — Yellow/orange with remaining time display
- `needs_attention` — Red, flashing
- `complete` — Green, brief flash then fade
- `passive` — Gray, small indicator, buddy-managed label

**Acceptance Criteria:**
- [ ] Process bar state pushed on every state change
- [ ] Includes all active processes sorted by priority
- [ ] Attention-needed processes flagged
- [ ] Next-due timer highlighted
- [ ] Latency: <= 500ms from state change to client receipt

---

### 5.4 P1 Conflict Resolution

**What:** When two processes both need attention simultaneously, present a choice to the user and handle timeout.

**Implementation:**

```python
async def handle_p1_conflict(
    websocket,
    process_a: dict,
    process_b: dict,
    timeout_seconds: int = 30,
):
    """Present P1 conflict to user and wait for choice."""
    await websocket.send_json({
        "type": "priority_conflict",
        "priority": "P1",
        "options": [
            {
                "process_id": process_a["process_id"],
                "name": process_a["name"],
                "urgency": "The garlic needs to come off heat now.",
            },
            {
                "process_id": process_b["process_id"],
                "name": process_b["name"],
                "urgency": "Pasta is almost at al dente.",
            },
        ],
        "message": "Two things need your attention! Which should we handle first?",
        "timeout_seconds": timeout_seconds,
    })

    # Wait for user response with timeout
    try:
        response = await asyncio.wait_for(
            websocket.receive_json(),
            timeout=timeout_seconds,
        )
        chosen_id = response.get("chosen_process_id")
        return chosen_id
    except asyncio.TimeoutError:
        # Timeout triage: handle the more irreversible process first
        # Burning > overcooking > undercooking
        irreversibility = {"P0": 0, "P1": 1, "P2": 2, "P3": 3, "P4": 4}
        if irreversibility.get(process_a["priority"], 4) <= irreversibility.get(process_b["priority"], 4):
            return process_a["process_id"]
        return process_b["process_id"]
```

**Acceptance Criteria:**
- [ ] P1 conflict presented with clear options
- [ ] User can choose which to handle first
- [ ] 30-second timeout with automatic triage by irreversibility
- [ ] Unchosen process continues tracking
- [ ] At least one P1 conflict demonstrable in demo recipe

---

### 5.5 Recipe Process Initialization

**What:** When a session activates, parse the recipe steps and create initial processes for steps that involve timing or parallelism.

**Implementation:**

```python
async def initialize_processes_from_recipe(session_id: str, recipe: dict) -> list[dict]:
    """Create process entries for recipe steps that need tracking."""
    processes = []
    for step in recipe.get("steps", []):
        if step.get("duration_minutes") or step.get("is_parallel"):
            process = {
                "process_id": str(uuid.uuid4()),
                "session_id": session_id,
                "name": f"Step {step['step_number']}: {step['instruction'][:50]}...",
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
```

**Acceptance Criteria:**
- [ ] Processes created for all timed and parallel steps
- [ ] Processes persisted in Firestore subcollection
- [ ] Parallel steps marked correctly
- [ ] Process names human-readable (truncated step instruction)

---

### 5.6 Buddy-Managed Delegation

**What:** Allow the orchestrator to delegate stable processes to buddy monitoring. The buddy tracks these in the background and alerts only when state changes.

**Behavior:**
- When user starts a new active step, long-running background tasks (simmering, resting) are automatically delegated
- Buddy-managed processes show as "passive" in the process bar with a small buddy icon
- If a buddy-managed timer fires, it's escalated back to active attention

```python
async def auto_delegate_stable_processes(processes: list[dict], active_step: int):
    """Auto-delegate P3/P4 processes when user moves to a new active step."""
    for p in processes:
        if p["state"] == "in_progress" and p["step_number"] != active_step:
            if p["priority"] in ("P3", "P4"):
                p["buddy_managed"] = True
                p["state"] = "passive"
```

**Acceptance Criteria:**
- [ ] Stable processes auto-delegated when user moves to new step
- [ ] Passive processes visible but muted in process bar
- [ ] Timer expiry re-escalates passive process to needs_attention
- [ ] User can manually delegate/undelegate

---

### 5.7 Process State Persistence

**What:** Persist all process state changes to Firestore for session resume.

```python
async def persist_process_state(session_id: str, process_id: str, updates: dict):
    await db.collection("sessions").document(session_id) \
        .collection("processes").document(process_id).update(updates)
```

**Acceptance Criteria:**
- [ ] Every process state change persisted
- [ ] Processes recoverable on session resume
- [ ] Timer state can be recalculated from `started_at` + `duration_minutes`

---

### 5.8 Mobile UX Implementation (Active Process Bar)

**What:** Implement process/timer UX that remains usable under pressure and at a glance.

**Required mobile UX components:**
1. Sticky process bar visible throughout live cooking.
2. Priority-driven visual treatment:
   - P0/P1 must be unmistakable (color + motion + icon)
   - P3/P4 should stay visible but low-noise
3. Conflict interaction:
   - Full-width two-option chooser for P1 conflicts
   - Timeout countdown visible to user
4. Hands-busy controls:
   - Tap targets sized for quick access
   - Voice shortcuts mirrored by UI buttons (`Handle A`, `Handle B`, `Buddy watch this`)

**Acceptance Criteria:**
- [ ] Process bar information is readable in <1 second glance
- [ ] P1 conflict chooser is actionable with one tap
- [ ] Timeout state is visible and understandable
- [ ] No hidden critical alerts behind scrolling content

---

## Demo Scenario (Aglio e Olio)

The demo recipe exercises this epic with:

1. **Step 1 (Boil water)** — P2, 8-min timer, countdown state
2. **Step 2 (Slice garlic)** — P2, parallel with step 1
3. **Step 3 (Cook pasta)** — P2, 9-min timer. Step 1 process completes → step 3 starts
4. **Step 4 (Saute garlic)** — P2, 4-min timer, runs parallel with pasta. **P1 conflict** when both step 3 and step 4 timers approach completion simultaneously
5. **Steps 5-7** — Sequential, no timers

**P1 conflict demo moment:** Pasta reaching al dente (step 3) while garlic approaching golden (step 4). User must choose which to handle first. If no response, system handles garlic first (more irreversible — burns quickly).

## Epic Completion Checklist

- [ ] Process CRUD via ADK agent tools
- [ ] Priority queue P0-P4 with correct ordering
- [ ] Timer system with countdown and warning
- [ ] Process bar state pushed via WebSocket within 500ms
- [ ] P1 conflict resolution with timeout triage
- [ ] Processes initialized from recipe steps
- [ ] Buddy delegation for stable background processes
- [ ] All state persisted to Firestore
- [ ] Mobile UX for process bar/conflict chooser validated on device
- [ ] Demo recipe exercises concurrent processes with P1 conflict
