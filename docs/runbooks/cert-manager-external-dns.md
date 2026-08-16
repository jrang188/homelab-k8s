# Runbook: cert-manager + external-dns go-live

Human steps to activate `infra/cert-manager` and `infra/external-dns` after
they sync via ArgoCD. Both charts are inert until these are done — the
ExternalSecrets will stay in `SecretSyncedError` and DNS won't converge.

Prerequisite: `infra/eso` is already synced and healthy (issue #5) — the
`onepassword-token` bootstrap Secret exists in the `eso` namespace.

## 1. Create the Cloudflare API token

1. In the Cloudflare dashboard: **My Profile → API Tokens → Create Token**.
2. Scope: `Zone.DNS: Edit` on the zone(s) this cluster will manage.
3. Copy the token value.

## 2. Store it in 1Password

1. In the `Development` vault (matches `infra/eso`'s `ClusterSecretStore`),
   create an item named `cloudflare-api-token`.
2. Add a field named `api-token` with the token value from step 1.
3. Both charts' `ExternalSecret`s pull this same item/field.

## 3. Provision the Floating IP

1. In `opentofu-infra`, add/apply the Hetzner Floating IP resource per
   [ADR-0005](../adr/0005-public-exposure-via-cloudflare-and-floating-ip.md)
   (small recurring cost, ~€1-2/mo).
2. Route it to the active ingress path at the Hetzner network level.
3. Note the resulting IPv4 address.

## 4. Fill in the two operator-supplied values

In this repo:

1. [`infra/external-dns/values.yaml`](../../infra/external-dns/values.yaml)
   — replace `REPLACE_WITH_FLOATING_IP` with the address from step 3.
2. [`infra/cert-manager/values.yaml`](../../infra/cert-manager/values.yaml)
   — replace `REPLACE_WITH_ACME_EMAIL` with the email Let's Encrypt should
   send expiry/registration notices to.
3. Commit and push to `main`.

## 5. Verify

1. `kubectl get externalsecret -n cert-manager -n external-dns` — both
   `cloudflare-api-token` should show `SecretSynced`.
2. `kubectl get clusterissuer cloudflare` — should show `Ready: True`.
3. `kubectl logs -n external-dns deploy/external-dns` — should show DNS
   records being created/synced, no auth errors.
4. Point a test `Ingress` (with a `cert-manager.io/cluster-issuer: cloudflare`
   annotation and a `tls` block) at a hostname in the managed zone; confirm a
   `Certificate` goes `Ready` and the hostname resolves to the Floating IP.
