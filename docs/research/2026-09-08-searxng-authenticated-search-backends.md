# Authenticated (API-key) search backends for SearXNG — worth adding?

**Date:** 2026-09-08
**Status:** Recommendation (not yet implemented)
**Scope:** Whether `apps/searxng` should add an authenticated/API-key search engine alongside
its current 8 free, scrape-based engines (google, brave, duckduckgo, startpage, bing, yahoo,
qwant, mojeek).

## Problem

All currently-enabled engines are HTML-scraping, no API key, inherently fragile against
anti-bot detection — this is what caused the original incident (multiple engines simultaneously
IP-flagged after a query burst). A prior internal handoff document claimed the Google CSE JSON
API is "discontinued (sunset 2027)" and recommended adding the Brave Search API via SearXNG's
`braveapi` engine. This doc verifies those claims against primary sources and gives a final
recommendation.

## TL;DR recommendation

**Not worth it right now.** Of the three most obvious options, two are dead ends (Google CSE is
closed to new signups; Bing's API no longer exists at all) and the one that's actually viable
(Brave Search API) would cost real operational overhead — an API key to provision via ESO/
1Password, a paid tier with usage to watch — for a single user + one agent whose actual query
volume almost certainly stays inside engine-diversity's existing coverage. Revisit only if the
8-engine scrape fallback starts producing genuinely degraded results on a regular basis, not
preemptively.

## Findings

### 1. Google Custom Search JSON API — confirmed dead end, don't pursue

Per [Google's own Custom Search JSON API overview](https://developers.google.com/custom-search/v1/overview)
(checked 2026-09-08):

- **Closed to new customers.** Only existing customers as of the closure date can still use it.
- **Hard sunset: January 1, 2027.** Quoted directly: "Existing Custom Search JSON API customers
  have until January 1, 2027 to transition to an alternative solution."
- Free tier (for existing customers only) is 100 queries/day; $5/1000 queries beyond that, up
  to 10k/day.

The prior handoff's claim is accurate, and it's moot either way — this repo has no existing CSE
credential, so there is no path to obtain one at all as a new integration. Not viable, full
stop.

### 2. Bing / Microsoft Search API — fully retired, no viable replacement

Per multiple 2025 industry reports on Microsoft's own announcement: the Bing Search API (all
versions, v7 included) was **retired August 11, 2025**, announced May 12, 2025 (~3 months'
notice). There is no drop-in successor. Microsoft's stated replacement, "Grounding with Bing
Search" under Azure AI Agents, is an AI-agent-integrated product (returns grounded LLM
responses, not a SERP JSON payload) and reported to cost **40–483% more** than the old API for
equivalent usage ([ppc.land coverage](https://ppc.land/microsoft-ends-bing-search-apis-on-august-11-alternative-costs-40-483-more/)).
Not a fit for SearXNG's engine model (which expects a search-results response, not an
agent-grounding response) and not cost-effective even if it were. The `bing` engine already
enabled in this repo is the free HTML-scrape engine (`searx/engines/bing.py`), unaffected by
this — that stays as-is regardless.

### 3. Brave Search API — the one real option, confirmed current and supported

Per [Brave's own Search API pricing page](https://brave.com/search/api/) (checked 2026-09-08):

- **Search plan:** $5 per 1,000 requests, **$5 in free monthly credits** applied automatically
  (≈1,000 free queries/month), 50 queries/second capacity.
- No explicit personal/non-commercial restriction found on the pricing page itself; full ToS
  terms live behind the API dashboard and weren't independently reviewed here — check before
  committing if this gets picked up later.
- SearXNG has a **maintained, current** dedicated engine for this:
  [`searx/engines/braveapi.py`](https://github.com/searxng/searxng/blob/master/searx/engines/braveapi.py)
  (confirmed present, `require_api_key: True`, `use_official_api: True`, calls
  `https://api.search.brave.com/res/v1/web/search` with an `X-Subscription-Token` header). It's
  registered `inactive: true` in the default `settings.yml` — enabling it is exactly the
  `api_key: !ENV ...` + un-inactive pattern the prior handoff described, matching this repo's
  existing ESO/1Password wiring convention (see `apps/searxng/external-secret.yaml`). This part
  of the handoff was accurate and technically sound if the operator wants to pursue it.

### 4. Other API-keyed engines SearXNG supports

Confirmed present in `searx/engines/` (current upstream): `kagi.py` (Kagi Search API, requires
a paid Kagi subscription + API key, `require_api_key: True`), `exaapi.py` (Exa — an AI/semantic
search API oriented at RAG/agent use cases, paid, `require_api_key: True`), `yandex_api.py`
(Yandex's cloud search API, paid/quota-based, `require_api_key: True`). None found to have a
meaningfully better free tier than Brave's for this use case, and Kagi in particular assumes an
existing paid Kagi subscription (not a standalone pay-per-query API), which doesn't fit a
"just add search API access" ask. No dedicated free-tier Mojeek API engine exists in SearXNG —
the already-enabled `mojeek` engine is the free scrape version.

### 5. Is the overhead worth it for this instance's actual volume?

Given the current setup is exactly one human (occasional tailnet browsing) plus one AI agent
(Hermes' web-search tool), realistic combined volume is very likely well under Brave's ~1,000
free queries/month — meaning cost isn't really the blocker. The blocker is everything *around*
the cost: provisioning and rotating a Brave API key through ESO/1Password, watching usage
against the free-credit ceiling so a burst month doesn't silently start billing, and carrying
one more secret + one more thing that can break (an expired key, a changed pricing tier) for a
homelab tool. Given the 8-engine scrape fallback already exists specifically to make single-
engine failures a non-event (that was the whole point of PR #53's Tier-2 additions), adding an
authenticated engine mainly buys *result quality* headroom, not reliability — the reliability
problem is already addressed.

## Recommendation

**Don't add an authenticated backend now.** Revisit if:
- The 8-engine scrape fan-out starts visibly degrading (e.g. `unresponsive_engines` showing
  multiple engines suspended simultaneously on a regular basis, not just after one bad burst), or
- Result *quality* (not availability) becomes a real complaint — Brave's API generally returns
  cleaner, more consistent results than scraping — at which point `braveapi` is a known-good,
  low-effort addition since the engine already exists and just needs a key.

If it's ever added, the `braveapi` engine's `inactive: true` flag needs to be flipped alongside
setting `api_key`, in the same `engines:` list already managed via `settings-configmap.yaml`.

## References

- [Google Custom Search JSON API overview](https://developers.google.com/custom-search/v1/overview) — closure/sunset details, checked 2026-09-08
- [Brave Search API pricing](https://brave.com/search/api/) — checked 2026-09-08
- [Microsoft ends Bing Search APIs on August 11 — ppc.land](https://ppc.land/microsoft-ends-bing-search-apis-on-august-11-alternative-costs-40-483-more/)
- [searx/engines/braveapi.py](https://github.com/searxng/searxng/blob/master/searx/engines/braveapi.py)
- [searx/engines/brave.py](https://github.com/searxng/searxng/blob/master/searx/engines/brave.py) — confirms the already-enabled `brave` engine is the free scrape variant, distinct from `braveapi`
- [searx/engines/kagi.py](https://github.com/searxng/searxng/blob/master/searx/engines/kagi.py), [searx/engines/exaapi.py](https://github.com/searxng/searxng/blob/master/searx/engines/exaapi.py), [searx/engines/yandex_api.py](https://github.com/searxng/searxng/blob/master/searx/engines/yandex_api.py)
- `searx/settings.yml` upstream default — `braveapi` engine entry, `inactive: true`
