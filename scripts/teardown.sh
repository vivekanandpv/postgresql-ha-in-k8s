#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "deleting kind cluster '${CLUSTER_NAME}'"
kind delete cluster --name "${CLUSTER_NAME}"
