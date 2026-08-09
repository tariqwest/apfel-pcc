"""Strict context strategy: the final prompt must not be duplicated.

The server sends the final user prompt to the model via respond(), so the
transcript entries baked into the session must NOT also contain it. All
trimming strategies receive the final entry for budget accounting only.
A strict-strategy request that bakes the final prompt into the transcript
makes the model see the user's prompt twice and double-counts it in
usage.prompt_tokens.

Regression tests: identical requests with and without
x_context_strategy=strict must report identical prompt_tokens.
"""
import httpx
import pytest

# Whole-suite marker: these tests drive real on-device generation (or, for
# the permit/benchmark suites, need Apple Intelligence up); GitHub CI cannot
# run them (CLAUDE.md "What GitHub CI CANNOT run"). Keeps -m "not model" a
# complete, correct model-free selector for the fast preflight phase (#374).
pytestmark = pytest.mark.model


BASE_URL = "http://127.0.0.1:11434"


def prompt_tokens(messages, strategy=None):
    payload = {"model": "apple-foundationmodel", "messages": messages, "max_tokens": 16}
    if strategy is not None:
        payload["x_context_strategy"] = strategy
    resp = httpx.post(f"{BASE_URL}/v1/chat/completions", json=payload, timeout=120)
    assert resp.status_code == 200, f"server returned {resp.status_code}: {resp.text}"
    return resp.json()["usage"]["prompt_tokens"]


def test_strict_single_message_prompt_tokens_match_default():
    """Single user message: strict must count the prompt exactly once."""
    messages = [{"role": "user", "content": "Reply with the single word OK."}]
    default_count = prompt_tokens(messages)
    strict_count = prompt_tokens(messages, strategy="strict")
    assert strict_count == default_count, (
        f"strict prompt_tokens {strict_count} != default {default_count} "
        "- the strict strategy is double-counting the final prompt"
    )


def test_strict_multi_turn_prompt_tokens_match_default():
    """Multi-turn history that fits the budget: strict and default build
    identical transcripts, so prompt_tokens must match exactly."""
    messages = [
        {"role": "user", "content": "My favourite colour is blue."},
        {"role": "assistant", "content": "Noted - blue it is."},
        {"role": "user", "content": "What is my favourite colour? One word."},
    ]
    default_count = prompt_tokens(messages)
    strict_count = prompt_tokens(messages, strategy="strict")
    assert strict_count == default_count, (
        f"strict prompt_tokens {strict_count} != default {default_count} "
        "- the strict strategy is double-counting the final prompt"
    )
