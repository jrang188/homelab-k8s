# Runbook: cert-manager + external-dns go-live

Human steps to activate `infra/cert-manager` and `infra/external-dns` after
they sync via ArgoCD. Both charts are inert until these are done — the
ExternalSecrets will stay in `SecretSyncedError` and DNS won't converge.

Prerequisite: `infra/eso` is already synced and healthy (issue #5) — the
`onepassword-token` bootstrap Secret exists in the `eso` namespace.

## 0. Get a domain onto Cloudflare

Both charts need a Cloudflare zone to write into — this has to exist before
step 1.

1. Own a domain (register one if needed).
2. Cloudflare dashboard → **Add a Site**, enter the domain — this creates
   the zone.
3. Update the domain's nameservers at your registrar to the ones Cloudflare
   gives you, so Cloudflare becomes authoritative. Allow time to propagate.

## 1. Create the Cloudflare API token

1. In the Cloudflare dashboard: **My Profile → API Tokens → Create Token**.
2. Scope: `Zone.DNS: Edit` on the zone from step 0.
3. Leave **Client IP Address Filtering** and **TTL** blank/default — the
   token is called from pods that can land on any control plane (no fixed
   egress IP to filter to), and there's no rotation automation in this repo
   to handle an expiring token.
4. Copy the token value.

## 2. Store it in 1Password

All three of these must match exactly or ESO silently fails to create the
Secret — see the troubleshooting note below.

1. Vault: **`Development`**. Not `Personal`. `infra/eso`'s
   `ClusterSecretStore` is pinned to a single vault (`spec.provider.
   onepasswordSDK.vault`), and the ESO service account is only granted
   access to that one — an item anywhere else is invisible to the cluster.
2. Item name: **`cloudflare-api-token`** (singular).
3. Field name: **`api-token`**.

Both charts' `ExternalSecret`s resolve this as `<item>/<field>`, matching
the convention already used by `infra/tailscale-operator` and
`infra/victoria-metrics`.

Verify before syncing anything:

```bash
op item get cloudflare-api-token --vault Development --fields api-token
```

### If the ExternalSecret won't sync

Symptom: `kubectl get externalsecret -A` shows `SecretSyncedError`, and the
`ClusterIssuer` reports `failed to get secret "cloudflare-api-token"`. ESO's
log gives the real reason:

```bash
kubectl logs -n eso -l app.kubernetes.io/name=external-secrets --tail=50
```

`no item matched the secret reference query` means the vault, item name, or
field name doesn't match the three values above — not that the token is
invalid. Fix the 1Password item; no repo change is needed. (Hit for real on
first go-live: the item had been created as `cloudflare-api-tokens` — plural
— in the `Personal` vault.)

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

## 4. ACME email — done

[`infra/cert-manager/values.yaml`](../../infra/cert-manager/values.yaml)'s
`acmeEmail` is set to `justinang177@gmail.com` (matches this repo's git
commit author / GitHub identity). Not a secret — Let's Encrypt doesn't
publish it or embed it in issued certs — but it is PII, so treat changing
it as a deliberate choice, not something to default carelessly in other
repos.

## 5. Sync the Applications

The `infra` ApplicationSet template sets no `syncPolicy.automated`, so a
newly discovered Application is created but never syncs on its own — it sits
`OutOfSync` until told otherwise. Sync `cert-manager` **first** and confirm
its `ExternalSecret` resolves before syncing `external-dns`, so a wrong
1Password item is caught before any real DNS records get written:

```bash
argocd app sync cert-manager
```

Then, once step 6's first two checks pass:

```bash
argocd app sync external-dns
```

## 6. Verify

1. `kubectl get externalsecret -n cert-manager -n external-dns` — both
   `cloudflare-api-token` should show `SecretSynced`.
2. `kubectl get clusterissuer cloudflare` — should show `Ready: True`.
3. `kubectl logs -n external-dns deploy/external-dns` — should show DNS
   records being created/synced, no auth errors.
4. Point a test `Ingress` (with a `cert-manager.io/cluster-issuer: cloudflare`
   annotation and a `tls` block) at a hostname in the managed zone; confirm a
   `Certificate` goes `Ready` and the hostname resolves to the Floating IP.
