#!/bin/bash
# The flagship demo: isolates node 2 (postgres-2 + etcd-2) from the other
# two nodes for 3 minutes (chaos/network-partition-minority.yaml). Watches
# both sides so you can see the majority side keep an etcd leader and
# (if needed) elect a new Postgres primary, while the isolated minority
# never does -- proving no split-brain is possible with 3 Raft members.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "pre-partition status:"
"${REPO_ROOT}/scripts/status.sh"

log "applying chaos/network-partition-minority.yaml (postgres-2+etcd-2 isolated for 3m)"
kube apply -f "${REPO_ROOT}/chaos/network-partition-minority.yaml"

log "polling status every 10s for 3 minutes -- watch for:"
log "  - etcd: only 2 of 3 members report a leader/term progressing (the majority side)"
log "  - patronictl: at most one pod anywhere shows 'Leader', never two"
for i in $(seq 1 18); do
  sleep 10
  echo
  echo "----- t+$(( i * 10 ))s -----"
  kube exec -n "${NAMESPACE}" etcd-0 -- etcdctl \
    --endpoints=http://etcd-0.etcd-headless.${NAMESPACE}.svc.cluster.local:2379,http://etcd-1.etcd-headless.${NAMESPACE}.svc.cluster.local:2379 \
    endpoint status --write-out=table 2>/dev/null || echo "(majority-side etcd query failed/still settling)"
  FIRST_RUNNING_POD="$(kube get pods -n "${NAMESPACE}" -l app=postgres --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [[ -n "${FIRST_RUNNING_POD}" ]] && kube exec -n "${NAMESPACE}" "${FIRST_RUNNING_POD}" -- patronictl -c /etc/patroni/patroni.yml list 2>/dev/null
done

log "partition window over (or run 'kube delete -f chaos/network-partition-minority.yaml' to end it early)"
"${REPO_ROOT}/scripts/status.sh"
