"""Render the end-to-end DevSecOps pipeline as a left-to-right flow.

Output: pipeline.png (in this directory).

Usage:
    pip install -r requirements.txt      # + Graphviz `dot` on PATH
    python pipeline.py

The diagram mirrors .github/workflows/devsecops.yml exactly:
  Commit / PR  ->  eight parallel CI jobs  ->  [workflow_dispatch] release.
HARD GATES (fail the build) are drawn solid green; REPORT-ONLY scanners
(audit / soft-fail) are drawn dashed amber; the on-demand release chain is blue.

Author: Md Irshad
"""
from __future__ import annotations

from diagrams import Cluster, Diagram, Edge
from diagrams.generic.blank import Blank
from diagrams.onprem.ci import GithubActions
from diagrams.onprem.container import Docker
from diagrams.onprem.vcs import Git, Github
from diagrams.programming.language import Python

GATE = "#1a7f37"      # hard gate  (blocks merge)
REPORT = "#bf8700"    # report-only (audit / soft-fail)
RELEASE = "#0969da"   # on-demand release chain

GRAPH_ATTR = {
    "fontsize": "18",
    "labelloc": "t",
    "pad": "0.5",
    "splines": "spline",
    "nodesep": "0.5",
    "ranksep": "1.1",
    "bgcolor": "white",
}

with Diagram(
    "DevSecOps Reference Pipeline",
    filename="pipeline",
    show=False,
    direction="LR",
    graph_attr=GRAPH_ATTR,
    outformat="png",
):
    trigger = Github("Commit / Pull Request\n(push & PR to main)")

    with Cluster("CI gates  (run on every push + PR, in parallel)"):
        lint = Python("lint-test\nruff + pytest\nHARD GATE")
        gitleaks = Git("secrets-scan\nGitleaks\nHARD GATE")
        hadolint = Docker("dockerfile-lint\nHadolint\nHARD GATE")
        opa = Blank("policy\nConftest / OPA\nHARD GATE")

        semgrep = Blank("sast\nSemgrep\nreport-only")
        trivy_fs = Blank("fs-scan\nTrivy fs + config\nreport-only")
        checkov = Blank("iac-scan\nCheckov\nreport-only")
        syft = Blank("sbom\nSyft (SPDX)\nartifact")

    with Cluster("release  [workflow_dispatch only — manual]"):
        build = Docker("docker build")
        trivy_img = Blank("Trivy image scan")
        cosign = Blank("cosign keyless sign\n(Sigstore + OIDC)")
        ghcr = GithubActions("push -> GHCR")

    # Trigger fans out to every gate.
    for gate in (lint, gitleaks, hadolint, opa):
        trigger >> Edge(color=GATE, style="bold", label="gate") >> gate
    for rep in (semgrep, trivy_fs, checkov, syft):
        trigger >> Edge(color=REPORT, style="dashed", label="report") >> rep

    # All gates green + manual dispatch -> release chain.
    opa >> Edge(color=RELEASE, style="bold", label="all green +\ndispatch") >> build
    build >> Edge(color=RELEASE) >> trivy_img >> Edge(color=RELEASE) >> cosign >> Edge(color=RELEASE) >> ghcr
