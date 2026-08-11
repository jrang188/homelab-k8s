# Deploy Hermes Agent as plain manifests, not a Helm chart or operator

## Status

Accepted

## Context

Evaluated two community projects for deploying NousResearch's `hermes-agent` to Kubernetes: `paperclipinc/hermes-operator` (a real k8s operator with CRDs, actively maintained, but single-maintainer, and its own documented agent-image pin (`v0.16.0`) predates the upstream fix for containerd/k8s container detection — its own quickstart would hit a known double-start crash-loop bug) and `ultraworkers/hermes-agent-helm-chart` (abandonware: zero commits in ~4 months, both post-launch PRs closed unmerged, an unresolved deployment-breaking default-config bug). Neither wraps anything upstream officially supports — NousResearch's own docs list `local`, Docker, SSH, Daytona, Singularity, and Modal as supported backends; no Kubernetes.

## Decision

Hand-write plain `Deployment`/`PVC`/`Service` manifests under `apps/hermes-agent` (no `Chart.yaml`), tracking the upstream Docker image directly at a current, explicitly-chosen tag rather than trusting either project's example.

## Consequences

We own the upgrade path ourselves — no free CRD-based lifecycle management, no automatic backups, no OCI auto-update polling — but we avoid inheriting a third party's maintenance and bus-factor risk for software that has no official Kubernetes target to begin with.

## Considered options

- `hermes-operator` — rejected: stale/broken default image pin, bus factor of 1, real conceptual overhead (CRDs, SSA, admission webhooks) this single-instance use case doesn't need.
- `hermes-agent-helm-chart` — rejected: abandonware by every signal (commit gap, unanswered issues, unmerged fixes).
