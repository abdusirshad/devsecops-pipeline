# DevSecOps pipeline — local developer targets.
# Mirrors the CI gates so you can run the same scanners before pushing.
# Scanners are invoked only if installed; otherwise the target prints a hint.

IMAGE_NAME ?= devsecops-sample-api
IMAGE_TAG  ?= local
IMAGE      := $(IMAGE_NAME):$(IMAGE_TAG)

.DEFAULT_GOAL := help

.PHONY: help install test lint build run scan-fs scan-config scan-image \
        sbom policy scan-local clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS=":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

install: ## Install app + dev dependencies
	pip install -r app/requirements-dev.txt

test: ## Run unit tests (pytest)
	pytest -q

lint: ## Lint the Python app (ruff)
	ruff check app

build: ## Build the container image
	docker build -t $(IMAGE) -f app/Dockerfile app

run: ## Run the container locally on :8000
	docker run --rm -p 8000:8000 $(IMAGE)

scan-fs: ## Trivy filesystem scan (vuln + secret)
	@command -v trivy >/dev/null 2>&1 \
		&& trivy fs --scanners vuln,secret --severity CRITICAL,HIGH --ignore-unfixed . \
		|| echo "trivy not installed -> https://aquasecurity.github.io/trivy"

scan-config: ## Trivy IaC/config misconfiguration scan
	@command -v trivy >/dev/null 2>&1 \
		&& trivy config --severity CRITICAL,HIGH . \
		|| echo "trivy not installed -> https://aquasecurity.github.io/trivy"

scan-image: build ## Build then Trivy-scan the image
	@command -v trivy >/dev/null 2>&1 \
		&& trivy image --severity CRITICAL,HIGH --ignore-unfixed $(IMAGE) \
		|| echo "trivy not installed -> https://aquasecurity.github.io/trivy"

sbom: ## Generate an SPDX SBOM with syft
	@command -v syft >/dev/null 2>&1 \
		&& syft dir:app -o spdx-json=sbom.spdx.json && echo "wrote sbom.spdx.json" \
		|| echo "syft not installed -> https://github.com/anchore/syft"

policy: ## Run OPA/Conftest policy tests + enforce on k8s manifests
	@command -v conftest >/dev/null 2>&1 \
		&& conftest verify --policy policy \
		&& conftest test k8s/deployment.yaml policy/conftest/inputs/deployment-pass.yaml --policy policy \
		|| echo "conftest not installed -> https://www.conftest.dev/install"

scan-local: lint test scan-fs scan-config policy sbom ## Run the full local gate set

clean: ## Remove local scan/build artifacts
	rm -f sbom.spdx.json trivy-results.* *.sarif
	rm -rf .pytest_cache .ruff_cache
