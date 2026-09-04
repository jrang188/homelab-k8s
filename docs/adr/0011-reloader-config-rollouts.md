# Auto-roll pods on ConfigMap/Secret changes via Stakater Reloader

## Status

Accepted

## Context

ConfigMaps mounted via `subPath` never hot-update inside the container — the
kubelet only refreshes full-volume binds, not subPath files, and even then the
process must reload the file itself. This bit immediately with SearXNG's
`settings.yml` ([ADR-0010](0010-searxng-plain-manifests-not-truecharts-chart.md)):
after PR #25 added the settings ConfigMap, ArgoCD synced it but the running pod
kept the old settings in memory until someone ran
`kubectl rollout restart deployment/searxng -n searxng` by hand. Every future
settings edit would repeat that manual step.

Options considered:

- **Stakater Reloader** (`infra/reloader`) — small controller (~30MB RSS) that
  watches ConfigMap/Secret events and rolling-restarts workloads annotated with
  `reloader.stakater.com/auto: "true"`.
- **Helm post-upgrade hooks / ArgoCD hooks** — no Helm releases exist for
  plain-manifest apps like searxng (ADR-0001/0010), so there's nothing to hook.
- **Manual rollout restarts** — clickops; exactly what this repo exists to
  eliminate.
- **Drop subPath, mount the ConfigMap as a directory + have the app hot-reload**
  — SearXNG reads settings.yml once at worker start; no in-process reload. And
  mounting over `/etc/searxng/` wholesale shadows files the image expects there.

## Decision

Deploy [Stakater Reloader](https://github.com/stakater/Reloader) via its
official chart using the repo's wrapper-chart pattern (`infra/reloader`, same
shape as `infra/traefik` / `infra/cert-manager`), and annotate opt-in
workloads. Only `apps/searxng` carries the annotation today; other apps adopt
it when they mount config from ConfigMaps.

## Consequences

One more controller runs cluster-wide (single Deployment, home-node-compatible
footprint) in exchange for eliminating manual restarts on every config change.
Opt-in by annotation means existing workloads are untouched until annotated —
no surprise rollouts. The controller is a new failure domain only for *rollout*
convenience: if it dies, config changes simply stop auto-applying (back to the
manual `rollout restart`), nothing else degrades.

## Considered options

- Manual `kubectl rollout restart` per config change — rejected: manual ops
  step that recurs on every edit.
- ArgoCD/Helm hooks — rejected: plain-manifest apps have no Helm release to
  hook, and App-of-App hook machinery contradicts the no-extra-machinery stance
  of [ADR-0009](0009-selfheal-over-sync-waves.md).
