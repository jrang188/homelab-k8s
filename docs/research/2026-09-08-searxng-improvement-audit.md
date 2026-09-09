# SearXNG deployment improvement audit

**Date:** 2026-09-08
**Status:** Recommendations (none implemented yet — this is a punch list, not a plan)
**Scope:** `apps/searxng` — improvements beyond the rate-limiting issue (resolved separately,
see the companion doc `2026-09-08-searxng-limiter-api-client-compatibility.md`).

## Context

Single-replica, no-PVC, ConfigMap-driven plain-manifest deployment. Tailnet-only, home-node-
pinned, non-root. Backs one human (occasional browser use) and one AI agent (`format=json`
calls). Cluster already runs Grafana + VictoriaMetrics + VictoriaLogs + ESO/1Password — this
audit weighs each recommendation against "is it worth the overhead for a single-user homelab
instance," not against what a public multi-tenant instance would want.

## Recommendations, prioritized

### 1. Wire `/metrics` into VictoriaMetrics — worth doing, low effort

SearXNG's default `settings.yml` already sets `general.enable_metrics: true` (records to
`/stats`, `/stats/errors`, `/preferences` — no action needed, already on). Separately,
`general.open_metrics: '<password>'` (empty/disabled by default) exposes a Prometheus/
OpenMetrics-format `/metrics` endpoint, protected by HTTP Basic Auth where **only the password
is validated** (per `docs/admin/settings/settings_general.rst` upstream — the username can be
anything). Since this cluster already has ESO/1Password and a VictoriaMetrics operator:

- Generate a password, store it via ESO the same way `SEARXNG_SECRET` already is, set
  `SEARXNG_OPEN_METRICS` (or the equivalent `settings.yml` key) to it.
- Add a `VMServiceScrape` (this cluster uses the VictoriaMetrics operator, not vanilla
  Prometheus ServiceMonitors) pointing at the `searxng` Service, port 8080, path `/metrics`,
  with `basicAuth` referencing the same secret.

Low effort, genuinely useful given `/stats/errors` (the engine-suspension view referenced in
the limiter doc) becomes queryable/alertable instead of something you have to remember to check
by hand. Worth doing.

### 2. `unresponsive_engines` monitoring — worth a lightweight version, skip full alerting

Following on from #1: once metrics are flowing, a simple Grafana panel or VictoriaLogs query
against engine-error log lines would surface "an engine has been suspended for N hours" without
manual `/stats/errors` checks. A full alert rule is probably overkill for a single-user
instance where "search felt degraded today" isn't a page-worthy event — a dashboard panel you
glance at occasionally is proportionate; a PagerDuty-style alert is not.

### 3. Image proxy / ephemeral cache — leave as-is, not worth an emptyDir

`general.image_proxy` defaults to `false` upstream (confirmed in `searx/settings.yml`) and
isn't currently overridden here, so it's already off — SearXNG isn't proxying/caching thumbnail
images through itself at all right now, meaning the "ephemeral cache reset on restart" concern
from the deployment's own header comment doesn't actually apply as written (there's nothing
being cached to lose). If image proxying is ever turned on for privacy reasons (hiding the
client's IP from image hosts), *then* revisit whether an `emptyDir` at `/var/cache/searxng` is
worth adding — for a single low-volume user it still probably isn't; the cache re-populating
after a rare pod restart is a non-event.

### 4. Agent-facing defaults — one real gap worth fixing: explicit `safesearch`

The instance's `settings.yml` override (`settings-configmap.yaml`) currently sets `search.formats`
and the engine list, but doesn't set `search.safesearch`. SearXNG's default is `0` (off) unless
overridden, so this is likely already fine for an agent doing general research — but it's
implicit, inherited from upstream defaults rather than a deliberate choice recorded in this
repo. Worth adding an explicit `safesearch: 0` (or whatever level is actually wanted) to
`settings-configmap.yaml` with a one-line comment on why, so a future SearXNG upgrade changing
its own default doesn't silently change agent behavior. Everything else in `search:` (autocomplete,
language, `max_page`) is UI-facing and doesn't affect JSON-format results meaningfully — not
worth touching for an agent backend.

### 5. `outgoing` tuning — leave defaults, not worth changing

Checked `outgoing.request_timeout` (default 3.0s), `pool_connections` (100), `enable_http2`
(true) against this instance's actual load (one agent, low query volume, single replica). None
of these are remotely close to being a bottleneck at this scale; changing them would be tuning
for a load profile this instance doesn't have. No action.

### 6. Upgrade cadence and health checks — current setup is fine, one small note

Explicit image-tag pinning (`searxng/searxng:2026.8.20-487d7a96e`, per ADR-0001) plus Reloader's
auto-restart-on-ConfigMap-change is a sound pattern already in place; no changes recommended
there. Readiness/liveness probes both hit `/healthz` with reasonable delays (5s/15s initial,
10s/20s period) — fine for a single-replica low-traffic service. The one gap: nothing in this
repo currently tracks new SearXNG releases for security-relevant fixes (the botdetection module
alone has had real behavioral surprises, as this incident showed) — if this repo's Renovate
rollout (see `2026-08-21-renovate-vs-dependabot-for-helm.md`) gets extended to plain-manifest
image tags via its Docker manager, `apps/searxng`'s `image:` line would just work; if not,
periodic manual tag checks remain the fallback. Not urgent, just flagging the gap.

### Explicitly not recommended

- **Result/response caching beyond what SearXNG already does per-engine:** no general-purpose
  result-cache setting was found in `settings.yml` (the `valkey:` block backs the limiter and a
  couple of other botdetection/webapp features, not a search-results cache) — there's nothing
  to enable here even if it were wanted.
- **Any change motivated by "public instance" concerns** (stricter safesearch defaults for
  anonymous users, `public_instance: true`, additional bot-detection): out of scope — this
  instance is tailnet-only by design and should stay that way; don't import public-instance
  hardening patterns that solve problems this deployment doesn't have (the same reasoning that
  drove the limiter removal).

## References

- `apps/searxng/deployment.yaml`, `settings-configmap.yaml`, `service.yaml`, `external-secret.yaml`, `README.md` (this repo, current state as of 2026-09-08)
- [docs.searxng.org — settings_general](https://docs.searxng.org/admin/settings/settings_general.html) — `enable_metrics`/`open_metrics` semantics
- `searx/settings.yml` upstream default (github.com/searxng/searxng) — `image_proxy: false` default, `outgoing:` defaults, `valkey:` usage
- `2026-08-21-renovate-vs-dependabot-for-helm.md` (this repo) — existing automation this could extend to
