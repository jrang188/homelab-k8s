# `apps/authentik` — Authentik (wrapper chart)

[Authentik](https://goauthentik.io/) is an open-source identity provider
(SSO/OIDC/SAML/LDAP) deployed as a wrapper Helm chart around the official
[`goauthentik/authentik`](https://github.com/goauthentik/helm) chart (pinned to
**2026.8.0** in `Chart.yaml`). ArgoCD's `apps` ApplicationSet auto-discovers
this directory on merge, creating the `authentik` namespace + Application
(`argocd-resources/applicationset-apps.yaml`, with `CreateNamespace=true`).

## Shape

- **Wrapper chart** (`Chart.yaml`): a single `dependencies:` entry pinning the
  upstream chart; everything else overrides it in `values.yaml`.
- **Home-node pinning** (`values.yaml`): `global.nodeSelector` +
  `global.tolerations` pin the Authentik server and worker to the home node;
  the bundled PostgreSQL subchart is pinned via `postgresql.primary.*` — all
  per [ADR-0002](../../docs/adr/0002-home-node-pinning-and-scoped-storage.md).
- **Storage** (`values.yaml`): PostgreSQL's PVC uses the home-node-scoped
  `local-path` StorageClass, per
  [ADR-0007](../../docs/adr/0007-broaden-home-node-storage-to-general-purpose.md).
- **Exposure** (`templates/authentik-tailscale-service.yaml`): tailnet-only via
  the Tailscale Kubernetes operator — `type: LoadBalancer` +
  `loadBalancerClass: tailscale` + `tailscale.com/hostname: authentik`, exactly
  like `apps/searxng`. Authentik is the IdP for the tailnet, so it is
  deliberately **not** behind the public Traefik/Cloudflare path. The upstream
  chart's Service template has no `loadBalancerClass` key, so we leave its
  in-cluster ClusterIP service and write the LB Service by hand.
- **Secrets** (`templates/external-secret.yaml`): via ESO + 1Password
  (`ClusterSecretStore/onepassword`). The chart's own generated config secret
  is skipped (`authentik.authentik.existingSecret.secretName`); a
  `authentik-config` secret carries the `AUTHENTIK_*` env the server/worker
  load via envFrom, and `authentik-postgres-credentials` feeds the bundled
  PostgreSQL subchart.

## Decisions worth flagging

- **Existing secret over chart-generated secret.** The upstream chart renders
  `authentik.secret_key` and `authentik.postgresql.password` straight into a
  Secret it generates — those would be committed to git. Pointing
  `existingSecret.secretName` at the ESO/1Password-managed `authentik-config`
  (as `apps/searxng` does) keeps every real secret out of the repo.
- **Bootstrap superuser.** `AUTHENTIK_BOOTSTRAP_PASSWORD` is injected so the
  initial admin user is created automatically on first boot; you can remove
  that one data entry and create the admin interactively instead if you prefer.
- **PostgreSQL admin user disabled** (`postgresql.auth.enablePostgresUser:
  false`) — the `authentik` app user/database is all that's needed; no separate
  superuser password to store.

## Pinned chart / versions

- `goauthentik/authentik` chart **2026.8.0** (app 2026.8.0), `Chart.lock`
  records the resolved digest. To upgrade: bump the version in `Chart.yaml`
  and re-run `helm dependency update apps/authentik` (the vendored `charts/*.tgz`
  are gitignored; `Chart.lock` is committed).
- `helm dependency update apps/authentik && helm template apps/authentik -f apps/authentik/values.yaml && helm lint apps/authentik` all pass locally.

## Required out-of-band setup (before this Application goes healthy)

1Password items (vault `Development`, matching `infra/eso`'s ClusterSecretStore)
must exist before the ExternalSecrets stop reporting `SecretSyncedError`:

| 1Password item        | Field              | Used by                     |
| --------------------- | ------------------ | --------------------------- |
| `authentik/secret-key`        | `secret-key`        | `AUTHENTIK_SECRET_KEY` (cookie/user-ID signing) |
| `authentik/postgres-password` | `postgres-password` | PostgreSQL app-user password |
| `authentik/bootstrap-password`| `bootstrap-password`| initial admin user bootstrap |

Generate e.g. `openssl rand -hex 32`.