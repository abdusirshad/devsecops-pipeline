# DevSecOps Reference Pipeline

[![devsecops](https://img.shields.io/badge/CI-GitHub_Actions-2088FF?logo=githubactions&logoColor=white)](.github/workflows/devsecops.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Python](https://img.shields.io/badge/python-3.13-blue?logo=python&logoColor=white)](app/requirements.txt)

A complete, **green-on-a-public-fork** DevSecOps CI/CD pipeline that scans a small
but real sample service. It demonstrates shift-left security: secrets scanning,
SAST, dependency/container vulnerability scanning, IaC misconfiguration scanning,
policy-as-code gates, SBOM generation, and keyless image signing — wired into a
single GitHub Actions workflow with least-privilege permissions.

> **Author:** Md Irshad — Senior Cloud & AI Platform Engineer
> **Design intent:** every gate uses free/OSS tooling so the workflow passes on a
> fork with **no secrets configured**. Steps that need registry-write or OIDC
> (image push + cosign signing) are guarded to run **only on push to `main`**.

---

## What's in here

```
.
├── app/                          # Sample FastAPI service (the scan target)
│   ├── main.py                   #   health/ready/version/echo endpoints
│   ├── tests/test_main.py        #   pytest unit tests
│   ├── requirements.txt          #   pinned runtime deps
│   ├── requirements-dev.txt      #   test/lint deps
│   ├── Dockerfile                #   multi-stage, non-root, pinned base
│   └── .dockerignore
├── terraform/main.tf             # Hardened S3+KMS sample IaC (scanned, not applied)
├── k8s/deployment.yaml           # Hardened Deployment + Service (scanned + policy-gated)
├── policy/                       # OPA/Rego policy-as-code (Conftest)
│   ├── deployment.rego           #   gates: no :latest, non-root, no privesc, RO-FS, limits
│   ├── deployment_test.rego      #   policy unit tests
│   └── conftest/inputs/          #   pass + fail sample inputs
├── .github/workflows/devsecops.yml
├── .gitleaks.toml                # secrets-scan config (placeholder allowlist)
├── Makefile                      # local mirror of the CI gates
├── pyproject.toml                # ruff + pytest config
├── .env.example
├── .gitignore
└── LICENSE                       # MIT (Md Irshad)
```

Everything referenced above exists in the repo — there are no stub files.

---

## Architecture

The workflow (`.github/workflows/devsecops.yml`) runs eight independent gates in
parallel on every push and pull request, then a final guarded `release` job that
only fires on push to `main`:

```
 push / pull_request
        │
        ├─▶ lint-test        ─ ruff + pytest
        ├─▶ secrets-scan     ─ Gitleaks
        ├─▶ sast             ─ Semgrep (p/ci, p/python, p/security-audit)
        ├─▶ dockerfile-lint  ─ Hadolint
        ├─▶ fs-scan          ─ Trivy fs (vuln+secret) + Trivy config (IaC)
        ├─▶ iac-scan         ─ Checkov (terraform, kubernetes, dockerfile)
        ├─▶ policy           ─ Conftest/OPA (verify + enforce)
        └─▶ sbom             ─ Syft (SPDX SBOM → artifact)
                 │
                 ▼  (all gates green AND event == push to main)
            release          ─ docker build → Trivy image scan
                               → push to GHCR → cosign keyless sign (OIDC)
```

### Why `release` is guarded

`release` declares `permissions: { packages: write, id-token: write }` and is
gated by `if: github.event_name == 'push' && github.ref == 'refs/heads/main'`.
Pull requests and forks never reach it, so they don't need registry credentials
or an OIDC trust relationship — the pipeline still runs fully green for
contributors. Cosign uses **keyless** signing (Sigstore + GitHub OIDC), so there
are no private keys stored anywhere.

---

## Pipeline stages

| # | Job | Tool (OSS) | What it gates | Fails the build on |
|---|-----|------------|---------------|--------------------|
| 1 | `lint-test` | ruff, pytest | Code style + unit correctness | Lint error or failing test |
| 2 | `secrets-scan` | Gitleaks | Hardcoded credentials in code/history | Any unallowlisted secret |
| 3 | `sast` | Semgrep | Insecure code patterns (Python/security-audit) | Any rule match (`--error`) |
| 4 | `dockerfile-lint` | Hadolint | Dockerfile best practices | Warning or worse |
| 5 | `fs-scan` | Trivy (`fs` + `config`) | Dependency CVEs, leaked secrets, IaC misconfig | CRITICAL/HIGH (fixable) |
| 6 | `iac-scan` | Checkov | Terraform / K8s / Dockerfile misconfig | Any failed check |
| 7 | `policy` | Conftest / OPA | Org policy-as-code on K8s manifests | Any `deny` rule |
| 8 | `sbom` | Syft | Software Bill of Materials (SPDX) | (artifact only) |
| 9 | `release`* | Docker, Trivy, Cosign | Image CVEs + provenance | CRITICAL/HIGH in image |

\* `release` runs only on push to `main`.

---

## Security controls matrix

| Control | Mechanism in this repo |
|---------|------------------------|
| Secret detection | Gitleaks gate + `.gitleaks.toml` allowlist for documented placeholders |
| Static analysis (SAST) | Semgrep public rulesets, failing on any finding |
| Dependency scanning (SCA) | Trivy filesystem scan over pinned `requirements*.txt` |
| Container hardening | Multi-stage build, pinned `python:3.13-slim`, non-root `USER 10001`, `HEALTHCHECK` |
| Image vulnerability scan | Trivy image scan **before** push (build fails on CRITICAL/HIGH) |
| IaC misconfiguration | Trivy `config` + Checkov over `terraform/` and `k8s/` |
| Policy-as-code | Conftest/OPA: no `:latest`, non-root, no privesc, read-only root FS, resource limits |
| Supply-chain provenance | Syft SBOM (SPDX) artifact + Cosign **keyless** signing via OIDC |
| Least privilege | Workflow default `permissions: contents: read`; elevated scope only in `release` |
| No long-lived keys | Keyless cosign (Sigstore), GHCR auth via ephemeral `GITHUB_TOKEN` |

The sample `terraform/` and `k8s/` manifests are deliberately written to **pass**
the scanners (KMS encryption + rotation, versioning, public-access block,
TLS-only policy; non-root pod, dropped capabilities, read-only FS, probes,
resource limits) so the reference pipeline is green out of the box.

---

## Quickstart (local)

Requires Python 3.11+ (3.13 recommended). Optional: Docker, and the scanners
listed below.

```bash
# 1. Install app + dev/test dependencies
make install            # pip install -r app/requirements-dev.txt

# 2. Lint + run unit tests
make lint               # ruff check app
make test               # pytest -q   -> 6 passed

# 3. Run the service locally (without Docker)
uvicorn app.main:app --reload
# then: curl localhost:8000/healthz   ->  {"status":"ok"}
#       curl -X POST localhost:8000/echo -H 'content-type: application/json' \
#            -d '{"message":"hi"}'      ->  {"message":"hi","length":2}
```

### Build & run the container

```bash
make build              # docker build -t devsecops-sample-api:local -f app/Dockerfile app
make run                # docker run --rm -p 8000:8000 devsecops-sample-api:local
```

---

## Running the security gates locally

The `Makefile` mirrors the CI gates. Each scan target runs the tool **only if it
is installed**, otherwise it prints an install hint — so the Makefile never hard-fails
just because a scanner is missing.

```bash
make scan-fs       # Trivy filesystem scan (CVEs + secrets)
make scan-config   # Trivy IaC/config misconfiguration scan
make scan-image    # build, then Trivy image scan
make sbom          # Syft SPDX SBOM -> sbom.spdx.json
make policy        # Conftest: policy unit tests + enforce on k8s manifests
make scan-local    # lint + test + scan-fs + scan-config + policy + sbom
```

Install the OSS scanners:

- **Trivy** — https://aquasecurity.github.io/trivy
- **Syft** — https://github.com/anchore/syft
- **Conftest** — https://www.conftest.dev/install
- **Gitleaks** — https://github.com/gitleaks/gitleaks
- **Semgrep** — `pip install semgrep`
- **Hadolint** — https://github.com/hadolint/hadolint
- **Checkov** — `pip install checkov`

### Policy demo (no extra app needed)

```bash
# Compliant manifest -> 0 denials
conftest test k8s/deployment.yaml --policy policy

# Deliberately insecure manifest -> 6 denials (latest tag, root, privesc,
# writable root FS, missing cpu + memory limits)
conftest test policy/conftest/inputs/deployment-fail.yaml --policy policy

# Run the policy's own unit tests
conftest verify --policy policy        # 3 tests, 3 passed
```

---

## How to verify

| Check | Command | Expected |
|-------|---------|----------|
| App compiles | `python -m py_compile app/main.py` | no output |
| Unit tests | `pytest -q` | `6 passed` |
| Lint clean | `ruff check .` | `All checks passed!` |
| Workflow is valid YAML | `python -c "import yaml;yaml.safe_load(open('.github/workflows/devsecops.yml'))"` | no error |
| Policy unit tests | `conftest verify --policy policy` | `3 tests, 3 passed` |
| Policy enforcement | `conftest test policy/conftest/inputs/deployment-fail.yaml --policy policy` | 6 failures |
| Image builds | `docker build -f app/Dockerfile app` | image built |

---

## Notes / honesty

- The `terraform/` and `k8s/` manifests are **illustrative IaC for scanning**;
  CI never runs `terraform apply` or `kubectl apply` and there are no cloud
  credentials in this repo.
- The `EXAMPLE_API_TOKEN` in `.env.example` is a documented placeholder
  (`your-token-here`), allowlisted in `.gitleaks.toml`. There are no real secrets.
- Pinned action and tool versions reflect releases current as of 2026 and should
  be reviewed by Dependabot/Renovate before adopting in a real project.

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Md Irshad.
