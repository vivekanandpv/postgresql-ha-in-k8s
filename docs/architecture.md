# Architecture

## Why etcd + Patroni, and not "PostgreSQL with RAFT"

PostgreSQL itself has no RAFT implementation — its built-in replication
(streaming/WAL shipping) is simple primary→replica copying with no
leader-election protocol attached. MySQL Group Replication and Galera are
similarly *not* RAFT (they use Paxos-derived certification or state-machine
replication instead).

The standard way to get genuine RAFT-driven consensus in front of
PostgreSQL is **etcd**, whose consensus core is the canonical Go
implementation of the RAFT paper, combined with **Patroni**, a PostgreSQL
HA agent that:

1. runs as a sidecar-less supervisor process next to `postgres` on every
   node,
2. stores cluster state (who is leader, config, timeline) in etcd instead
   of deciding it locally, and
3. reacts to what etcd's Raft log resolves — acquiring a leader lease,
   promoting/demoting itself, and rewiring streaming replication — rather
   than implementing any consensus logic itself.

So: **etcd does the RAFT**, **Patroni translates RAFT outcomes into
PostgreSQL actions**. This is the same architecture used in most
production Patroni deployments (Zalando's postgres-operator, Crunchy's
PGO, etc.), just built here from first principles instead of via an
operator, so every moving part is visible in this repo.

## Topology

```
                         ┌─────────────────────────────┐
                         │      etcd Raft group        │
                         │   (StatefulSet: etcd, x3)    │
                         │                              │
                         │   etcd-0 ── etcd-1 ── etcd-2  │
                         │     (peer traffic :2380,      │
                         │      client traffic :2379)    │
                         └───────────────┬──────────────┘
                                         │
                     leader lease + cluster state (DCS)
                                         │
        ┌────────────────────────────────┼────────────────────────────────┐
        │                                │                                │
  ┌─────▼─────┐                   ┌──────▼─────┐                   ┌──────▼─────┐
  │postgres-0 │  streaming repl.  │postgres-1  │  streaming repl.  │postgres-2  │
  │ Patroni + │◄──────────────────┤ Patroni +  │◄──────────────────┤ Patroni +  │
  │ PostgreSQL│                   │ PostgreSQL │                   │ PostgreSQL │
  └─────┬─────┘                   └──────┬─────┘                   └──────┬─────┘
        │  role label kept in sync by on-role-change.sh callback          │
        └──────────────────────┬──────────────────────────────────────────┘
                                │
              ┌─────────────────┴──────────────────┐
              │                                     │
     Service: postgres-primary            Service: postgres-replica
     selector: role=master                selector: role=replica
     (always the current leader)          (all current standbys)
```

Each `postgres-N` pod and each `etcd-N` pod is scheduled onto a distinct
kind worker node (`podAntiAffinity` + a 3-worker kind cluster), so a pod
kill or network partition in the demos below acts like a real per-node
failure rather than two processes sharing one kernel.

## Where "leader election" actually happens

1. Every Patroni instance tries to acquire a leader key/lease in etcd
   (`bootstrap.dcs.ttl: 30`, `loop_wait: 10` in
   `docker/patroni-postgres/patroni.yml`). etcd's Raft log is what
   guarantees only one node can hold that lease at a time — this is the
   actual consensus step.
2. Whichever Patroni instance holds the lease promotes its local
   PostgreSQL to primary (or keeps it primary) and configures the other
   two as streaming replicas.
3. If the leader's lease expires without renewal (pod killed, node
   partitioned away from etcd's majority, etc.), the surviving Patroni
   instances race to acquire it. Because etcd itself required a Raft
   majority to grant/renew the *original* lease, and requires a majority
   to grant a *new* one, **only a node that can reach a majority of etcd
   members can ever become leader** — which is exactly what prevents
   split-brain during network partitions (see
   `chaos/network-partition-minority.yaml`).
4. `on-role-change.sh` (baked into the image, wired via
   `postgresql.callbacks.on_role_change`) is Patroni's notification hook
   for step 2/3 — it patches this pod's `role` label, which is what the
   `postgres-primary` / `postgres-replica` Services select on. Note this
   labeling is a demo convenience specific to running Patroni with **etcd**
   as its DCS; if you instead pointed Patroni at Kubernetes itself as the
   DCS (`kubernetes` section instead of `etcd3`), it would manage these
   labels natively and you would not need this callback — but then
   Kubernetes' own resourceVersion-based optimistic concurrency would be
   doing the consensus instead of Raft, which defeats the point of this
   repo.

## Key tunables

| Setting | Where | Effect |
|---|---|---|
| `bootstrap.dcs.ttl` | `docker/patroni-postgres/patroni.yml` | How long a leader lease survives without renewal before another node can take over. Lower = faster failover, more sensitive to transient network blips. |
| `bootstrap.dcs.loop_wait` | same | How often Patroni re-evaluates cluster state / renews its lease. |
| `--auto-compaction-retention` | `manifests/etcd/statefulset.yaml` | etcd history retention; irrelevant to failover behavior, just keeps the demo's etcd disk usage bounded. |

After first bootstrap, `bootstrap.dcs.*` is written into etcd once and
becomes the live config; edit it with `patronictl edit-config` against a
running cluster rather than editing the YAML file and redeploying.

## Chaos scenarios and what they isolate

| Scenario | File | What it tests |
|---|---|---|
| Kill the leader | `chaos/pod-kill-postgres-leader.yaml` | Leader-election latency, write-availability gap |
| Fail a follower | `chaos/pod-failure-postgres-follower.yaml` | Replication catch-up, confirms followers are non-critical for availability |
| Network-partition the minority | `chaos/network-partition-minority.yaml` | Split-brain prevention via Raft's majority-quorum requirement |

See the repo root `README.md` for how to run each one.
