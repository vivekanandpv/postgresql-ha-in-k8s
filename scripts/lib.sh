#!/bin/bash
# Shared variables/helpers sourced by every script in this directory.
set -euo pipefail

CLUSTER_NAME="raft-lab"
NAMESPACE="raft-lab"
IMAGE="raft-lab/patroni-postgres:local"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
  echo ">> $*" >&2
}

kube() {
  kubectl --context "kind-${CLUSTER_NAME}" "$@"
}
