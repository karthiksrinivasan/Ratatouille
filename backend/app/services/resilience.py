"""Resilience utilities for graceful degradation (Epic 7, Task 7.7).

Provides retry wrappers and fallback patterns for external service calls.
"""

import asyncio
import logging

logger = logging.getLogger("ratatouille.resilience")


async def with_retry(coro_func, max_retries=2, backoff_base=1.0):
    """Retry an async callable with exponential backoff.

    Args:
        coro_func: Async callable (no-arg) to retry.
        max_retries: Max number of retries after initial attempt.
        backoff_base: Base delay in seconds for exponential backoff.

    Returns:
        Result of successful call.

    Raises:
        The last exception if all attempts fail.
    """
    for attempt in range(max_retries + 1):
        try:
            return await coro_func()
        except Exception as e:
            if attempt == max_retries:
                logger.error(f"Failed after {max_retries + 1} attempts: {e}")
                raise
            wait = backoff_base * (2 ** attempt)
            logger.warning(f"Attempt {attempt + 1} failed, retrying in {wait}s: {e}")
            await asyncio.sleep(wait)


async def with_fallback(coro_func, fallback_value, error_msg="Operation failed"):
    """Execute an async callable, returning fallback_value on failure.

    Args:
        coro_func: Async callable to attempt.
        fallback_value: Value to return if coro_func raises.
        error_msg: Log message on failure.

    Returns:
        Result of coro_func, or fallback_value on exception.
    """
    try:
        return await coro_func()
    except Exception as e:
        logger.warning(f"{error_msg}: {e}")
        return fallback_value
