#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

kube apply -f "${REPO_ROOT}/manifests/00-namespace.yaml"

log "deploying etcd (the Raft layer)"
kube apply -f "${REPO_ROOT}/manifests/etcd/service.yaml"
kube apply -f "${REPO_ROOT}/manifests/etcd/statefulset.yaml"

log "waiting for all 3 etcd pods to be ready"
kube rollout status statefulset/etcd -n "${NAMESPACE}" --timeout=180s

log "deploying Patroni-managed PostgreSQL"
kube apply -f "${REPO_ROOT}/manifests/patroni/rbac.yaml"
kube apply -f "${REPO_ROOT}/manifests/patroni/secret.yaml"
kube apply -f "${REPO_ROOT}/manifests/patroni/services.yaml"
kube apply -f "${REPO_ROOT}/manifests/patroni/statefulset.yaml"

log "waiting for all 3 postgres pods to be ready (leader election + replica cloning happens here)"
kube rollout status statefulset/postgres -n "${NAMESPACE}" --timeout=300s

log "deploy complete. Run scripts/status.sh for a full picture."
