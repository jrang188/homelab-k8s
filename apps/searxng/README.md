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

- **Stateless** (`deployment.yaml`): a single non-root container, configured
  via env vars plus a `settings.yml` override (`settings-configmap.yaml`) for
  the handful of settings with no env-var equivalent (engine list, JSON
  format, safesearch, metrics). No PVC — pinned to the home node
  ([ADR-0002](../../docs/adr/0002-home-node-pinning-and-scoped-storage.md)
  pattern) for its RAM/CPU headroom.
- **Metrics** (`vmservicescrape.yaml`): SearXNG's Prometheus/OpenMetrics
  endpoint (`general.open_metrics` in `settings-configmap.yaml`) scraped into
  the cluster's existing VictoriaMetrics stack. The Basic Auth password comes
  from ESO/1Password like `SEARXNG_SECRET`, but `open_metrics` has no
  env-var override — so a `render-settings` initContainer
  (`deployment.yaml`) substitutes it into the ConfigMap-mounted
  `settings.yml` template at pod start, writing the result to an `emptyDir`
  the main container mounts instead. The ConfigMap itself never holds the
  real password.
- **No instance-level rate limiter**: tried `SEARXNG_LIMITER=true` + an
  in-namespace Valkey (#53) to stop in-cluster automation bursts from
  tripping upstream engines' anti-bot, but its botdetection unconditionally
  429s any non-browser User-Agent — including Hermes, the only automated
  caller this instance has, regardless of request rate (`ip_limit`'s
  format=json cap of 4 req/IP/hour is also hardcoded, not configurable). The
  one client the limiter would ever need to throttle has to be exempted for
  Hermes to work at all, leaving it protecting against traffic that doesn't
  exist here. Removed; see `deployment.yaml`'s header comment. Tailnet-only
  exposure remains the actual access control; bursts are mitigated by engine
  breadth (below) and by pacing on the caller side instead.
- **Exposure** (`service.yaml`): tailnet-only via the Tailscale Kubernetes
  operator — `type: LoadBalancer` + `loadBalancerClass: tailscale` +
  `tailscale.com/hostname: searxng`, exactly like
  [`apps/hermes-agent`](../hermes-agent/service.yaml). Reachable at
  `https://searxng.tail8255cc.ts.net/` over the tailnet (MagicDNS + a
  Tailscale-issued TLS cert), never via the public Traefik/Cloudflare path
  ([ADR-0005](../../docs/adr/0005-public-exposure-via-cloudflare-and-floating-ip.md)).

## Required out-of-band setup

1Password secret (`external-secret.yaml`): create an item named
`searxng-secret` (vault `Development`) with two fields:
- `secret` — `openssl rand -base64 32`, consumed as `SEARXNG_SECRET`.
- `open-metrics-password` — `openssl rand -hex 24`, consumed as
  `OPEN_METRICS_PASSWORD` (the `/metrics` Basic Auth password; the username
  half is unchecked by SearXNG, so one field covers both).

The Deployment fails closed without both — same pattern as
`cloudflare-api-token` / `tailscale-operator-oauth`.

## Checking engine health

No dashboard is provisioned for this (a single-user instance doesn't warrant
one) — check ad hoc via VictoriaLogs, once metrics are flowing:

```logsql
{kubernetes.pod_namespace="searxng"} "SearxEngine"
```

(matches the `SearxEngineCaptchaException` / `SearxEngineTooManyRequestsException` /
`SearxEngineAccessDeniedException` family — what actually shows up in pod logs
when an engine gets blocked; `unresponsive_engines` itself is a JSON response
field, not something logged). Or hit `/stats/errors` on the instance directly
(tailnet: `https://searxng.tail8255cc.ts.net/stats/errors`) for the current
live view of which engines are suspended and why.

## Upgrading

Bump the pinned image tag in `deployment.yaml` (`searxng/searxng:<tag>`).
Tags are `YYYY.M.D-<commit>` on
[Docker Hub](https://hub.docker.com/r/searxng/searxng/tags); pin an explicit
tag rather than `latest` (see ADR-0001).
