#!/bin/bash
# A full snapshot: Raft view (etcd) + Patroni's view + which pod each
# Service currently routes to. Run this before/during/after any chaos
# scenario to see what actually happened.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "===== etcd Raft cluster status ====="
kube exec -n "${NAMESPACE}" etcd-0 -- etcdctl \
  --endpoints=http://etcd-0.etcd-headless.${NAMESPACE}.svc.cluster.local:2379,http://etcd-1.etcd-headless.${NAMESPACE}.svc.cluster.local:2379,http://etcd-2.etcd-headless.${NAMESPACE}.svc.cluster.local:2379 \
  endpoint status --write-out=table || true

echo
echo "===== Patroni cluster status ====="
FIRST_RUNNING_POD="$(kube get pods -n "${NAMESPACE}" -l app=postgres --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "${FIRST_RUNNING_POD}" ]]; then
  kube exec -n "${NAMESPACE}" "${FIRST_RUNNING_POD}" -- patronictl -c /etc/patroni/patroni.yml list || true
else
  echo "(no running postgres pods)"
fi

echo
echo "===== role labels (what the Services see) ====="
kube get pods -n "${NAMESPACE}" -l app=postgres -o custom-columns='NAME:.metadata.name,NODE:.spec.nodeName,ROLE-LABEL:.metadata.labels.role,STATUS:.status.phase'

echo
echo "===== active chaos experiments ====="
kube get podchaos,networkchaos -n "${NAMESPACE}" 2>/dev/null || echo "(none, or Chaos Mesh not installed)"
