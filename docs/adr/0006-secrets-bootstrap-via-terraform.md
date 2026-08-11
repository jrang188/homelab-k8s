# Bootstrap secret delivered via Terraform, not GitOps; sealed-secrets removed

## Status

Accepted

## Context

External Secrets Operator (ESO) with the native 1Password SDK provider is replacing hand-managed secrets for ordinary app secrets. But the 1Password service-account token ESO needs to authenticate has to land in-cluster before ESO can fetch anything — a bootstrap secret can't itself come from the system it bootstraps.

## Decision

Deliver that one bootstrap secret via a `kubernetes_secret` Terraform resource added to `opentofu-infra` (which already has cluster access and applies over Tailscale), rather than through GitOps — mirroring the user's existing operational pattern for this exact problem. Delete `infra/sealed-secrets`: once ESO covers every other secret, it has no remaining use case in this repo.

## Consequences

This one secret's lifecycle (initial creation, rotation) lives outside ArgoCD's reconciliation loop, in Terraform state — a deliberate exception, not an oversight. A future reader should not try to "fix" it by routing it through GitOps instead.

## Considered options

- Keep `infra/sealed-secrets` solely for this one bootstrap secret — rejected in favor of matching the user's existing Terraform-based pattern rather than keeping a whole component around for a single narrow use.
- Inject the token by hand via `kubectl` — rejected: undocumented and non-reproducible on cluster rebuild.
