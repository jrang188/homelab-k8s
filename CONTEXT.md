# homelab-k8s

A GitOps-reconciled home Kubernetes cluster. This file is a glossary of terms specific to this cluster's shape and workloads — not a spec, not an implementation log.

## Language

**Control plane**:
One of 3 Hetzner CX23 cloud VPS instances (`../../devops/opentofu-infra`, `kube-hetzner` module), forming HA etcd. Despite the name, these **are** schedulable — `allow_scheduling_on_control_plane = true` — and run ordinary workloads (e.g. all 3 Traefik ingress replicas) alongside etcd/API-server duties. Subject to unattended OS/k3s upgrades with `kured`-driven reboots. No PVC storage class of any kind is provisioned on this side (Hetzner CSI and Longhorn are both explicitly disabled).
_Avoid_: "the cluster" (the home node is also part of it)

**Home node**:
`k3s-agent-hml` — the physical mini PC (4-core Haswell i5-4570T, 16GB DDR3 RAM, ~100GB+ SSD), joined as a k3s agent over Tailscale (`../../devops/homelab-nix`). Tainted `node-role.kubernetes.io/home=true:NoSchedule` — only workloads that explicitly tolerate it get scheduled here. No unattended-upgrade churn (its own drain-hook mechanism, not `kured`). The only node with real dedicated local disk.
_Avoid_: "worker node" (control planes are also workers, see above)

**Storage class**:
Does not exist yet, on either the control-plane or home side, as of this writing — Hetzner CSI, Longhorn, and k3s's built-in local-path provisioner are all disabled. Any `apps/`/`infra/` workload that needs a PVC needs this provisioned first (a `local-path-provisioner` scoped to the home node is the natural fit, given it's the only node with disk meant for this).

**Hermes Agent**:
An always-on daemon (single planned instance, not yet built — planning stage) running the NousResearch `hermes-agent` LLM coding-agent CLI. Deployed as a plain Kubernetes Deployment under `apps/hermes-agent` (mirroring the `apps/whoami` plain-manifest pattern, not a Helm chart — upstream has no official k8s deployment target to wrap), pinned to the **home node** only via taint toleration + `topology.kubernetes.io/zone=home` nodeSelector, using the **local-path-provisioner** (home-node-scoped, new `infra/` addition) for its state PVC, reachable remotely by Hermes Desktop via a dedicated **Tailscale operator**-exposed `Service` (new `infra/tailscale-operator`), rather than node-level Tailscale or public Traefik ingress. No off-node backup for now (deferred).
_Avoid_: hermes-operator, hermes-agent-helm-chart (both evaluated and rejected — the operator's community image pin is stale/broken on containerd, the chart is abandonware)

**Execution backend**:
The sandbox Hermes Agent uses to run agent-issued shell/code commands. Resolved as `local` (runs directly in the pod, no docker socket/DinD — those grant node-level compromise on a cluster where 3 of 4 nodes hold etcd) wrapped in a **gVisor** `RuntimeClass` installed on the home node only, as defense-in-depth against accidentally-executed malicious code (e.g. prompt-injected or compromised-dependency scenarios), not deliberate red-teaming.
