# Unit tests for the Conftest policy. Run with: `conftest verify --policy policy`
package main

import rego.v1

# A fully-compliant deployment should produce zero denials.
test_compliant_deployment_passes if {
	count(deny) == 0 with input as compliant
}

# A :latest image should be denied.
test_latest_tag_denied if {
	some msg in deny with input as bad_latest
	contains(msg, ":latest")
}

# A root container should be denied.
test_root_container_denied if {
	count(deny) > 0 with input as bad_root
}

compliant := {
	"apiVersion": "apps/v1",
	"kind": "Deployment",
	"metadata": {"name": "ok"},
	"spec": {"template": {"spec": {
		"securityContext": {"runAsNonRoot": true},
		"containers": [{
			"name": "api",
			"image": "ghcr.io/abdusirshad/devsecops-sample-api:1.0.0",
			"securityContext": {
				"runAsNonRoot": true,
				"allowPrivilegeEscalation": false,
				"readOnlyRootFilesystem": true,
			},
			"resources": {"limits": {"cpu": "250m", "memory": "128Mi"}},
		}],
	}}},
}

bad_latest := {
	"apiVersion": "apps/v1",
	"kind": "Deployment",
	"metadata": {"name": "bad"},
	"spec": {"template": {"spec": {
		"securityContext": {"runAsNonRoot": true},
		"containers": [{
			"name": "api",
			"image": "ghcr.io/abdusirshad/devsecops-sample-api:latest",
			"securityContext": {
				"runAsNonRoot": true,
				"allowPrivilegeEscalation": false,
				"readOnlyRootFilesystem": true,
			},
			"resources": {"limits": {"cpu": "250m", "memory": "128Mi"}},
		}],
	}}},
}

bad_root := {
	"apiVersion": "apps/v1",
	"kind": "Deployment",
	"metadata": {"name": "bad"},
	"spec": {"template": {"spec": {"containers": [{
		"name": "api",
		"image": "ghcr.io/abdusirshad/devsecops-sample-api:1.0.0",
		"securityContext": {"allowPrivilegeEscalation": true},
	}]}}},
}
