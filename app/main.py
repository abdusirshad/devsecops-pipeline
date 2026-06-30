"""Minimal FastAPI service used as the scan target for the DevSecOps pipeline.

The service is intentionally tiny but real: it exposes a health endpoint, a
readiness probe, and a small echo endpoint with input validation so that the
SAST / dependency / container scanners have genuine code and dependencies to
analyse.
"""
from __future__ import annotations

import os
import platform
from datetime import UTC, datetime

from fastapi import FastAPI
from pydantic import BaseModel, Field

APP_NAME = "devsecops-sample-api"
APP_VERSION = os.getenv("APP_VERSION", "1.0.0")

app = FastAPI(
    title=APP_NAME,
    version=APP_VERSION,
    description="Sample service scanned by the reference DevSecOps pipeline.",
)


class EchoRequest(BaseModel):
    """Request body for the echo endpoint."""

    message: str = Field(..., min_length=1, max_length=280, description="Text to echo back.")


class EchoResponse(BaseModel):
    message: str
    length: int


@app.get("/healthz", tags=["ops"])
def healthz() -> dict[str, str]:
    """Liveness probe."""
    return {"status": "ok"}


@app.get("/readyz", tags=["ops"])
def readyz() -> dict[str, str]:
    """Readiness probe."""
    return {"status": "ready"}


@app.get("/version", tags=["ops"])
def version() -> dict[str, str]:
    """Return build/runtime metadata."""
    return {
        "name": APP_NAME,
        "version": APP_VERSION,
        "python": platform.python_version(),
        "time": datetime.now(UTC).isoformat(),
    }


@app.post("/echo", response_model=EchoResponse, tags=["api"])
def echo(payload: EchoRequest) -> EchoResponse:
    """Echo the supplied message back with its length."""
    return EchoResponse(message=payload.message, length=len(payload.message))
