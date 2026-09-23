#!/bin/bash
# Kills the current Postgres leader pod via Chaos Mesh (a hard SIGKILL —
# the same kind of abrupt failure a node crash or OOM kill would cause)
# and watches Patroni elect a replacement in real time. Run
# scripts/watch-heartbeat.sh in another terminal first to see the exact
# write-availability gap this causes.
#
# NOTE: because pod-kill bypasses graceful shutdown, the killed pod's old
# DCS member record doesn't get cleanly released. When Kubernetes
# immediately recreates a pod with the same name, that new process will
# often refuse to start ("already running") until the old record's TTL
# expires -- Patroni's own guard against two processes sharing one member
# identity. That produces a brief, expected CrashLoopBackOff on the killed
# pod even after a *different* node has already taken over as leader; it
# is not a bug, and it means the replacement leader is not guaranteed to
# have a different pod name from the one that was killed.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BEFORE="$(kube get pods -n "${NAMESPACE}" -l app=postgres,role=master -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -z "${BEFORE}" ]]; then
  echo "Could not find a current leader (role=master) pod. Run scripts/status.sh first." >&2
  exit 1
fi
log "current leader: ${BEFORE}"

log "applying chaos/pod-kill-postgres-leader.yaml"
kube apply -f "${REPO_ROOT}/chaos/pod-kill-postgres-leader.yaml"

START=$(date +%s)
SAW_GAP=false
log "watching for the leadership gap and its end (allow up to 3m for CrashLoopBackOff recovery)..."
while true; do
  CURRENT="$(kube get pods -n "${NAMESPACE}" -l app=postgres,role=master -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  ELAPSED=$(( $(date +%s) - START ))
  if [[ -z "${CURRENT}" ]]; then
    if [[ "${SAW_GAP}" == false ]]; then
      log "t+${ELAPSED}s: no pod currently holds role=master (write-availability gap started)"
      SAW_GAP=true
    fi
  elif [[ "${SAW_GAP}" == true ]]; then
    log "new leader elected: ${CURRENT} (gap ended at t+${ELAPSED}s)"
    break
  elif [[ "${CURRENT}" != "${BEFORE}" ]]; then
    log "new leader elected: ${CURRENT} (after ${ELAPSED}s, no visible gap at this poll interval)"
    break
  fi
  if [[ ${ELAPSED} -gt 180 ]]; then
    log "no confirmed new leader after 180s, giving up -- check scripts/status.sh"
    break
  fi
  sleep 2
done

log "cleaning up chaos experiment"
kube delete -f "${REPO_ROOT}/chaos/pod-kill-postgres-leader.yaml" --ignore-not-found

"${REPO_ROOT}/scripts/status.sh"
