#!/bin/bash
# Patroni callback: invoked as `on-role-change.sh <action> <role> <scope>`
# whenever this node's role changes. We use it to keep a `role` label on
# this pod in sync with what Patroni/etcd's Raft log actually elected, so
# the postgres-primary / postgres-replica Services (which select on that
# label) always route to the current truth instead of a stale pod name.
set -euo pipefail

ROLE="${2:-}"
POD_NAME="$(hostname)"
NAMESPACE="$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)"

case "$ROLE" in
  master|standby_leader)
    LABEL_VALUE="master"
    ;;
  replica)
    LABEL_VALUE="replica"
    ;;
  *)
    LABEL_VALUE="none"
    ;;
esac

kubectl label pod "${POD_NAME}" role="${LABEL_VALUE}" --overwrite -n "${NAMESPACE}"
