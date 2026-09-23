#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if kube get ns chaos-mesh >/dev/null 2>&1; then
  log "chaos-mesh namespace already exists, skipping install"
  exit 0
fi

log "installing Chaos Mesh via its official kind-targeted installer"
log "(downloads and runs https://mirrors.chaos-mesh.org/latest/install.sh)"
curl -sSL https://mirrors.chaos-mesh.org/latest/install.sh | bash -s -- --local kind --name "${CLUSTER_NAME}"
