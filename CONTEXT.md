# homelab-k8s

A GitOps-reconciled home Kubernetes cluster. This file is a glossary of terms specific to this cluster's shape and workloads — not a spec, not an implementation log.

## Language

**Control plane**:
One of 3 Hetzner CX23 cloud VPS instances (`../../devops/opentofu-infra`, `kube-hetzner` module), forming HA etcd. Despite the name, these **are** schedulable — `allow_scheduling_on_control_plane = true` — and run ordinary workloads (e.g. all 3 Traefik ingress replicas) alongside etcd/API-server duties. Subject to unattended OS/k3s upgrades with `kured`-driven reboots. No PVC storage class of any kind is provisioned on this side (Hetzner CSI and Longhorn are both explicitly disabled).
_Avoid_: "the cluster" (the home node is also part of it)

**Home node**:
`k3s-agent-hml` — the physical mini PC (4-core Haswell i5-4570T, 16GB DDR3 RAM, ~500GB SSD), joined as a k3s agent over Tailscale (`../../devops/homelab-nix`). Tainted `node-role.kubernetes.io/home=true:NoSchedule` — only workloads that explicitly tolerate it get scheduled here. No unattended-upgrade churn (its own drain-hook mechanism, not `kured`). The only node with real dedicated local disk.
_Avoid_: "worker node" (control planes are also workers, see above)

**Storage class**:
A `local-path-provisioner` scoped to the home node only (the only node with real dedicated disk — Hetzner CSI and Longhorn stay disabled on the control planes). General-purpose, not tied to a single workload: Hermes Agent's state PVC, the monitoring TSDB, and log storage all share it (see [ADR-0007](docs/adr/0007-broaden-home-node-storage-to-general-purpose.md)). Not yet built as of this writing.

**Ingress path**:
The L4/L7 chain that gets a request from the public internet to a Service: Klipper (k3s's built-in `ServiceLB`, turned on via kube-hetzner's `enable_klipper_metal_lb` flag — despite the name, this is *not* real MetalLB) binds `:80`/`:443` on each control plane's public IP and forwards to Traefik, which this repo owns via `infra/traefik` (not kube-hetzner's built-in install). A Floating IP gives this path one stable public address regardless of which node currently serves it. See [ADR-0004](docs/adr/0004-own-traefik-remove-metallb.md).
_Avoid_: "MetalLB" (a real MetalLB install existed briefly as `infra/metallb`, targeting a home-LAN pool that never matched any node's actual network — removed, see ADR-0004)

**Secrets bootstrap secret**:
The one secret — a 1Password service-account token — that can't come from ESO itself, since ESO needs it to reach 1Password in the first place. Delivered as a `kubernetes_secret` Terraform resource in `../../devops/opentofu-infra`, outside ArgoCD's reconciliation loop, rather than through GitOps. Every other secret is managed by ESO's 1Password SDK provider afterward. See [ADR-0006](docs/adr/0006-secrets-bootstrap-via-terraform.md).
_Avoid_: sealed-secrets (removed — this was its only remaining use case in this repo)

**Bootstrap secret contract** (cross-repo interface):
- Name: `onepassword-token`
- Namespace: `eso`
- Key: `token`
- Created by: `kubernetes_secret` Terraform resource in `opentofu-infra`
- Consumed by: `ClusterSecretStore` `onepassword` (via `serviceAccountSecretRef`)
- Any future consumer (cert-manager, external-dns) that needs ESO-fetched secrets must reference `ClusterSecretStore/onepassword` — it is cluster-scoped and namespace-agnostic.

**Hermes Agent**:
An always-on daemon (single planned instance, not yet built — planning stage) running the NousResearch `hermes-agent` LLM coding-agent CLI. Deployed as a plain Kubernetes Deployment under `apps/hermes-agent` (plain manifests, not a Helm chart — see [ADR-0001](docs/adr/0001-plain-manifests-not-operator-or-chart.md) — upstream has no official k8s deployment target to wrap), pinned to the **home node** only via taint toleration + `topology.kubernetes.io/zone=home` nodeSelector, using the **local-path-provisioner** (home-node-scoped, general-purpose) for its state PVC, reachable remotely by Hermes Desktop via a dedicated **Tailscale operator**-exposed `Service` (new `infra/tailscale-operator`), rather than node-level Tailscale or public Traefik ingress. No off-node backup for now (deferred).
_Avoid_: hermes-operator, hermes-agent-helm-chart (both evaluated and rejected — the operator's community image pin is stale/broken on containerd, the chart is abandonware)

**SearXNG**:
A self-hosted metasearch engine — the cluster's first public-facing web app — deployed as plain manifests under `apps/searxng` (not a Helm chart, see [ADR-0010](docs/adr/0010-searxng-plain-manifests-not-truecharts-chart.md)). Stateless: configured entirely via env vars (`SEARXNG_SECRET` from ESO/1Password, `SEARXNG_BASE_URL`, bot-protection limiter off), so no PVC and no home-node pinning — it schedules on any schedulable node. Exposed via a Traefik `Ingress` (this repo's own `infra/traefik`), TLS from the `cloudflare` `ClusterIssuer`, DNS from external-dns, all fronted by Cloudflare per [ADR-0005](docs/adr/0005-public-exposure-via-cloudflare-and-floating-ip.md).
_Avoid_: the TrueCharts `searxng` chart (rejected — drags in the TrueCharts `common` layer, hard-requires k8s ≥1.33, runs as root; see ADR-0010)

**Execution backend**:
The sandbox Hermes Agent uses to run agent-issued shell/code commands. Resolved as `local` (runs directly in the pod, no docker socket/DinD — those grant node-level compromise on a cluster where 3 of 4 nodes hold etcd) wrapped in a **gVisor** `RuntimeClass` installed on the home node only, as defense-in-depth against accidentally-executed malicious code (e.g. prompt-injected or compromised-dependency scenarios), not deliberate red-teaming.
