# Pin Hermes Agent to the home node, with home-node-scoped local-path storage

## Status

Accepted

## Context

This cluster's schedulable nodes are 3 Hetzner CX23 control planes (`../../devops/opentofu-infra`) — which also hold etcd/API-server for the whole cluster, receive unattended OS/k3s upgrades with `kured`-driven reboots, and have zero PVC storage class provisioned (Hetzner CSI and Longhorn both explicitly disabled) — and one home node, `k3s-agent-hml` (`../../devops/homelab-nix`), tainted `NoSchedule` by default, with dedicated local disk and no automated reboot/replacement churn. Hermes Agent is a stateful, always-on, single-instance daemon that may execute agent-issued code (see [0003](0003-local-execution-with-gvisor-not-docker.md)).

## Decision

Schedule Hermes Agent on the home node only, via a toleration for `node-role.kubernetes.io/home=true:NoSchedule` and a `nodeSelector` of `topology.kubernetes.io/zone=home`. Provision a `local-path-provisioner` scoped to the home node only (not a cluster-wide default StorageClass) as a new `infra/` component to back its state PVC.

## Consequences

Hermes Agent's state is tied to one specific physical machine — no live migration if it dies, which is an accepted trade-off for a single-instance homelab daemon with no HA requirement. In exchange: a stateful, possibly untrusted-code-executing workload stays off the nodes holding etcd for the entire cluster, and we avoid the dual-default-StorageClass conflict that enabling Hetzner CSI/Longhorn alongside a cluster-wide local-path provisioner would create.
