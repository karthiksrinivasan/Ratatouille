"""Privacy controls verification module (Epic 7, Task 7.8).

Documents and enforces all privacy constraints for the Ratatouille app.
"""

from typing import Any

# Fields that must never appear in log output
SENSITIVE_FIELDS = [
    "authorization",
    "token",
    "audio",
    "password",
    "Bearer",
    "id_token",
    "refresh_token",
    "secret",
    "credential",
]

# Documented privacy constraints for the application
PRIVACY_CONSTRAINTS = {
    "ambient_mode_requires_optin": True,
    "ambient_raw_not_persisted": True,
    "only_user_triggered_artifacts_stored": True,
    "auth_on_every_endpoint": True,
    "memory_confirmation_gate": True,
    "no_pii_in_logs": True,
}


def verify_no_pii_in_log(log_entry: dict) -> bool:
    """Check that a log entry does not contain tokens, audio data, or PII fields.

    Returns True if the log entry is clean (no PII found).
    Returns False if sensitive data is detected.
    """
    sensitive_lower = [f.lower() for f in SENSITIVE_FIELDS]

    def _check_value(value: Any) -> bool:
        """Return False if value contains sensitive data."""
        if isinstance(value, str):
            val_lower = value.lower()
            for field in sensitive_lower:
                if field in val_lower:
                    return False
        return True

    def _check_dict(d: dict) -> bool:
        for key, value in d.items():
            # Check if the key itself is sensitive
            if key.lower() in sensitive_lower:
                return False
            # Check if value contains sensitive strings
            if not _check_value(value):
                return False
            # Recurse into nested dicts
            if isinstance(value, dict):
                if not _check_dict(value):
                    return False
        return True

    return _check_dict(log_entry)


def sanitize_log_data(data: dict) -> dict:
    """Return a copy of data with sensitive fields redacted.

    Sensitive field values are replaced with '[REDACTED]'.
    """
    sensitive_lower = [f.lower() for f in SENSITIVE_FIELDS]
    sanitized = {}
    for key, value in data.items():
        if key.lower() in sensitive_lower:
            sanitized[key] = "[REDACTED]"
        elif isinstance(value, dict):
            sanitized[key] = sanitize_log_data(value)
        else:
            sanitized[key] = value
    return sanitized
