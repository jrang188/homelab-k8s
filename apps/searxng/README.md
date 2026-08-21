# `apps/searxng` — SearXNG (plain manifests)

Plain Kubernetes manifests (`Deployment`, `Service`, `ExternalSecret`) for
[SearXNG](https://docs.searxng.org/), a self-hosted metasearch engine.
Deployed as plain manifests rather than the
[TrueCharts chart](https://truecharts.org/charts/stable/searxng/) per
[ADR-0010](../../docs/adr/0010-searxng-plain-manifests-not-truecharts-chart.md).

## Why plain manifests

SearXNG has no official Helm chart, so there's nothing to wrap in the repo's
usual "wrapper chart" pattern — and the only third-party chart (TrueCharts)
drags in its `common` library layer, hard-requires Kubernetes ≥1.33, and runs
the workload as root. See ADR-0010 for the full comparison.

## Shape

- **Stateless** (`deployment.yaml`): a single non-root container configured
  entirely via env vars — the image's default `settings.yml` already sets
  `use_default_settings: true`, so `SEARXNG_*` env vars are all that's needed.
  No PVC, no home-node pinning, no ConfigMap.
- **Bot-protection limiter off** (`SEARXNG_LIMITER=false`): a single-user
  instance reachable only on the tailnet already has access control at the
  network layer, so SearXNG's Redis/Valkey rate limiter isn't needed. If it
  ever goes multi-user or public, add a Valkey deployment and set
  `SEARXNG_VALKEY_URL`.
- **Exposure** (`service.yaml`): tailnet-only via the Tailscale Kubernetes
  operator — `type: LoadBalancer` + `loadBalancerClass: tailscale` +
  `tailscale.com/hostname: searxng`, exactly like
  [`apps/hermes-agent`](../hermes-agent/service.yaml). Reachable at
  `https://searxng.tail8255cc.ts.net/` over the tailnet (MagicDNS + a
  Tailscale-issued TLS cert), never via the public Traefik/Cloudflare path
  ([ADR-0005](../../docs/adr/0005-public-exposure-via-cloudflare-and-floating-ip.md)).

## Required out-of-band setup

1Password secret (`external-secret.yaml`): create an item named
`searxng-secret` (vault `Development`) with a field `secret` set to
`openssl rand -base64 32`. The Deployment fails closed without it — the same
pattern as `cloudflare-api-token` / `tailscale-operator-oauth`.

## Upgrading

Bump the pinned image tag in `deployment.yaml` (`searxng/searxng:<tag>`).
Tags are `YYYY.M.D-<commit>` on
[Docker Hub](https://hub.docker.com/r/searxng/searxng/tags); pin an explicit
tag rather than `latest` (see ADR-0001).
