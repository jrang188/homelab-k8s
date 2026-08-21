# Deploy SearXNG as plain manifests, not the TrueCharts chart

## Status

Accepted

## Context

Adding [SearXNG](https://docs.searxng.org/) (a self-hosted metasearch engine)
for the cluster. Two candidates: the
[TrueCharts `searxng` chart](https://truecharts.org/charts/stable/searxng/) —
the only ready-made Helm chart for it — or hand-written plain manifests.

SearXNG has **no official Helm chart**: `searxng/searxng` ships only Docker +
Compose + install scripts, and `searxng/searxng-docker` is superseded in favor
of the docs' Compose-instancing. So this repo's usual "wrapper chart" pattern
(a thin `Chart.yaml` pinning an *official* upstream chart, as used for
`infra/traefik`, `infra/cert-manager`, `infra/external-dns`) has nothing
official to wrap — leaving the TrueCharts third-party chart as the only
"chart" option.

Facts verified directly against the TrueCharts chart (`Chart.yaml` /
`values.yaml`):

- It depends on the `common` library chart v29.10.4
  (`oci://oci.trueforge.org/truecharts`) — the TrueCharts abstraction layer
  that presumes their whole operator stack and conventions (their ingress,
  storage classes, cert issuance, CNPG database operator). This duplicates
  what the repo already owns (`infra/traefik` per ADR-0004, `infra/cert-manager`,
  `infra/eso`, `infra/local-path-provisioner`).
- It hard-requires `kubeVersion: '>=1.33.0-0'` — a stricter Kubernetes floor
  than this cluster's k3s control planes / home node are known to track, and
  a real install blocker risk.
- It runs the container as `runAsUser: 0` (root) with `SETUID`/`SETGID`
  capabilities, versus the official image's non-root `searxng` user (uid 977)
  — a security downgrade antithetical to ADR-0003's defense-in-depth stance.
- It pins `appVersion: latest` (a digest-pinned `latest` tag) — a moving
  target, where ADR-0001 deliberately chose a current, explicitly-chosen tag.

## Decision

Hand-write plain manifests under `apps/searxng` (no `Chart.yaml`), tracking
`searxng/searxng:<explicit tag>` directly — the same precedent ADR-0001 set
for `apps/hermes-agent`.

SearXNG is effectively stateless for a single-user instance, so it's a clean
plain-manifest fit:

- **Config via env vars only** — the official image's `settings.yml` already
  sets `use_default_settings: true` and is overridden by `SEARXNG_SECRET`,
  `SEARXNG_BASE_URL`, `SEARXNG_LIMITER`, and `SEARXNG_BIND_ADDRESS` (verified in
  `searx/settings_defaults.py`). No `settings.yml` ConfigMap needed; the only
  secret (`SEARXNG_SECRET`) comes from 1Password via ESO, per the repo's
  secrets bootstrap contract.
- **No PVC** — the image-proxy cache (`/var/cache/searxng`) is ephemeral and
  regenerable, left in the container layer. It's still pinned to the home
  node (ADR-0002's scheduling pattern) for RAM/CPU headroom, even though
  there's no storage binding it there.
- **Bot-protection limiter off** (`SEARXNG_LIMITER=false`) — a single-user
  instance reachable only on the tailnet already has its access control at
  the network layer, so SearXNG's Redis/Valkey rate limiter isn't needed.
  Valkey + `SEARXNG_VALKEY_URL` can be added later if it ever becomes
  multi-user or public.
- **Exposure** — tailnet-only via the Tailscale Kubernetes operator
  (`infra/tailscale-operator`): a `Service` with `type: LoadBalancer` +
  `loadBalancerClass: tailscale` + `tailscale.com/hostname`, the same pattern
  as `apps/hermes-agent`. Not the public Traefik/Cloudflare path (ADR-0005) —
  a single-user search instance shouldn't be reachable from the public
  internet.

## Consequences

We own the config and the upgrade path (bump the pinned image tag
deliberately), with no third-party chart/operator layer to keep in sync. One
out-of-band input is required before this Application goes healthy — a
1Password item for `SEARXNG_SECRET` (documented in the app README).

## Considered options

- **TrueCharts `searxng` chart** — rejected: drags in the TrueCharts `common`
  layer and operator conventions this repo already owns; hard k8s ≥1.33 floor;
  runs the workload as root; pins a `latest` moving target.
- **Wrapper chart around an official SearXNG chart** — not possible: no
  official Helm chart exists.
