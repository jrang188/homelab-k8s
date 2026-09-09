# Hermes Agent community sentiment on SearXNG and engine choice

**Date:** 2026-09-08
**Status:** Informational
**Scope:** What NousResearch/hermes-agent's own documentation and GitHub issue/PR history say
about running SearXNG as a `web_search` backend — a second, independent data source alongside
`2026-09-08-searxng-community-engine-reliability.md`'s searx.space analysis.

## Where this comes from

Hermes Agent ([NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)) is a
real open-source project with its own docs site, an official `searxng-search` optional skill
(the exact skill referenced in this instance's own Hermes pod logs — "Refusing background
curator patch for hub-installed skill 'searxng-search'"), and an active issue/PR tracker. This
is the actual upstream project this deployment's `hermes-agent` image is built from, so its
docs and issues are as close to primary-source "community sentiment" as it gets — not third-
party opinion.

## Official guidance matches what we already found independently

- The `web-search` docs page states plainly: *"For production use, self-hosting is strongly
  recommended"* — public SearXNG instances carry rate limits and uptime variability that
  self-hosting avoids.
- The `searxng-search` `SKILL.md` lists rate limiting under **Limitations**: *"Some public
  instances limit requests. Self-hosting avoids this."* — the project's own mental model is
  that a self-hosted instance should **not** be rate-limited. This independently validates the
  Option A decision (removing `SEARXNG_LIMITER`) — it's not a workaround this repo invented, it
  matches the tool author's own assumption about how self-hosting is supposed to work.
- Its **Troubleshooting** table lists "Empty results → Instance blocks the query → Try a
  different instance or self-host" — i.e. the project already expects engine-level blocking to
  be the dominant self-hosted failure mode, not something unusual.
- Every example command in the skill's own documentation filters to **`engines=google,bing`**
  — never the full default set, never qwant/mojeek/startpage/duckduckgo/brave. This is an
  independent signal, from the tool author's own reference examples, that lines up almost
  exactly with the reliability-data-driven recommendation in the companion doc (keep
  `google`+`google cse`+`bing`+`yahoo` as the core set).

## The real finding: this exact failure mode is a known, currently-unresolved gap in Hermes itself

Searching hermes-agent's issue tracker for "searxng" surfaces a cluster of very recent (Jun–Sep
2026), still-**open** PRs/issues, all converging on the same defect:

**The core bug:** when SearXNG's upstream engines get CAPTCHA'd/rate-limited, SearXNG itself
returns **HTTP 200 with an empty result list** plus an `unresponsive_engines` field — not an
error. Hermes' web-search provider (as currently released) treats that as a *successful* empty
search, not a failure, so:
- its "keyless rescue" / fallback-chain logic (meant to retry a failed call on another provider)
  never triggers, because it only fires on explicit failure, and
- the empty result gets cached for the response TTL, so even a moment of upstream flakiness can
  poison results for a while after.

This is not a hypothetical: **two independent operators hit this in production**, reported in
[PR #36838](https://github.com/NousResearch/hermes-agent/pull/36838)'s discussion:

- **@ZsZolee**: self-hosted SearXNG returned 0 results when upstream engines blocked their
  datacenter IP; their configured Brave-API fallback never got called because SearXNG "succeeded"
  with nothing.
- **@ScotterMonk**: reports a **production pipeline failure lasting days** after their
  self-hosted SearXNG's upstream engines got blocked — *"Brave 429, DuckDuckGo/Startpage CAPTCHA,
  Qwant/Wikidata/Reddit 403"* — nearly the identical engine list and failure signature as this
  repo's own original incident, from a completely unrelated operator.

`teknium1` (NousResearch) reviewed the fix in [PR #76329](https://github.com/NousResearch/hermes-agent/pull/76329)
and **confirmed the defect in production** — this is acknowledged internally, not just an
outside bug report.

## Fixes exist but are not yet merged — don't assume they're in your current image

As of 2026-09-08, all of the following are **open, unmerged**:

| # | Title | What it fixes |
|---|---|---|
| [#76329](https://github.com/NousResearch/hermes-agent/pull/76329) | fix(web): surface SearXNG engine failures | Original fix for the empty-vs-failure bug; hit merge conflicts after a provider refactor |
| [#104030](https://github.com/NousResearch/hermes-agent/pull/104030) | fix(web): treat SearXNG empty reply with unresponsive engines as failure | Narrower rebase of #76329 against current codebase; explicitly "complementary, not competing" |
| [#36838](https://github.com/NousResearch/hermes-agent/pull/36838) | feat(web): runtime fallback chain for search/extract providers | Walks Firecrawl→Parallel→Tavily→Exa→SearXNG→Brave-free→DDGS on failure |
| [#80201](https://github.com/NousResearch/hermes-agent/issues/80201) | Per-provider cooldown in fallback chain | Skips a provider for ~10min after 2 consecutive errors or 3 empty-but-"successful" responses, so a stuck SearXNG doesn't get re-hit (and re-burn paid fallback quota) on every single query |
| [#48645](https://github.com/NousResearch/hermes-agent/pull/48645) | fix(searxng): use format=html + regex parsing for private instances | Alternative to `format=json` — parses the rendered HTML page instead, "always available on every instance, no formats config required" |
| [#99399](https://github.com/NousResearch/hermes-agent/issues/99399) | make the SearXNG provider HTTP timeout configurable (currently hardcoded 15s) | Currently fixed at 15s regardless of instance load |

None of this is in the currently-running image as of this repo's pinned tags. Practically: **the
resilience for this class of failure has to come from the SearXNG side (engine selection) right
now**, because Hermes itself doesn't yet reliably detect "SearXNG technically responded but every
engine is blocked" as a failure worth falling back from. This directly reinforces why the
engine-reliability work in the companion doc matters more than it would once these PRs land —
today, a bad engine list doesn't just degrade results, it can silently return nothing with no
visible error and no fallback, for as long as the block lasts.

## Note on PR #48645's stated reasoning (flagged, not fully verified)

That PR's description claims SearXNG "intentionally returns HTTP 403 when `format=json` is
requested on instances with `server.public_instance: false`." This doesn't match this repo's own
direct testing tonight (JSON format worked fine at HTTP 200 without the limiter; the failure
mode we hit was a 429 from the `http_user_agent` botdetection check, not a 403 tied to
`public_instance`). It's plausible the PR author encountered the same class of problem (a
private/self-hosted instance rejecting programmatic JSON requests) but attributed the mechanism
slightly differently, or hit a different SearXNG version's behavior. Their fix (falling back to
`format=html` + regex parsing) is a reasonable workaround regardless of the exact stated cause —
worth knowing it exists as an option, without taking the specific "403 on public_instance:false"
claim as verified fact.

## Takeaways

1. Removing `SEARXNG_LIMITER` (Option A, already done) matches the Hermes project's own stated
   assumption about self-hosted instances — this isn't a one-off local decision, it's aligned
   with upstream's mental model.
2. The engine-reliability findings in the companion doc aren't just "more accurate" than the
   current default list — they matter *more* than they would in isolation, because Hermes
   currently has no safety net if the enabled engines all fail at once (that safety net is
   actively being built, just not shipped yet).
3. Worth periodically checking whether #76329/#104030/#36838/#80201 land in a future release —
   once they do, this instance's exposure to "all engines blocked → silent empty result" drops
   significantly independent of any SearXNG-side config.
4. If `format=html` (#48645) lands and gets adopted, it would sidestep the JSON-specific
   `API_MAX=4/hour` cap entirely (that cap only applies when `format != html`) — not relevant
   right now since the limiter is off, but worth knowing if the limiter question is ever
   revisited.

## References

- [hermes-agent SKILL.md — searxng-search](https://raw.githubusercontent.com/NousResearch/hermes-agent/main/optional-skills/research/searxng-search/SKILL.md)
- [Web Search & Extract docs](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-search)
- [PR #36838 — runtime fallback chain](https://github.com/NousResearch/hermes-agent/pull/36838) (see @ZsZolee, @ScotterMonk, @teknium1 comments)
- [Issue #80201 — per-provider cooldown](https://github.com/NousResearch/hermes-agent/issues/80201)
- [PR #76329](https://github.com/NousResearch/hermes-agent/pull/76329) / [PR #104030](https://github.com/NousResearch/hermes-agent/pull/104030) — empty-reply-as-failure fix
- [PR #48645 — format=html fallback for private instances](https://github.com/NousResearch/hermes-agent/pull/48645)
- [Issue #99399 — configurable timeout](https://github.com/NousResearch/hermes-agent/issues/99399)
