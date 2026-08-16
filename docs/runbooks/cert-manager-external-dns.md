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

## 3. Floating IP — done

Already provisioned in `opentofu-infra` (`hcloud_floating_ip.control_planes["0-0-control-plane"]`,
assigned to node 0): `49.12.118.244`. Already filled into
`infra/external-dns/values.yaml`'s `--default-targets`, so nothing to do
here unless the IP changes.

Outstanding: the `ingress_floating_ipv4` output added alongside this
resource isn't in `opentofu-infra`'s state yet — run `tofu apply` there
(should be a no-op on resources, just picks up the output) so `tofu output
ingress_floating_ipv4` works for future reference instead of reading state
directly.

## 4. Fill in the remaining operator-supplied value

In this repo:

1. [`infra/cert-manager/values.yaml`](../../infra/cert-manager/values.yaml)
   — replace `REPLACE_WITH_ACME_EMAIL` with the email Let's Encrypt should
   send expiry/registration notices to.
2. Commit and push to `main`.

## 5. Verify

1. `kubectl get externalsecret -n cert-manager -n external-dns` — both
   `cloudflare-api-token` should show `SecretSynced`.
2. `kubectl get clusterissuer cloudflare` — should show `Ready: True`.
3. `kubectl logs -n external-dns deploy/external-dns` — should show DNS
   records being created/synced, no auth errors.
4. Point a test `Ingress` (with a `cert-manager.io/cluster-issuer: cloudflare`
   annotation and a `tls` block) at a hostname in the managed zone; confirm a
   `Certificate` goes `Ready` and the hostname resolves to the Floating IP.
