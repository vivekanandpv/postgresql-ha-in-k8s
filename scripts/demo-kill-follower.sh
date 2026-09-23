#!/bin/bash
# Fails a replica for 60s (chaos/pod-failure-postgres-follower.yaml) and
# watches it drop out of, then rejoin, Patroni's cluster view via streaming
# replication catch-up. No leader change happens here -- the point is to
# show that losing a follower does NOT affect write availability at all,
# in contrast to demo-kill-leader.sh.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TARGET="$(kube get pods -n "${NAMESPACE}" -l app=postgres,role=replica -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -z "${TARGET}" ]]; then
  echo "Could not find a replica (role=replica) pod. Run scripts/status.sh first." >&2
  exit 1
fi
log "target replica: ${TARGET}"

log "applying chaos/pod-failure-postgres-follower.yaml (60s failure window)"
kube apply -f "${REPO_ROOT}/chaos/pod-failure-postgres-follower.yaml"

log "leader should be unaffected throughout -- spot check:"
kube get pods -n "${NAMESPACE}" -l app=postgres,role=master -o custom-columns='NAME:.metadata.name,STATUS:.status.phase'

log "waiting ~70s for the failure window to end and the replica to catch back up"
sleep 70

kube delete -f "${REPO_ROOT}/chaos/pod-failure-postgres-follower.yaml" --ignore-not-found

"${REPO_ROOT}/scripts/status.sh"
