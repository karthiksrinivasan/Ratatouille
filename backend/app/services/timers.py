"""Timer system — background countdown timers for cooking processes (Epic 5)."""

import asyncio
from typing import Awaitable, Callable, Dict, Optional


# Callback signatures:
#   on_timer_due(process_id, process_name) -> None
#   on_timer_warning(process_id, process_name, remaining_seconds) -> None

OnTimerDue = Callable[[str, str], Awaitable[None]]
OnTimerWarning = Callable[[str, str, int], Awaitable[None]]


class TimerSystem:
    """Manages countdown timers for active cooking processes."""

    def __init__(
        self,
        on_timer_due: OnTimerDue,
        on_timer_warning: OnTimerWarning,
    ):
        self.timers: Dict[str, asyncio.Task] = {}
        self.on_timer_due = on_timer_due
        self.on_timer_warning = on_timer_warning

    async def start_timer(
        self,
        process_id: str,
        duration_minutes: float,
        process_name: str,
    ):
        """Start a countdown timer for a process.

        - Fires a 1-minute warning if the total duration exceeds 2 minutes.
        - Fires the due callback when the timer expires.
        """
        # Cancel existing timer for this process (idempotent restart)
        if process_id in self.timers:
            self.timers[process_id].cancel()

        async def _countdown():
            total_seconds = duration_minutes * 60

            # Warning at 1 minute remaining (only if timer > 2 min)
            if total_seconds > 120:
                await asyncio.sleep(total_seconds - 60)
                await self.on_timer_warning(process_id, process_name, 60)
                await asyncio.sleep(60)
            else:
                await asyncio.sleep(total_seconds)

            await self.on_timer_due(process_id, process_name)

        self.timers[process_id] = asyncio.create_task(_countdown())

    def cancel_timer(self, process_id: str):
        """Cancel a running timer for a specific process."""
        if process_id in self.timers:
            self.timers[process_id].cancel()
            del self.timers[process_id]

    def cancel_all(self):
        """Cancel all running timers."""
        for task in self.timers.values():
            task.cancel()
        self.timers.clear()

    def active_timer_count(self) -> int:
        """Return the number of currently running timers."""
        return len(self.timers)

    def has_timer(self, process_id: str) -> bool:
        """Check if a timer is running for the given process."""
        return process_id in self.timers
