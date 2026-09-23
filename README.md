# postgresql-ha-in-k8s

A reference project demonstrating **RAFT-based distributed consensus,
automatic failover, and network-partition tolerance** for PostgreSQL on
Kubernetes, using [etcd](https://etcd.io/) (RAFT) + [Patroni](https://patroni.readthedocs.io/)
for leader election and [Chaos Mesh](https://chaos-mesh.org/) for fault
injection.

See [docs/architecture.md](docs/architecture.md) for how the pieces fit
together and why etcd+Patroni (rather than PostgreSQL alone, or MySQL) is
the right stack for a genuine RAFT demo.

> An earlier, naive version of this repo (`legacy-manual-failover/`) hardcoded
> `postgres-0` as the primary with no consensus and no automatic failover —
> kept around for contrast. This README describes the current version.

## What you'll see

- **etcd** running as a real 3-node RAFT group (you can watch its term
  number and leader change with `etcdctl endpoint status`).
- **Patroni** using that RAFT group to elect exactly one PostgreSQL
  primary at a time, and to fail over automatically when it dies.
- **Two Kubernetes Services** (`postgres-primary`, `postgres-replica`)
  that always route to the current truth, with no client reconfiguration
  needed across a failover.
- **Chaos Mesh** scenarios to kill the leader pod, fail a follower, and
  network-partition a minority node — with scripts that watch the cluster
  react in real time.

## Prerequisites

- Docker (running)
- [kind](https://kind.sigs.k8s.io/)
- `kubectl`
- `curl` (used by the Chaos Mesh installer script)

## Quickstart

```bash
make up              # create a 1 control-plane + 3 worker kind cluster
make build            # build the Patroni+PostgreSQL image and load it into kind
make deploy            # deploy etcd (3 nodes) then Patroni-managed PostgreSQL (3 nodes)
make status             # see the Raft view, Patroni's view, and current role labels
make chaos-install        # install Chaos Mesh (only needed once)
```

Then, in one terminal, start the write-availability probe:

```bash
make watch
```

...and in another, run a demo:

```bash
make demo-kill-leader      # kill the current PostgreSQL leader, watch re-election
make demo-kill-follower     # fail a replica for 60s, watch it catch back up
make demo-partition          # isolate one node from the other two for 3 minutes
```

Tear everything down with `make down`.

## What to actually watch during each demo

**`make demo-kill-leader`** — the leader pod is deleted. `make watch`
should show a short run of `FAIL` lines (typically well under the 30s DCS
lease TTL, often just a handful of seconds), then resume `OK` once a
majority of etcd members grant the new leader's lease and the new primary
starts accepting writes. `make status` afterwards shows a *different* pod
now holding `role=master`.

**`make demo-kill-follower`** — a replica is made unavailable for 60s
without touching the leader. `make watch` should show **zero** `FAIL`
lines throughout — proof that follower loss doesn't affect availability,
in contrast to leader loss.

**`make demo-partition`** — one node (its Postgres pod *and* its etcd
pod together) is cut off from the other two, bidirectionally, for 3
minutes. This is the important one:

- The isolated node can never see a majority of etcd (it's 1 of 3), so it
  can never win a leader election, no matter what it thinks locally.
- The majority side (2 of 3) still has an etcd Raft quorum, so if the
  isolated node *happened to be* the primary, the majority elects a new
  one after the lease expires.
- At no point do both sides believe they are the primary — `make status`
  during the partition will show at most one `Leader` in `patronictl
  list`, queried from the majority side. This is what an **odd-sized**
  Raft membership guarantees: a 1-vs-2 split can never produce two
  quorums.

Note: the node that regains leadership on the majority side is decided by
a race and is **not guaranteed to differ** from the pre-partition leader —
in testing, partitioning away the existing leader produced a new leader
on the majority side; a separate leader-*kill* test re-elected the exact
same pod once it restarted and rejoined in time. Both are correct
outcomes; what matters is that exactly one leader ever exists.

If you want to see what happens *without* this guarantee, try changing
`replicas: 3` to `replicas: 2` in `manifests/etcd/statefulset.yaml` and
`manifests/patroni/statefulset.yaml` (and the corresponding
`--initial-cluster` / `PATRONI_ETCD3_HOSTS` lists) — a 1-vs-1 split has no
majority on either side, and you'll see the whole cluster correctly
refuse to elect anyone rather than accept writes on two sides.

## Project layout

```
cluster/                kind cluster definition
docker/patroni-postgres/ Dockerfile + static Patroni config + role-labeling callback
manifests/etcd/          the RAFT layer: a 3-node etcd StatefulSet
manifests/patroni/       RBAC, secret, Services, the Patroni/PostgreSQL StatefulSet
chaos/                   Chaos Mesh PodChaos/NetworkChaos scenario manifests
scripts/                 setup, deploy, status, and demo automation (see Makefile)
docs/architecture.md     how etcd+Patroni map to RAFT concepts, tunables, diagrams
legacy-manual-failover/  the original hand-rolled, non-consensus version
```

## Validated against a live cluster

This repo was built and exercised end-to-end on a real kind cluster
(3 workers, one etcd/Patroni pod per node) before being committed, not
just checked for YAML/syntax validity. Observed results:

- **Leader kill**: ~27s write-availability gap (bounded by the 30s DCS
  `ttl`), then a clean promotion with the WAL timeline incrementing.
- **Network partition (flagship)**: the majority side (2 of 3) correctly
  elected a new leader without ever losing its own quorum view; the
  isolated minority never claimed leadership at any point; on
  reconnection the previously-isolated node rejoined as a replica with
  zero lag, no manual intervention.
- **Follower failure**: zero write-availability impact throughout, full
  catch-up after the failure window ended.

Two non-obvious things that came out of that testing, both already
reflected in the manifests/scripts:

1. The official `quay.io/coreos/etcd` image has no shell, so
   `manifests/etcd/statefulset.yaml` drives etcd entirely through
   `args:` with Kubernetes' own `$(POD_NAME)` substitution rather than a
   wrapper script.
2. Patroni's `on_role_change` callback only fires on a role
   *transition* — it does not fire for the very first bootstrap. The
   image's `patroni.yml` registers the same script for `on_start` too,
   which is what actually labels a freshly-bootstrapped cluster's pods.

## Notes and caveats

- This is a **learning/demo reference**, not a production template:
  credentials are in plaintext `Secret` manifests, TLS is not configured
  for etcd or PostgreSQL client connections, and etcd/Patroni cluster
  membership is static (3 replicas, no dynamic add/remove).
- MySQL was intentionally not used here: neither Group Replication nor
  Galera implement RAFT (see `docs/architecture.md`). If you specifically
  need a MySQL-based demo, look at `dolthub/dolt` (uses a Go RAFT library)
  or MySQL Group Replication with an honest label of "Paxos-derived", not
  "RAFT".
