# Renovate vs Dependabot for Helm chart updates

**Date:** 2026-08-21
**Status:** Proposal (pending review)
**Scope:** Automated dependency updates for the wrapper charts in this repo (`argocd/`, `infra/*`, `apps/*`)

## Problem

Every Helm-managed component in this repo is a thin wrapper chart: `Chart.yaml` pins an
upstream chart version, `Chart.lock` + vendored tarballs pin it exactly. Today those pins are
updated by hand. Consequences:

- Chart updates happen rarely and in batches, so each upgrade carries more risk than many
  small upgrades would.
- Security fixes in ingress controllers, cert-manager, ESO, etc. land on our schedule
  (i.e., never) instead of upstream's.
- Nothing tells us when a pin is stale; drift is discovered during incident debugging.

We need a bot that opens small, reviewable PRs when upstream charts release.

## TL;DR recommendation

**Use Renovate, self-hosted on GitHub Actions, free tier of compute, ~30 lines of workflow.**
Dependabot is disqualified outright — it has no Helm manager at all. The only real decision
left is hosted-app vs self-hosted Renovate, and self-hosting wins for this repo because
`Chart.lock` regeneration requires running the `helm` binary as a post-update command.

If zero-infra trumps everything: install the Mend-hosted GitHub app and accept that
`Chart.lock` may go stale between manual `helm dependency update` runs (ArgoCD still syncs
fine; the lock file just lags). This repo should not make that trade — see below.

## Why not Dependabot

Dependabot's supported ecosystems (`dependabot.yml` version-updaters) cover pip, npm,
bundler, cargo, Go modules, Docker, **GitHub Actions** — but **not Helm charts**. There is no
`package-ecosystem: "helm"` equivalent. It literally cannot see the dependencies in any
`Chart.yaml` in this repo. Decision over.

(Its one adjacent trick, `package-ecosystem: docker` against image tags inside
`values.yaml`, doesn't apply here either: our charts don't pin images directly — the upstream
charts do.)

## Why Renovate fits this repo exactly

Renovate has a first-class [`helmv3`
manager](https://docs.renovatebot.com/modules/manager/helmv3/) whose default file match is
`/(^|/)Chart\.ya?ml$/` — it discovers all 9 wrapper charts with zero per-chart wiring:

| Repo pattern | Renovate behavior |
| --- | --- |
| `dependencies:` pin in `Chart.yaml` | Bumps `version:` to latest upstream release, one PR per chart |
| `Chart.lock` | Regenerates via `helm dependency update <dir>` (external command) |
| Vendored `charts/*.tgz` | Refreshed by the same command (gitignored here, so no-op in PRs) |
| Exact pins (`cert-manager v1.21.1`) | Updates across major/minor/patch |
| Caret ranges (`traefik ^41.2.0`) | Updates within range automatically; majors get their own PR |

It also understands the `repository:` URL in each dependency, so it queries the right index
(argo-helm, jetstack, external-secrets, traefik, tailscale, victoriametrics,
kubernetes-sigs, goauthentik) without registry configuration.

### Hosted app vs self-hosted — the deciding factor

The [Mend-hosted GitHub app](https://docs.renovatebot.com/mend-hosted/overview/) is free
(unlimited private repos), zero infra, and runs every 4 hours. But its runner permits only "a
limited set of approved postUpgradeTasks commands" (undocumented set, discoverable via
`allowedCommands` in job logs). Whether `helm dependency update` is in that set is not
documented anywhere official. If it isn't, every Renovate PR updates `Chart.yaml` but leaves
`Chart.lock` stale — and a stale lock file means ArgoCD keeps deploying the *old* pinned
chart while the diff suggests an upgrade happened. That failure mode is silent and nasty.

Self-hosted Renovate runs `helm dependency update` natively (lock-file maintenance is
explicitly delegated to the package-manager binary; long-standing support, see
renovatebot/renovate#13858 resolved in 2022). On GitHub Actions this costs nothing at this
repo's scale (one repo, 9 charts, hourly cron ≈ well under the free minutes allowance).

**Decision: self-host.** We keep full control of scheduling, the helm binary version, and
the exact commands run — appropriate for a security-sensitive homelab control repo.

## Proposed implementation

Three files, all in-repo, no external service accounts:

1. **`.github/workflows/renovate.yml`** — scheduled self-hosted Renovate:
   - `cron: '0 * * * *'` (hourly; Renovate itself rate-limits and dedupes)
   - `container: ghcr.io/renovatebot/renovate:<pinned tag>` (official image ships helm)
   - `RENOVATE_TOKEN` from a fine-grained PAT (Contents+PRs RW on this repo only),
     stored as an org/repo Actions secret — **manual step for Justin**, listed below
   - `workflow_dispatch` trigger for on-demand runs while tuning config
2. **`renovate.json`** — repo config (see PR): extends `config:recommended`, scopes the
   helmv3 manager to `argocd/**`, `infra/**`, `apps/**`, groups all chart bumps into one
   weekly PR (a single reviewable cluster change suits a homelab better than 9 separate
   pings), sets `minimumReleaseAge: 3 days` so we never ride a broken upstream release,
   enables `lockFileMaintenance` (weekly re-lock even without version changes).
3. **Nothing else.** No labels, no branch protection changes required. Existing Claude
   code-review workflows will also fire on Renovate PRs — free second-opinion review.

### Operational notes

- First run creates an **onboarding PR** ("Configure Renovate") — merge or edit it to taste.
- The bot authenticates as a dedicated identity. Recommended: create a fine-grained PAT
  under Justin's account scoped to `jrang188/homelab-k8s` only (Contents: RW, Pull requests:
  RW, Workflows: RO). Do **not** reuse yohjibot3800's classic token for this.
- Rollback story is unchanged: revert the merge commit, ArgoCD self-heals back.
- If we later want per-chart PRs instead of grouped, flip one boolean (`groupName` removal);
  config lives in-repo so iteration is cheap.

## Alternatives considered and rejected

| Alternative | Why rejected |
| --- | --- |
| Dependabot | No Helm ecosystem support. Disqualified. |
| Mend-hosted Renovate app | Free & zero-infra, but undocumented whether `helm` post-update commands are allowed → risk of silently stale `Chart.lock`. Revisit if self-hosting becomes annoying. |
| ArgoCD Image Updater | Different problem: mutates image tags in-cluster or via API writes, fights GitOps review flow, and doesn't handle chart version pins in `Chart.yaml` well. |
| Flux-native automation | We're an ArgoCD shop; not switching. |
| Manual quarterly bump ritual | Status quo. Already demonstrated to not happen. |

## References

- https://docs.renovatebot.com/modules/manager/helmv3/
- https://docs.renovatebot.com/bot-comparison/
- https://docs.renovatebot.com/mend-hosted/hosted-apps-config/ (allowedCommands note)
- https://docs.renovatebot.com/configuration-options/#minimumreleaseage
- renovatebot/renovate#13858 (helm lock-file update support confirmed)
