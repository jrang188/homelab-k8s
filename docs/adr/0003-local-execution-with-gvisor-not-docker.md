# Use the `local` execution backend with gVisor, not Docker socket/DinD

## Status

Accepted

## Context

Hermes Agent executes agent-issued shell/code commands and supports several execution backends (`local`, Docker, SSH, Daytona, Singularity, Modal). The intuitive choice for isolating that execution is Docker (a socket mount or Docker-in-Docker), but on this cluster that is a worse failure mode than no isolation at all: mounting `/var/run/docker.sock` hands the pod root-equivalent control of the host's Docker daemon (trivial full-node compromise via a new `--privileged -v /:/host` container), and DinD requires `privileged: true`, a well-documented container-breakout surface. This cluster has only 4 nodes total, 3 of which hold etcd (see [0002](0002-home-node-pinning-and-scoped-storage.md)) — a node-level compromise from either path is a whole-cluster incident, not a contained one.

## Decision

Use the `local` backend (commands run directly inside the pod, ordinary container isolation only), wrapped in a gVisor (`runsc`) `RuntimeClass` installed on the home node. This is defense-in-depth against *accidentally* executed malicious code — e.g. indirect prompt injection via fetched web content, or a compromised dependency — not a design for deliberately adversarial, red-team-grade code execution.

## Consequences

Requires installing gVisor's containerd shim and a `RuntimeClass` on the home node only (Hermes Agent never schedules elsewhere, per 0002). If a future use case needs genuinely adversarial-grade isolation, revisit with Kata Containers (needs KVM — available on the home node's hardware, not guaranteed on the Hetzner control planes) or by pushing execution off-cluster entirely onto Hermes's own Daytona/Modal backends.
