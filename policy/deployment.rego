# Conftest / OPA policy enforcing baseline workload security for Kubernetes
# Deployments. Evaluated against k8s manifests in CI (`make policy`) and locally.
#
# Gates enforced:
#   1. Container images MUST be pinned (no :latest, no missing tag).
#   2. Containers MUST run as non-root.
#   3. Privilege escalation MUST be disabled.
#   4. The root filesystem MUST be read-only.
#   5. CPU/memory limits MUST be set.
package main

import rego.v1

# --- helpers ---------------------------------------------------------------

is_deployment if {
	input.kind == "Deployment"
}

containers contains c if {
	is_deployment
	c := input.spec.template.spec.containers[_]
}

# --- 1. no :latest / untagged images --------------------------------------

deny contains msg if {
	some c in containers
	endswith(c.image, ":latest")
	msg := sprintf("container '%s' uses a mutable ':latest' tag; pin to an immutable version or digest", [c.name])
}

deny contains msg if {
	some c in containers
	not contains(c.image, ":")
	msg := sprintf("container '%s' image '%s' has no tag; pin to an immutable version or digest", [c.name, c.image])
}

# --- 2. non-root -----------------------------------------------------------

deny contains msg if {
	some c in containers
	not c.securityContext.runAsNonRoot == true
	not input.spec.template.spec.securityContext.runAsNonRoot == true
	msg := sprintf("container '%s' must set runAsNonRoot: true (pod or container securityContext)", [c.name])
}

# --- 3. no privilege escalation -------------------------------------------

deny contains msg if {
	some c in containers
	not c.securityContext.allowPrivilegeEscalation == false
	msg := sprintf("container '%s' must set allowPrivilegeEscalation: false", [c.name])
}

# --- 4. read-only root filesystem -----------------------------------------

deny contains msg if {
	some c in containers
	not c.securityContext.readOnlyRootFilesystem == true
	msg := sprintf("container '%s' must set readOnlyRootFilesystem: true", [c.name])
}

# --- 5. resource limits ----------------------------------------------------

deny contains msg if {
	some c in containers
	not c.resources.limits.cpu
	msg := sprintf("container '%s' must declare resources.limits.cpu", [c.name])
}

deny contains msg if {
	some c in containers
	not c.resources.limits.memory
	msg := sprintf("container '%s' must declare resources.limits.memory", [c.name])
}
