#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  log "kind cluster '${CLUSTER_NAME}' already exists, skipping create"
else
  log "creating kind cluster '${CLUSTER_NAME}' (1 control-plane + 3 workers)"
  kind create cluster --config "${REPO_ROOT}/cluster/kind-config.yaml"
fi

kube cluster-info
