# Broaden home-node storage from Hermes-only to general-purpose

## Status

Accepted — supersedes the scoping rationale in [ADR-0002](0002-home-node-pinning-and-scoped-storage.md)

## Context

ADR-0002 scoped `local-path-provisioner` narrowly — explicitly "not a cluster-wide default StorageClass" — for Hermes Agent's state PVC alone. Monitoring's TSDB and log storage (see [ADR-0008](0008-victoriametrics-and-victorialogs.md)) now also need persistent storage, and the home node remains the only node with real disk — Hetzner CSI/Longhorn stay disabled on the control planes, per ADR-0002's own context.

## Decision

Broaden the same `local-path-provisioner` into a general-purpose home-node-scoped StorageClass, usable by any workload that tolerates the home-node taint — not a second provisioner per app.

## Consequences

Hermes Agent, the monitoring TSDB, and log storage now share the home node's disk/CPU/RAM (i5-4570T, 16GB RAM, ~500GB SSD) rather than each getting isolated resources. Accepted given current headroom; worth revisiting (e.g. enabling Hetzner CSI on the control planes for some workloads) if the home node becomes a bottleneck.

## Considered options

- A second, separate storage path (e.g. Hetzner CSI on the control planes) for non-Hermes workloads — rejected for now as unnecessary complexity while the home node has spare capacity.
