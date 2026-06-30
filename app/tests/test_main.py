"""Unit tests for the sample API. Run with `pytest`."""
from __future__ import annotations

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_healthz() -> None:
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_readyz() -> None:
    resp = client.get("/readyz")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ready"}


def test_version_fields() -> None:
    resp = client.get("/version")
    assert resp.status_code == 200
    body = resp.json()
    assert body["name"] == "devsecops-sample-api"
    assert "version" in body
    assert "python" in body


def test_echo_roundtrip() -> None:
    resp = client.post("/echo", json={"message": "hello"})
    assert resp.status_code == 200
    assert resp.json() == {"message": "hello", "length": 5}


def test_echo_rejects_empty() -> None:
    resp = client.post("/echo", json={"message": ""})
    assert resp.status_code == 422


def test_echo_rejects_too_long() -> None:
    resp = client.post("/echo", json={"message": "x" * 281})
    assert resp.status_code == 422
