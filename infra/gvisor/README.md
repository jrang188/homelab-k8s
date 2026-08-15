# `infra/gvisor` — home-node-scoped gVisor RuntimeClass

This directory defines a single Kubernetes resource: a `RuntimeClass` named
`gvisor`, with handler `runsc`, that any pod can request via
`spec.runtimeClassName: gvisor`.

## Scope: home node only

The `RuntimeClass` is scoped to the home node via the `scheduling` field:

- `nodeSelector: topology.kubernetes.io/zone=home` — only nodes with that
  label are eligible to run a pod requesting this RuntimeClass.
- `tolerations` — adds a toleration for `node-role.kubernetes.io/home=true:NoSchedule`,
  matching the home node's NoSchedule taint so the kubelet will consider the
  pod for scheduling there.

Both fields are required together: `nodeSelector` alone would leave a
requesting pod permanently unschedulable, since the only zone-matching node
also repels non-tolerating pods via its own `NoSchedule` taint. The
`tolerations` block is what actually admits the pod past that taint; the
`nodeSelector` is what keeps it from landing anywhere else.

This matches Hermes Agent's home-node pinning (ADR-0002). The home node is
the only one where `runsc` will actually be installed, so restricting at
admission is the right place to fail.

## Companion `homelab-nix` change: landed

This Kubernetes-side `RuntimeClass` is only half of ADR-0003's design — the
other half is installing the `runsc` binary and its containerd shim on the
home node, and registering `runsc` as a containerd runtime handler there.
That install lives in the sibling
[`homelab-nix`](https://github.com/jrang188/homelab-nix) repo and landed
2026-08-15 (`modules/gvisor.nix`, enabled on `hosts/k3s-agent-hml`).

With both halves in place, once this `RuntimeClass` is merged and synced by
ArgoCD, a pod requesting `runtimeClassName: gvisor` should schedule onto the
home node and actually start there — not just be admitted.

See [ADR-0003](../../../docs/adr/0003-local-execution-with-gvisor-not-docker.md)
for the broader rationale (defense-in-depth against accidentally-executed
code, not a design for deliberately adversarial execution).