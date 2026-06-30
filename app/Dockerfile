# syntax=docker/dockerfile:1.7
# ----------------------------------------------------------------------------
# Multi-stage, non-root, pinned-base image for the sample API.
# Built and scanned (Trivy image scan + Hadolint) by the DevSecOps pipeline.
# ----------------------------------------------------------------------------

# --- build stage: install deps into an isolated prefix -----------------------
FROM python:3.13-slim AS build

WORKDIR /app

# hadolint ignore=DL3008  (slim base; no apt packages required)
ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

COPY requirements.txt ./
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# --- runtime stage: minimal, non-root ---------------------------------------
FROM python:3.13-slim AS runtime

# OCI labels for provenance / SBOM correlation.
LABEL org.opencontainers.image.title="devsecops-sample-api" \
      org.opencontainers.image.source="https://github.com/abdusirshad/devsecops-pipeline" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.authors="Md Irshad"

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    APP_VERSION=1.0.0

# Create an unprivileged user to run the app (no shell, no login).
RUN groupadd --gid 10001 appuser \
    && useradd --uid 10001 --gid appuser --no-create-home --shell /usr/sbin/nologin appuser

WORKDIR /app

# Copy installed site-packages from the build stage.
COPY --from=build /install /usr/local
COPY main.py ./

USER 10001

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz').status==200 else 1)"]

ENTRYPOINT ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
