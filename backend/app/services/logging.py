"""Structured JSON logging for Cloud Run (Epic 7, Task 7.4)."""

import json
import logging
from datetime import datetime, timezone


class StructuredFormatter(logging.Formatter):
    """Formats log records as JSON for Cloud Logging compatibility."""

    def format(self, record):
        log_entry = {
            "severity": record.levelname,
            "message": record.getMessage(),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "component": record.name,
        }
        if hasattr(record, "session_id"):
            log_entry["session_id"] = record.session_id
        if hasattr(record, "endpoint"):
            log_entry["endpoint"] = record.endpoint
        if hasattr(record, "latency_ms"):
            log_entry["latency_ms"] = record.latency_ms
        if hasattr(record, "status_code"):
            log_entry["status_code"] = record.status_code
        if record.exc_info and record.exc_info[1]:
            log_entry["error"] = str(record.exc_info[1])
        return json.dumps(log_entry)


def setup_logging():
    """Configure structured JSON logging at app startup."""
    handler = logging.StreamHandler()
    handler.setFormatter(StructuredFormatter())
    logging.root.handlers = [handler]
    logging.root.setLevel(logging.INFO)


logger = logging.getLogger("ratatouille")
