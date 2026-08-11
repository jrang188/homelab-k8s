# Own Traefik in this repo; rely on Klipper for L4, remove MetalLB

## Status

Accepted

## Context

kube-hetzner already runs Klipper (`enable_klipper_metal_lb = true` — a misleadingly-named flag; this is k3s's built-in `ServiceLB`/Klipper, not real MetalLB) binding `:80`/`:443` on each of the 3 Hetzner control planes' public IPs, forwarding to a Traefik that kube-hetzner itself installs via `ingress_controller = "traefik"` (a k3s `HelmChartConfig`, provisioned in `opentofu-infra`, outside this repo's GitOps loop). This repo separately carried a real MetalLB install (`infra/metallb`) whose `L2Advertisement` pool (`192.168.1.192/26`) never matched any node's actual network — the home node's k3s node-ip is its Tailscale IP (`homelab-nix/modules/k3s-agent.nix` sets `flannel-iface: tailscale0`), and the 3 Hetzner control planes have no interface on that subnet at all. It was a leftover from an earlier, fully home-hosted topology, with no node selector scoping its speaker DaemonSet to a node where it would actually work.

## Decision

Delete `infra/metallb` outright — Klipper already satisfies every `LoadBalancer` Service on the public-facing control planes, and no workload today needs a real L2-adjacent LAN IP from the home node. Move Traefik ownership into this repo: `infra/traefik` becomes the sole Traefik install, with kube-hetzner's built-in one disabled via a companion `opentofu-infra` change (applied and sequenced by the user, out of scope for this repo).

## Consequences

Ingress config briefly spans two repos during the cutover — kube-hetzner's Traefik must be disabled in careful sequence with `infra/traefik` coming up, to avoid an ingress gap.

## Considered options

- Keep MetalLB, scoped to the home node only, for future LAN-only services — rejected for now: nothing currently needs a home-LAN-visible LoadBalancer IP.
- Leave Traefik owned by kube-hetzner — rejected: upcoming work (cert-manager, ESO-backed middleware) wants Traefik CRDs/config this repo can't currently reach.
