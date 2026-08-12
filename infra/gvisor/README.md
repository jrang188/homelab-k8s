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

This matches Hermes Agent's home-node pinning (ADR-0002). The home node is
the only one where `runsc` will actually be installed, so restricting at
admission is the right place to fail.

## Non-functional until `homelab-nix` lands

This Kubernetes-side change is **not enough on its own**. The `runsc` binary
and its containerd shim must also be installed on the home node, and the
home node's containerd must register `runsc` as a runtime handler under the
name `runsc`. That install lives in the sibling
[`homelab-nix`](https://github.com/jrang188/homelab-nix) repo (NixOS-side
config), and is tracked as a separate ticket there.

Until that companion change lands:

- This `RuntimeClass` will exist and be accepted by the API server.
- A pod requesting `runtimeClassName: gvisor` will be admitted, scheduled,
  and started on the home node.
- The kubelet on the home node will fail to actually launch the container,
  because no runtime handler named `runsc` is registered.

See [ADR-0003](../../../docs/adr/0003-local-execution-with-gvisor-not-docker.md)
for the broader rationale (defense-in-depth against accidentally-executed
code, not a design for deliberately adversarial execution).