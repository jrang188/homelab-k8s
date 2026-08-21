# Run scripts/render.sh locally and in CI

## Status

Accepted

## Context

Verifying a change meant running `helm dependency update`/`template`/`lint` by hand, per directory, with no single command covering every `infra/*` and `apps/*` module — see the architecture review that identified this as the repo's missing test surface. Several recent commits (e.g. `73d251a`, `1357cd5`, `c968126`) were fixes to problems that only surfaced after ArgoCD synced a broken render.

## Decision

Add `scripts/render.sh`, which walks every `infra/*` and `apps/*` directory the same way the ApplicationSets discover them, renders/lints each one, and reports every failure in one pass. Run it both locally (by hand, before committing) and in CI (`.github/workflows/render.yml`, on every PR).

## Consequences

This is the repo's first CI job. The line in `AGENTS.md` stating there is no build/lint/test pipeline no longer holds as stated; it's been corrected to describe `scripts/render.sh` as that pipeline. `render.sh` only validates shape (helm render/lint, YAML syntax) — it never touches the cluster and doesn't gate or reorder ArgoCD's own sync, so [ADR-0009](0009-selfheal-over-sync-waves.md)'s rejection of sync-wave ordering machinery still stands.
