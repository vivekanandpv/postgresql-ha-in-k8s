#!/bin/bash
# Run this in its own terminal *before* triggering a chaos scenario. It
# writes one timestamped row per second to postgres-primary and prints
# success/failure for each attempt, so the exact write-availability gap
# during a failover or partition is visible as a run of FAIL lines.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

export PGPASSWORD=postgres
CONN="host=postgres-primary.${NAMESPACE}.svc.cluster.local port=5432 user=postgres dbname=postgres connect_timeout=2"

log "starting heartbeat writer against postgres-primary (ctrl-c to stop)"
kube run heartbeat-writer -n "${NAMESPACE}" --rm -it --restart=Never \
  --image=postgres:17 \
  --env="PGPASSWORD=postgres" \
  -- bash -c '
    CONN="host=postgres-primary.'"${NAMESPACE}"'.svc.cluster.local port=5432 user=postgres dbname=postgres connect_timeout=2"
    psql "$CONN" -c "CREATE TABLE IF NOT EXISTS heartbeat (id serial PRIMARY KEY, written_at timestamptz NOT NULL DEFAULT now(), source text NOT NULL)" >/dev/null 2>&1
    while true; do
      TS="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
      if psql "$CONN" -c "INSERT INTO heartbeat (source) VALUES ('"'"'watch-heartbeat'"'"')" >/dev/null 2>&1; then
        echo "${TS}  OK"
      else
        echo "${TS}  FAIL (no primary reachable)"
      fi
      sleep 1
    done
  '
