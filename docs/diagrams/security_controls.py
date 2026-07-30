"""Render the "shift-left" security-controls coverage map.

Output: security_controls.png (in this directory).

Usage:
    pip install -r requirements.txt      # + Graphviz `dot` on PATH
    python security_controls.py

Maps each SDLC stage (code -> dependencies -> container -> IaC -> policy ->
artifact / supply-chain) to the OSS tool that covers it in this pipeline, and
labels whether that control is a HARD GATE or REPORT-ONLY.

Author: Md Irshad
"""
from __future__ import annotations

from diagrams import Cluster, Diagram, Edge
from diagrams.generic.blank import Blank
from diagrams.onprem.container import Docker
from diagrams.onprem.vcs import Git
from diagrams.programming.language import Python

GATE = "#1a7f37"
REPORT = "#bf8700"

GRAPH_ATTR = {
    "fontsize": "18",
    "labelloc": "t",
    "pad": "0.5",
    "nodesep": "0.4",
    "ranksep": "0.9",
    "bgcolor": "white",
}

with Diagram(
    "Shift-Left Security Controls  (SDLC stage -> tool)",
    filename="security_controls",
    show=False,
    direction="LR",
    graph_attr=GRAPH_ATTR,
    outformat="png",
):
    with Cluster("1. Code"):
        code = Python("Semgrep (SAST)\nreport-only")
        secrets = Git("Gitleaks (secrets)\nHARD GATE")

    with Cluster("2. Dependencies"):
        deps = Blank("Trivy fs (SCA / CVEs)\nreport-only")

    with Cluster("3. Container"):
        dfile = Docker("Hadolint (Dockerfile)\nHARD GATE")
        img = Blank("Trivy image\n(release only)")

    with Cluster("4. Infrastructure (IaC)"):
        iac = Blank("Checkov + Trivy config\nreport-only")

    with Cluster("5. Policy-as-code"):
        policy = Blank("Conftest / OPA\nHARD GATE")

    with Cluster("6. Artifact / Supply chain"):
        sbom = Blank("Syft SBOM (SPDX)\nartifact")
        sign = Blank("cosign keyless\n(release only)")

    # Left-to-right shift-left progression.
    code >> Edge(style="invis") >> deps >> Edge(style="invis") >> dfile
    dfile >> Edge(style="invis") >> iac >> Edge(style="invis") >> policy
    policy >> Edge(style="invis") >> sbom

    secrets >> Edge(color=GATE, style="bold") >> deps
    deps >> Edge(color=REPORT, style="dashed") >> img
    iac >> Edge(color=GATE, style="bold") >> policy
    sbom >> Edge(color=GATE, style="bold") >> sign
