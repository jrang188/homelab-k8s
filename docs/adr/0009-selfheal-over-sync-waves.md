# Rely on ArgoCD selfHeal/retries instead of explicit sync-wave ordering

## Status

Accepted

## Context

The new infra components introduce real startup dependencies — ESO before secret-consuming apps sync cleanly, cert-manager before TLS Ingresses resolve, the home-node StorageClass before PVC-consuming apps schedule. The existing `applicationset-infra`/`applicationset-apps` ApplicationSets impose no ordering between the Applications they generate.

## Decision

Do not add explicit `sync-wave` annotations. Rely on `syncPolicy.automated.selfHeal` and ArgoCD's own retry/reconciliation loop to converge through first-bootstrap dependency failures.

## Consequences

Expect transient "unhealthy"/"progressing" states across dependent Applications on first bootstrap or a full redeploy, self-resolving within a few sync cycles rather than instantly. This is a deliberate choice — matching the repo's stated no-extra-machinery approach (no CI, no Makefile) — not a gap to "fix" by adding sync-waves.

## Considered options

- Explicit `sync-wave` annotations per component — rejected as ongoing maintenance overhead disproportionate to a few minutes of bootstrap convergence lag.
