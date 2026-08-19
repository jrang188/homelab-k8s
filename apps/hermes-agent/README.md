# `apps/hermes-agent` — Hermes Agent (plain manifests)

Plain Kubernetes manifests (`Deployment`, `PersistentVolumeClaim`, `Service`,
plus an `ExternalSecret` for its dashboard credentials) for NousResearch's
[`hermes-agent`](https://github.com/NousResearch/hermes-agent), per
[ADR-0001](../../docs/adr/0001-plain-manifests-not-operator-or-chart.md) —
no official Kubernetes packaging exists upstream to wrap.

- **Home-node pinning** (`deployment.yaml`): toleration + `topology.kubernetes.io/zone=home`
  nodeSelector, per [ADR-0002](../../docs/adr/0002-home-node-pinning-and-scoped-storage.md).
- **Sandboxing** (`deployment.yaml`): `runtimeClassName: gvisor`, referencing
  `infra/gvisor`'s `RuntimeClass`, per
  [ADR-0003](../../docs/adr/0003-local-execution-with-gvisor-not-docker.md).
- **State** (`pvc.yaml`): `local-path` StorageClass (`infra/local-path-provisioner`).
- **Exposure** (`service.yaml`): `type: LoadBalancer` + `loadBalancerClass: tailscale`,
  handled by `infra/tailscale-operator` — reachable only over the tailnet,
  never via public Traefik Ingress.

## Runtime image and command

Runs `gateway run` — the image's supervised main process — with
`HERMES_DASHBOARD=1` set so the dashboard comes up as an s6-supervised
sibling service in the *same* container. This is not optional: the docs
note the dashboard's liveness detection needs a shared PID namespace with
the gateway, so it can't be split into a second Deployment/pod. Hermes
Desktop's remote-connection mode (Settings → Gateways →
`http://hermes-agent:9119` once resolved over Tailscale MagicDNS) talks to
this dashboard port, not the gateway's own OpenAI-compatible API server
(port 8642, not exposed here — unused by this deployment's design). See
upstream's
[docker.md](https://hermes-agent.nousresearch.com/docs/user-guide/docker).

A `/dev/shm` `emptyDir` (backed by memory, 1Gi) is mounted alongside the
data PVC: Playwright/Chromium (bundled in the image, used for browser
tools) needs real shared memory beyond Kubernetes' 64Mi default, matching
upstream's documented `--shm-size=1g` Docker flag.

## Required out-of-band setup

The dashboard's auth gate engages automatically on any non-loopback bind
(the image default is `0.0.0.0`) and fails closed at startup without a
registered auth provider. `external-secret.yaml` expects a 1Password item
named `hermes-agent-dashboard-auth` (vault `Development`, matching
`infra/eso`'s `ClusterSecretStore`) with three fields — `username`,
`password`, `secret` (the last a random key, e.g. `openssl rand -base64 32`,
for session persistence across restarts) — created before this Application
will go healthy. This mirrors how `cloudflare-api-token` and
`tailscale-operator-oauth` are provisioned in 1Password out-of-band for
`infra/cert-manager`/`infra/external-dns`/`infra/tailscale-operator`.

## Tooling inside the image

Out of scope for this issue: the upstream image already bundles what a
general-purpose coding agent needs — Python 3.13, Node.js 26, Playwright +
Chromium, ripgrep, ffmpeg, git, and `openssh-client` (for the SSH terminal
backend). It deliberately excludes `docker-cli`'s use case (driving the
host's Docker daemon via a mounted `/var/run/docker.sock`) — ADR-0003
rejected that exact path as a full-node-compromise risk, independent of
gVisor sandboxing. Anything beyond the bundled set is meant to be installed
on demand by the agent itself (`npx`/`uvx`, or `apt-get` + remember) per
upstream's own guidance, not pre-provisioned here — see docker.md's
"Installing more tools in the container".
