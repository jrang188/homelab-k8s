# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A GitOps repo for a home Kubernetes cluster, reconciled by ArgoCD. No Makefile, no build/deploy pipeline. CI runs `scripts/render.sh` on every PR — see below — which renders/lints every `infra/*` and `apps/*` module; there is no further pipeline beyond that, and ArgoCD's own sync is the only "deploy."

## Repo layout and sync flow

Bootstrap (applied manually, once, with `kubectl apply -f <file>`):
- `argocd-management/argocd.yaml` — the ArgoCD `Application` that installs ArgoCD itself from `argocd/` (a wrapper chart around the upstream `argo-cd` chart).
- `argocd-management/applications.yaml` — the ArgoCD `Application` (`argocd-apps`) that points at `argocd-resources/`.

Everything else is discovered automatically, no manual `kubectl apply` needed:
- `argocd-resources/applicationset-infra.yaml` and `applicationset-apps.yaml` are ArgoCD `ApplicationSet`s. Each uses a git directory generator over `infra/*` and `apps/*` respectively, creating one ArgoCD `Application` per subdirectory. The Application name and destination namespace are both derived from the directory's basename (`{{path.basename}}`), so a new directory under `infra/` or `apps/` is picked up with no other wiring.
- `infra/` — cluster infrastructure components (currently `traefik`).
- `apps/` — workloads deployed to the cluster (currently empty; `apps/hermes-agent` is planned — see `CONTEXT.md`).

ApplicationSet sync policy is `applicationsSync: create-only` with `preserveResourcesOnDeletion: true` — ArgoCD creates new Applications for new directories but won't delete/prune an Application (or its resources) just because the directory disappeared; deletions must be handled by hand. Individual Applications have `syncPolicy.automated.selfHeal: true`.

## Helm chart pattern ("wrapper charts")

Most `infra/*` and some `apps/*` directories are thin wrapper charts: a local `Chart.yaml` with a single `dependencies` entry pinning an upstream chart + repo, vendored into `charts/*.tgz`, with a local `values.yaml` overriding upstream defaults. e.g. `infra/traefik/Chart.yaml` depends on `traefik/traefik`, `argocd/Chart.yaml` depends on `argo-cd/argo-cd`.

- `charts/*.tgz` and `Chart.lock` vendor the pinned dependency — regenerate after editing `Chart.yaml`'s dependency version with `helm dependency update <dir>`.
- `*.tgz` files, `.idea`, `.vscode`, and `.DS_Store` are gitignored (see `.gitignore`), so vendored chart tarballs are a local/regenerable artifact, not committed — don't assume a directory lacking `charts/*.tgz` on disk is broken; run `helm dependency update` before templating it.
- Chart-local Kubernetes resources live under `<dir>/templates/`.
- Not every directory is a Helm chart: plain Kubernetes manifests are applied directly by ArgoCD (Deployment/Service/Ingress, no `Chart.yaml` — see `docs/adr/0001-plain-manifests-not-operator-or-chart.md`).

To render/validate every `infra/*` and `apps/*` module before committing, run:
```
./scripts/render.sh
```
This is the same check CI runs on every PR (`.github/workflows/render.yml`) — see [ADR-0010](docs/adr/0010-render-script-in-ci.md). It walks each directory, `Chart.yaml` present or not, and reports every failure in one pass rather than stopping at the first.

To debug a single directory by hand:
```
helm dependency update <dir>     # e.g. infra/traefik
helm template <dir> -f <dir>/values.yaml
helm lint <dir>
```

## Networking conventions

- Traefik (`infra/traefik`) is the ingress controller; app-level routing is expressed as plain `Ingress` resources. LoadBalancer Services on the public-facing control planes are satisfied by Klipper (k3s's built-in ServiceLB), not MetalLB.
- ArgoCD itself is deployed via the `argocd` wrapper chart at repo root, not under `infra/` — it's bootstrapped before the ApplicationSets exist to discover anything.

## Repo identity

The ApplicationSets and root Applications hardcode `repoURL: https://github.com/jrang188/homelab-k8s`, `targetRevision: HEAD`. Any restructuring of top-level directories (`apps/`, `infra/`, `argocd-resources/`, `argocd-management/`, `argocd/`) needs a matching update to these hardcoded paths, since ArgoCD won't infer them.

## External infrastructure repositories

This GitOps repository depends on two external infrastructure repositories:

- **Hetzner Control Plane**: https://github.com/jrang188/opentofu-infra — OpenTofu code for provisioning the k3s control plane on Hetzner Cloud
- **Home Agent Node**: https://github.com/jrang188/homelab-nix — NixOS/nix-darwin configuration for the k3s home agent node

## Agent skills

### Issue tracker

GitHub Issues (`jrang188/homelab-k8s`), via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five canonical roles, label strings equal to their names (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
