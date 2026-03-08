"""Technical metrics instrumentation (Epic 7, Task 7.5).

Hybrid collector: in-memory for quick local summaries + Firestore for multi-instance durability.
"""

import logging
import statistics
from collections import defaultdict
from datetime import datetime, timezone

from app.services.firestore import db

logger = logging.getLogger("ratatouille.metrics")


class MetricsCollector:
    """Collects latency and counter metrics with Firestore durability."""

    def __init__(self):
        self.latencies: dict[str, list[float]] = defaultdict(list)
        self.counters: dict[str, int] = defaultdict(int)

    async def record_latency(self, metric_name: str, latency_ms: float):
        """Record a latency measurement and persist to Firestore."""
        self.latencies[metric_name].append(latency_ms)
        try:
            from google.cloud import firestore as fs
            minute_bucket = datetime.now(timezone.utc).strftime("%Y%m%d%H%M")
            await db.collection("metrics_minute").document(f"{metric_name}:{minute_bucket}").set(
                {
                    "metric_name": metric_name,
                    "minute_bucket": minute_bucket,
                    "count": fs.Increment(1),
                    "sum_ms": fs.Increment(float(latency_ms)),
                    "max_ms": float(latency_ms),
                    "updated_at": fs.SERVER_TIMESTAMP,
                },
                merge=True,
            )
        except Exception as e:
            logger.warning(f"Failed to persist metric {metric_name}: {e}")

    async def increment(self, counter_name: str):
        """Increment a counter and persist to Firestore."""
        self.counters[counter_name] += 1
        try:
            from google.cloud import firestore as fs
            await db.collection("metrics_counters").document(counter_name).set(
                {
                    "name": counter_name,
                    "count": fs.Increment(1),
                    "updated_at": fs.SERVER_TIMESTAMP,
                },
                merge=True,
            )
        except Exception as e:
            logger.warning(f"Failed to persist counter {counter_name}: {e}")

    def get_summary(self) -> dict:
        """Return in-memory summary with p50/p95 for all latency metrics."""
        summary = {}
        for name, values in self.latencies.items():
            if values:
                sorted_vals = sorted(values)
                n = len(sorted_vals)
                summary[name] = {
                    "count": n,
                    "p50": round(sorted_vals[n // 2], 2),
                    "p95": round(sorted_vals[int(n * 0.95)], 2) if n >= 20 else round(max(sorted_vals), 2),
                    "mean": round(statistics.mean(values), 2),
                }
        summary["counters"] = dict(self.counters)
        return summary


metrics = MetricsCollector()
