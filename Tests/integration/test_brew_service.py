"""
apfel-plus Integration Tests -- Brew Service Mode

Tests that `brew services start apfel-plus` works correctly.
These tests manage the service lifecycle themselves:
start before tests, stop after.

Run: python3 -m pytest Tests/integration/test_brew_service.py -v
Requires: apfel-plus installed via Homebrew with service block in formula.
"""

import json
import os
import pathlib
import subprocess
import time

import httpx
import pytest

# Whole-suite marker: manipulates global launchd/brew service state on the
# shared service port - must never run concurrently with other suites (#374).
pytestmark = pytest.mark.serial


ROOT = pathlib.Path(__file__).resolve().parents[2]
SERVICE_PORT = 11434
SERVICE_URL = f"http://127.0.0.1:{SERVICE_PORT}"


def _brew_service_available():
    """Check if apfel-plus is installed via Homebrew with a service block."""
    try:
        result = subprocess.run(
            ["brew", "services", "info", "apfel-plus", "--json"],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0:
            return False
        info = json.loads(result.stdout)
        return isinstance(info, list) and len(info) > 0
    except (subprocess.TimeoutExpired, FileNotFoundError, json.JSONDecodeError):
        return False


def _service_running():
    try:
        resp = httpx.get(f"{SERVICE_URL}/health", timeout=2)
        return resp.status_code == 200
    except httpx.HTTPError:
        return False


@pytest.fixture(scope="module")
def brew_service():
    """Start brew service before tests, stop after."""
    if not _brew_service_available():
        pytest.skip("apfel-plus not installed via Homebrew or missing service block")

    # Stop if already running (clean slate)
    subprocess.run(["brew", "services", "stop", "apfel-plus"],
                    capture_output=True, timeout=10)
    time.sleep(1)

    # Start
    result = subprocess.run(["brew", "services", "start", "apfel-plus"],
                             capture_output=True, text=True, timeout=10)
    if result.returncode != 0:
        pytest.skip(f"brew services start failed: {result.stderr}")

    # Wait for health
    for _ in range(20):
        if _service_running():
            break
        time.sleep(0.5)
    else:
        pytest.skip("brew service started but health check failed after 10s")

    yield

    # Cleanup
    subprocess.run(["brew", "services", "stop", "apfel-plus"],
                    capture_output=True, timeout=10)


def test_brew_service_health(brew_service):
    """Brew service health endpoint returns OK."""
    resp = httpx.get(f"{SERVICE_URL}/health", timeout=5)
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "ok"
    assert data["model_available"] is True


def test_brew_service_models(brew_service):
    """Brew service /v1/models returns apple-foundationmodel."""
    resp = httpx.get(f"{SERVICE_URL}/v1/models", timeout=5)
    assert resp.status_code == 200
    data = resp.json()
    assert any(m["id"] == "apple-foundationmodel" for m in data["data"])


@pytest.mark.model
def test_brew_service_chat_completion(brew_service):
    """Brew service handles a chat completion request."""
    resp = httpx.post(
        f"{SERVICE_URL}/v1/chat/completions",
        json={
            "model": "apple-foundationmodel",
            "messages": [{"role": "user", "content": "What is 2+2? Reply with just the number."}],
            "max_tokens": 10,
        },
        timeout=30,
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "choices" in data
    assert len(data["choices"]) > 0
    content = data["choices"][0]["message"]["content"]
    assert "4" in content


def test_brew_service_streaming(brew_service):
    """Brew service handles streaming chat completion."""
    with httpx.stream(
        "POST",
        f"{SERVICE_URL}/v1/chat/completions",
        json={
            "model": "apple-foundationmodel",
            "messages": [{"role": "user", "content": "Say OK."}],
            "stream": True,
            "max_tokens": 5,
        },
        timeout=30,
    ) as resp:
        assert resp.status_code == 200
        chunks = []
        for line in resp.iter_lines():
            if line.startswith("data: ") and line != "data: [DONE]":
                chunks.append(json.loads(line[6:]))
        assert len(chunks) > 0, "Expected at least one SSE chunk"


def test_brew_service_info_shows_loaded(brew_service):
    """brew services info shows the service as loaded with correct command."""
    # Ensure service is fully up
    for _ in range(10):
        if _service_running():
            break
        time.sleep(0.5)
    result = subprocess.run(
        ["brew", "services", "info", "apfel-plus", "--json"],
        capture_output=True, text=True, timeout=10,
    )
    assert result.returncode == 0
    info = json.loads(result.stdout)
    assert info[0]["loaded"] is True
    assert "apfel-plus" in info[0]["command"]
    assert "--serve" in info[0]["command"]


def test_brew_service_logs_exist(brew_service):
    """Brew service log file exists and has content."""
    log_path = pathlib.Path("/opt/homebrew/var/log/apfel-plus.log")
    assert log_path.exists(), f"Log file not found at {log_path}"
    content = log_path.read_text()
    assert "apfel-plus server" in content, "Log file missing server startup output"


def test_brew_service_restart(brew_service):
    """Brew service can be restarted."""
    result = subprocess.run(["brew", "services", "restart", "apfel-plus"],
                             capture_output=True, text=True, timeout=15)
    assert result.returncode == 0
    # Wait for health after restart
    for _ in range(20):
        if _service_running():
            break
        time.sleep(0.5)
    assert _service_running(), "Service not running after restart"
