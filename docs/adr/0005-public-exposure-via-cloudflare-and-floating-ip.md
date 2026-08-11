# Public exposure via Cloudflare DNS/TLS, fronted by a Hetzner Floating IP

## Status

Accepted

## Context

Prior work (Hermes Agent, see ADR-0001–0003) deliberately kept everything internal/Tailscale-only. This reconfiguration brings at least one public-facing component into scope, which needs real DNS and TLS automation. Klipper binds ingress to each control plane's own public IP with no stable address — `opentofu-infra`'s own README already flags this and warns against pointing a real domain at it before a stable address exists.

## Decision

`infra/external-dns` and `infra/cert-manager` both target Cloudflare (the existing DNS provider) using DNS-01 challenges. A Hetzner Floating IP is provisioned (companion `opentofu-infra` change, applied by the user) as the one stable address external-dns points DNS records at, decoupling public DNS from individual node identity.

## Consequences

Small recurring Hetzner cost (~€1-2/mo) for the Floating IP. Routing the Floating IP to the active ingress path still needs to be wired at the Hetzner network level as part of that companion change — not done as of this writing.

## Considered options

- Skip the Floating IP, let external-dns chase node IP changes on every replacement — rejected: the resulting propagation gap and cert re-issuance churn wasn't worth the small savings.
