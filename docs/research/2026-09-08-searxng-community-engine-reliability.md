# What the SearXNG community actually runs — engine reliability, by the numbers

**Date:** 2026-09-08
**Status:** Recommendation (not yet implemented)
**Scope:** Which general-web engines are worth enabling in `apps/searxng`, based on real aggregate
reliability data across the whole public SearXNG instance community — not opinion or forum anecdote.

## Method

[searx.space](https://searx.space) — the project's own community-run instance directory —
publishes machine-readable reliability stats at `https://searx.space/data/instances.json`,
gathered by an automated checker (`searx-checker`) that polls every listed public instance and
records, per engine, an `error_rate` (0–100) reflecting how often that engine failed to return
results *at that instance* recently. Data refreshes roughly every 24h. I downloaded the current
snapshot directly and computed the mean/median error rate per engine across all 92 currently-
listed public instances (excluding engines with no data on a given instance).

This is the closest thing that exists to "what does the community actually experience" —
aggregated across dozens of independent operators, IPs, and network paths, so it's not just
one homelab's anti-bot luck.

## Findings: current engine list, ranked by real-world reliability

| Engine | Currently in `apps/searxng`? | n (instances reporting) | Mean error % | Median error % |
|---|---|---:|---:|---:|
| `bing` | ✅ added (#53) | 14 | 7.5 | **0** |
| `google` (plain) | ❌ not enabled | 42 | 14.5 | **10** |
| `yandex` | ❌ not enabled | 15 | 27.3 | 0 (small sample, often geo-restricted) |
| `yahoo` | ✅ added (#53) | 42 | 35.2 | 25 |
| `yep` | ❌ not enabled | 28 | 42.3 | 45 |
| `duckduckgo` | ✅ default | 55 | 58.4 | 55 |
| `google cse` | ✅ default (the one actually active) | 35 | **67.0** | **75** |
| `duckduckgo web` | (variant, not separately configured here) | 25 | 68.4 | 80 |
| `brave` | ✅ default | 48 | 70.4 | 90 |
| `qwant` | ✅ added (#53) | 52 | 81.2 | **100** |
| `mojeek` | ✅ added (#53) | 45 | 84.1 | **100** |
| `startpage` | ✅ default | 55 | 94.8 | **100** |

Lower is better — a 100 median means half of all public instances see this engine fail *every
single time* it's queried.

## The standout finding: you're running the worse of the two Google engines

SearXNG ships **two independent Google engines**: `google` (plain scrape, community median
error **10%**) and `google cse` (scrapes Google's embeddable Custom Search widget — not the
paid API, confirmed `require_api_key: False` in source — community median error **75%**).
Upstream ships `google` (plain) as `disabled: true` by default and `google cse` as the enabled
default. This repo inherits that default via `use_default_settings: true`, so it's running the
engine the community data says fails 3 out of 4 times, while the much more reliable sibling
engine sits disabled one line away. This matches what was observed live on this instance
tonight too: `google cse` was the only engine returning results after the recent incident,
which is consistent with it being the default active engine — not evidence it's especially
reliable, just evidence it's the one running.

## The Tier-2 additions (#53) are, on this data, mostly not adding real resilience

PR #53 added bing/yahoo/qwant/mojeek specifically for fan-out resilience — the idea that if a
few engines get blocked, others pick up the slack. The community data says two of those four
(`bing`, `yahoo`) genuinely deliver on that; the other two (`qwant`, `mojeek`) have a **100%
median failure rate across the entire public instance fleet** — meaning most operators running
them get nothing back, ever, not just this instance during an anti-bot episode. This lines up
exactly with what was observed live tonight: `qwant` CAPTCHA'd on its very first request from a
completely fresh pod, and `mojeek` returned zero results even for the trivial query "python."
`mojeek` also has a multi-year history of open GitHub issues (parsing errors, XPath exceptions,
403s, and — as recently as March 2026 — a reported ~50% timeout failure rate even when it does
respond: [searxng/searxng#5797](https://github.com/searxng/searxng/issues/5797),
[#5504](https://github.com/searxng/searxng/issues/5504),
[#4307](https://github.com/searxng/searxng/issues/4307)). This isn't this instance's IP being
flagged — it's a chronically fragile engine integration, community-wide.

`brave`, `duckduckgo`, and `startpage` (the pre-existing defaults) sit in a worse middle
ground than they'd get credit for: median 90%, 55%, and 100% respectively. `startpage` in
particular is statistically almost as dead-on-arrival as `qwant`/`mojeek` — it's just an
upstream default, not something this repo chose to add.

## Recommendation

1. **Enable plain `google` alongside (or instead of) `google cse`.** Flip its `disabled: true`
   in an engine override, same pattern already used for the #53 additions. Given they scrape
   different Google surfaces, running both costs little and gives two independent shots at
   Google results instead of one unreliable one.
2. **Keep `bing` and `yahoo`** — the data backs up that they're carrying real weight, not just
   filling out a list.
3. **Drop `qwant` and `mojeek`.** Zero evidence they contribute anything most of the time,
   community-wide or on this instance specifically, and they add latency + log noise
   (`unresponsive_engines` clutter) for no return. `startpage` is nearly as bad and is worth
   considering for removal too, though it's an upstream default rather than something added
   here.
4. **`brave` and `duckduckgo`** are borderline — worse than bing/yahoo/google, better than the
   qwant/mojeek/startpage bottom tier. Reasonable to keep as low-cost extra rolls of the dice
   given they occasionally do come through, but don't count on them as primary coverage.

Net effect of 1+3: a smaller, more honest engine list (`google`, `google cse`, `bing`, `yahoo`,
optionally `brave`/`duckduckgo`) that's more likely to give *real* fan-out redundancy instead of
padding the list with engines that fail the vast majority of the time everywhere, not just here.

## The broader catalog — anything else worth considering?

SearXNG ships 346 engines total, but almost all of that is other categories (images, videos,
torrents, social media, science, per-language regional engines) — not general web search. Cross-
referencing the actual `general`/`web`-category engines against the same searx.space reliability
data surfaces a few more real candidates and a lot of noise:

- **`naver`** (Korean) — excellent reliability (median 0%, n=13), but Korean-language search
  results; not useful for an English-language homelab instance unless bilingual use is wanted.
- **`yandex`** (Russian, plain scrape, no API key) — decent median reliability (0%, though a
  noisier mean of 27.3% — likely some instances geo-block it). Functionally viable, but Yandex
  is a Russian company; worth being deliberate about that rather than adding it reflexively.
  `yandex_api` also exists as a separate paid/keyed engine (see the authenticated-backends doc)
  — this is the free scrape variant, distinct from that.
- **`mwmbl`** (n=19, mean 35%, median 20%) — a genuinely different kind of engine: a non-profit,
  open, community-indexed search project (no scraping-ToS risk since it's a real API,
  `use_official_api: True`, `require_api_key: False`). Interesting philosophically, but its own
  docstring in source is explicit that it's still "little more than an idea together with a
  proof-of-concept... on a small index" — responding successfully doesn't mean it has real
  coverage. Not a serious primary-source candidate yet, worth revisiting as the project matures.
- **`dogpile`** and **`yacy`** (mean ~51% each) — both are themselves meta-search engines (dogpile
  aggregates other engines; YaCy is a decentralized P2P search network requiring either a public
  peer or running your own node). Layering SearXNG's own aggregation on top of another
  aggregator is redundant, and YaCy specifically would mean either trusting a random public peer
  or standing up real new infrastructure — not worth it here.
- **`seznam`** (Czech, mean 47.8%) and **`quark`**/**`baidu`**/**`sogou`** (Chinese, all mean
  90%+) — region-specific, not applicable.
- Everything else in the general/web category (`gmx`, `fireball`, `infospace`,
  `resulthunter`, `searchmysite`, `privacywall`, `fastbot`, `tusksearch`, `vuhuv`, `gabanza`,
  `searchtoday`, `searchrockit`, and similar) sits at 85–100% mean/median error — the long tail
  of engines that exist in the codebase but essentially never work for anyone, community-wide.

Nothing here beats the recommendation already made above (`google` + `google cse` + `bing` +
`yahoo`, `brave`/`duckduckgo` as low-priority extras). `yandex` is the one genuine "maybe" from
this broader pass, worth a deliberate yes/no rather than a default add.

## Caveats

- `error_rate` reflects recent failures at each specific instance — it can include transient
  outages, not just permanent brokenness, so treat this as a strong prior, not gospel. The
  `qwant`/`mojeek`/`startpage` 100% medians are damning specifically because they're medians
  across *55, 45, and 52 independent instances respectively* — that's not one bad day.
- Sample sizes vary (`bing` n=14 vs `duckduckgo` n=55) — smaller samples are noisier; `bing`'s
  excellent number should be read with that in mind, though it also matched this instance's own
  live test tonight (worked, if with one quality hiccup on an unrelated query).
- This data doesn't measure *result quality* when an engine does respond, only whether it
  responds at all. The live test tonight also surfaced a `bing` quality issue (irrelevant
  Arabic-language results for one query, fine for another) that this dataset wouldn't catch —
  reliability and quality are related but distinct questions.

## References

- [searx.space instance data](https://searx.space/data/instances.json) — raw source for the table above, snapshot taken 2026-09-08
- [searx/engines/google.py](https://github.com/searxng/searxng/blob/master/searx/engines/google.py) vs [searx/engines/google_cse.py](https://github.com/searxng/searxng/blob/master/searx/engines/google_cse.py)
- `searx/settings.yml` upstream default — `google` entry has `disabled: true`, `google cse` does not
- [searxng/searxng#5797](https://github.com/searxng/searxng/issues/5797), [#5504](https://github.com/searxng/searxng/issues/5504), [#4307](https://github.com/searxng/searxng/issues/4307), [#1218](https://github.com/searxng/searxng/issues/1218) — mojeek engine's multi-year bug history
