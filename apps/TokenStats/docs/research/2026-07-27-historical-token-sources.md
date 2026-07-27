# Is there a source of historical token totals cheaper than scanning every transcript?

Research for [#25](https://github.com/zhangchi0104/agent-sessions/issues/25), a child of
map [#24](https://github.com/zhangchi0104/agent-sessions/issues/24). **No winner is picked here** — this
records what exists, what it contains, and what each option costs. The choice belongs to a later ticket.

Investigated 2026-07-27 on the dev's own machine. Everything below was established against primary
sources: files under `~/.claude` and `~/.codex`, the shipped Claude Code binary
(`~/.local/share/claude/versions/2.1.220`, native install, arm64 Mach-O with the JS bundle embedded),
and this repo's Swift.

**Placement note:** the repo had no research convention — `docs/specs/` at the repo root holds
executable working specs, and `docs/adr/` holds decisions. This is neither. It is the same genre as
`apps/TokenStats/docs/claude-code-integration.md` and `codex-integration.md` — undocumented vendor
facts read out of shipped artefacts — so it sits beside them under a new `apps/TokenStats/docs/research/`.

## Environment the numbers come from

| Fact | Value | Source |
|---|---|---|
| Machine timezone | `Australia/Sydney`, AEST **+1000** | `readlink /etc/localtime`, `date +%Z%z` |
| Claude Code version | 2.1.220 | `~/.local/bin/claude` → `~/.local/share/claude/versions/2.1.220` |
| Codex version | 0.144.4 | `~/.codex/version.json` |
| Roots TokenStats scans | `~/.claude/projects`, `~/.codex/sessions` | `ClaudeCodeIntegration.swift:27`, `CodexIntegration.swift:29` |

The +1000 offset matters — see [UTC day keys](#the-day-keys-are-utc-tokens-today-is-local).

---

## 1. `~/.claude/stats-cache.json`

**Verdict: real, per-day, per-model — and it measures a different quantity than Tokens Today, by a
factor of ~16 on this machine. It is also not live.**

35 KB, mode `0600`, last written **2026-07-18** — ten days stale at the time of writing.

### What is in it

Top-level keys (`~/.claude/stats-cache.json`):

```jsonc
{
  "version": 4,
  "lastComputedDate": "2026-07-17",
  "dailyActivity":    [ { "date": "2025-12-23", "messageCount": 421, "sessionCount": 5, "toolCallCount": 162 } ],  // 117 entries, no tokens
  "dailyModelTokens": [ { "date": "2025-12-23", "tokensByModel": { "claude-opus-4-5-20251101": 42423 } } ],        // 125 entries
  "modelUsage": {                                   // lifetime cumulative, 9 models
    "claude-opus-4-7": {
      "inputTokens": 2296505, "outputTokens": 21599613,
      "cacheReadInputTokens": 2768119326, "cacheCreationInputTokens": 112801845,
      "webSearchRequests": 0, "costUSD": 0, "contextWindow": 0, "maxOutputTokens": 0
    }
  },
  "totalSessions": 793, "totalMessages": 91139,
  "longestSession": {...}, "firstSessionDate": "2025-12-23T03:38:24.486Z",
  "hourCounts": { "0": 5, "2": 1, ... }
}
```

The critical shape fact: **per-day and per-kind are mutually exclusive.**

- `dailyModelTokens` is per-day **and** per-model, but its value is a single scalar.
- `modelUsage` is per-model **and** per-kind (all four), but lifetime-cumulative with no day axis.

### That scalar is `input_tokens + output_tokens` only, with no dedup

Two independent proofs.

**Arithmetic.** Summing `dailyModelTokens` over all 125 days matches `modelUsage`'s
`inputTokens + outputTokens` exactly, for all nine models:

| model | Σ `dailyModelTokens` | `modelUsage` in+out | `modelUsage` all four kinds |
|---|---:|---:|---:|
| `claude-opus-4-7` | 23,896,118 | 23,896,118 | 2,904,817,289 |
| `claude-opus-4-8` | 13,907,258 | 13,907,258 | 1,440,256,135 |
| `claude-fable-5` | 5,276,587 | 5,276,587 | 580,109,989 |
| `claude-opus-4-6` | 4,867,174 | 4,867,174 | 1,373,980,131 |
| `claude-haiku-4-5-20251001` | 1,851,957 | 1,851,957 | 605,808,379 |
| `claude-sonnet-4-6` | 1,243,149 | 1,243,149 | 191,048,646 |
| `claude-sonnet-4-5-20250929` | 318,219 | 318,219 | 69,878,849 |
| `claude-opus-4-5-20251101` | 264,225 | 264,225 | 137,218,771 |
| `claude-sonnet-5` | 43,316 | 43,316 | 4,020,377 |

Cache read and cache write are excluded from the daily figure. Summed across all nine models the
daily scalar accounts for 51,668,003 of 7,307,138,566 lifetime tokens — **cache kinds are 99.3% of
the volume the cache's day axis throws away.**

**Code.** The builder is `jYo()` in the embedded JS bundle (byte offset ≈241,282,000 in
`versions/2.1.220`; recovered by locating the `tokensByModel` string):

```js
u[z].inputTokens            += q.input_tokens               || 0,
u[z].outputTokens           += q.output_tokens              || 0,
u[z].cacheReadInputTokens   += q.cache_read_input_tokens    || 0,
u[z].cacheCreationInputTokens += q.cache_creation_input_tokens || 0;
let V = (q.input_tokens || 0) + (q.output_tokens || 0);          // <-- daily value
if (V > 0) { let K = s.get(G) || {}; K[z] = (K[z] || 0) + V; s.set(G, K) }
```

There is no `seen`-id set anywhere in `jYo` — every assistant entry carrying `message.usage` is added.
`TranscriptTokenReader.swift:196-198` deliberately dedups by `message.id` because one API response
spans several transcript lines. On this corpus that difference is large: a full dedup'd scan of
`~/.claude/projects` counts 7,717 responses / 1.17 B tokens; the same scan without dedup counts
18,217 responses / 2.54 B tokens — **2.36× the responses, 2.17× the tokens.**

### The day keys are UTC; Tokens Today is local

`sPe(e) { return e.toISOString().split("T")[0] }` — the date key comes from `toISOString()`, i.e. UTC.
`TranscriptTokenReader.swift:92-97` pins its formatter to the **local** time zone on purpose. At
AEST+1000 a stats-cache day covers local 10:00 → 10:00 next day, so everything before 10 a.m. local
lands in the previous bucket.

### Direct cross-check against the transcripts

Rebuilding Claude Code's own algorithm from the raw transcripts (UTC key, drop `isSidechain` in
non-subagent files, skip model `<synthetic>`, value = in+out) reproduces the cache **byte-exactly** on
every day tested, which pins down all three behaviours at once:

| UTC day | in `stats-cache.json` | rebuilt: no dedup, in+out | rebuilt: dedup, all four kinds (≈ Tokens Today) |
|---|---:|---:|---:|
| 2026-07-12 | `fable-5: 22642, haiku-4-5: 750` | `fable-5: 22642, haiku-4-5: 750` ✅ | `fable-5: 1,027,541, haiku-4-5: 87,433` |
| 2026-07-13 | `fable-5: 1977019` | `fable-5: 1977019` ✅ | `fable-5: 106,393,684` |
| 2026-07-14 | `fable-5: 357342` | `fable-5: 357342` ✅ | `fable-5: 5,653,784` |

On 2026-07-14 the cache reports **6.3%** of the TokenStats figure — 15.8× low. Two errors compound in
opposite directions (missing cache kinds understates ~46×; missing dedup overstates ~2.9×) and do not
cancel. **A Tokens tab cannot mix a `dailyModelTokens` history with a live Tokens Today hero — the
two numbers are not on the same scale, and the discontinuity would land exactly at today's boundary.**

### It is not live, and its refresh is user-driven

`TFb()` (the "all" range) is the only path that touches the cache:

```js
let o = await eif();            // load cache
let i = tif();                  // YESTERDAY
if (!o.lastComputedDate) { ... await jYo(e, {toDate: i}) ... }        // cold: full historical scan
else if (z9t(o.lastComputedDate, i)) { ... jYo(e, {fromDate: vFb(o.lastComputedDate), toDate: i}) ... }
let r = i0a();                                  // TODAY
let n = await jYo(e, {fromDate: r, toDate: r}); // today is ALWAYS rescanned live
return SFb(t, n);                               // merge
```

`TFb` is reached from `qif() { return WYo("all") ... }`, which feeds the `allTimePromise` prop of the
Ink stats screen component. **Nothing refreshes the cache in the background** — it advances only when
the user opens Claude Code's stats UI. That is why `lastComputedDate` is 2026-07-17 while today is
2026-07-27. A TokenStats tab reading this file would be showing a snapshot of unbounded age, with no
signal of how old beyond `lastComputedDate` itself. The cache also never contains today (`tif()` caps
it at yesterday; today is always rescanned).

### The format is private scratch

- `V9t = 4` (current version), `X2b = 1` (minimum migratable), `Q2b = "stats-cache.json"` — all three
  read from the binary.
- The `.tmp` sibling `~/.claude/stats-cache.json.8349490a2f94338b.tmp` is a leftover atomic-write temp
  from **2026-01-27** and is `"version": 1`. **The schema went v1 → v4 in six months.**
- The v1 leftover covers 2025-11-18 → 2026-01-22; the live v4 file starts 2025-12-23. History earlier
  than that was dropped somewhere across those migrations.
- The loader `eif()` silently returns an empty cache on any structural surprise, and the empty-cache
  factory in 2.1.220 already emits a `shotDistribution` field that the on-disk v4 file does not have —
  the shape moves under `version: 4` itself.

**Cost if used anyway:** ~1 ms. It is 35 KB of JSON. The cost is not compute — it is that the numbers
mean something else, arrive late, and the format is explicitly unversioned scratch.

### Anything else under `~/.claude`?

Checked and ruled out:

- `~/.claude/history.jsonl` (1.1 MB) — prompt history. Keys are exactly
  `["display", "pastedContents", "project", "timestamp"]`. No tokens.
- `~/.claude/telemetry/` — `1p_failed_events.*.json`, undelivered analytics events awaiting retry.
- `~/.claude/cache/` — `changelog.md`, `my-closed-issues.json`.
- `~/.claude/projects/` is the transcript corpus itself (§4).

---

## 2. `~/.codex/` equivalents

**Verdict: no per-day or per-kind aggregate exists. One per-thread scalar does.**

### `~/.codex/state_5.sqlite` — `threads` table (19 MB)

The only Codex store holding token counts. Schema (`sqlite_master`):

```sql
CREATE TABLE threads (
    id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL,
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    ..., tokens_used INTEGER NOT NULL DEFAULT 0, ...
, ..., model TEXT, reasoning_effort TEXT, ...)
```

683 rows, `SUM(tokens_used)` = 2,315,751,472, spanning 2025-10-17 → 2026-07-25. Grouped by model:

| model | threads | Σ tokens_used |
|---|---:|---:|
| `gpt-5.6-sol` | 106 | 1,294,894,212 |
| `gpt-5.5` | 246 | 839,465,191 |
| `codex-auto-review` | 178 | 117,036,713 |
| `gpt-5.3-codex` | 24 | 18,344,794 |
| *(null)* | 92 | 11,599,025 |

What it does **not** give:

- **No token-kind breakdown.** One scalar. Codex has no cache-write concept (map #24), but even
  direct-input vs cache-read vs output cannot be recovered.
- **No day axis.** `created_at`/`updated_at` bound a thread; a thread spanning three days offers no
  way to split its total across them. `019f922c…` above ran 03:29 → 05:00 on one day, but the row
  carries no per-turn structure.
- **`model` is one label per thread.** The map already established that a Codex rollout mixes models
  across turns; this column can only name one. Note the DB does record `codex-auto-review` as its own
  thread row here, so review turns are at least separable at thread granularity.
- 88 of 683 rows have `tokens_used = 0`.

**Cost if used:** a single indexed SQL query, effectively free. The problem is that it answers a
different question — "how big was each conversation" — not "how many tokens of each kind on each day".

### `~/.codex/logs_2.sqlite` (499 MB) — not a source

One `logs` table (`id, ts, ts_nanos, level, target, feedback_log_body, module_path, file, line, …`).
Rolling debug log: 51,283 rows covering only **2026-07-17 → 2026-07-27** (10 days) in 499 MB.
`feedback_log_body LIKE '%token_count%'` matches 1,015 rows, but these are unstructured diagnostic
lines. Parsing 499 MB of debug text to recover 10 days is strictly worse than parsing the 421 MB of
rollouts that cover 84 days.

### Also checked and ruled out

- `~/.codex/session_index.jsonl` (21 KB, 156 lines) — `{id, thread_name, updated_at}` only.
- `~/.codex/.codex-global-state.json` (223 KB) — Electron UI state (sidebar widths, dismissed
  banners, prompt drafts). No usage data.
- `~/.codex/history.jsonl` (186 KB) — prompt history.
- `~/.codex/memories_1.sqlite`, `goals_1.sqlite`, `models_cache.json` — unrelated.

---

## 3. The OAuth endpoints the app already reaches

**Verdict: current Usage Windows only. No history, and per-model exists only as a quota percentage,
never as token counts.**

### Claude Code — `GET https://api.anthropic.com/api/oauth/usage`

`ClaudeCodeUsageProvider.swift:13` calls it with no query parameters. The call site in the shipped
binary confirms the client does the same (`fetchUtilization: GET /api/oauth/usage (attempt …)`, at
offset ≈87,433,286) — **no date, range, or history parameter anywhere in the request**.

The complete top-level key set the 2.1.220 client decodes (recovered from the schema table at offset
≈206,955,900) is:

```
five_hour · seven_day · seven_day_oauth_apps · seven_day_opus · seven_day_sonnet ·
cinder_cove · extra_usage · limits
```

Every entry is a `utilization`/`percent` (0–100) plus a `resets_at`, per
`docs/claude-code-integration.md` and `UsageSnapshotParser.swift`. `seven_day_opus`,
`seven_day_sonnet` and `limits[].scope.model` are **per-model**, but they carry a percentage of a
weekly quota — not a token count, and not attributable to a day. There is nothing token-denominated
in the response.

I enumerated every `/api/…` path string in the binary looking for an alternative. The only
usage-adjacent ones are not read APIs:

- `/api/claude_code/metrics` — an **OpenTelemetry exporter** sink (`class O3s { … async export(e, t)
  … ExportResultCode … }`), i.e. the client pushes org telemetry out. Not queryable.
- `/api/organization/claude_code_first_token_date` — returns one date (`"Received invalid
  first_token_date from API"`). Org onboarding metadata.
- `/api/rate-limits` — current limits, same family as above.

**Not established:** whether the Anthropic or OpenAI *web consoles* expose a historical usage export
behind a session the app does not hold. I did not make live authenticated calls and did not read the
user's Keychain tokens; the endpoint facts above are from the shipped client's own request and decode
paths.

### Codex — `GET https://chatgpt.com/backend-api/wham/usage`

`CodexUsageProvider.swift:15`, no query parameters. Payload per `docs/codex-integration.md`
(`RateLimitStatusPayload`, read from the OSS `codex-rs` source): `plan_type`,
`rate_limit.{primary,secondary}_window` (`used_percent`, `limit_window_seconds`, `reset_at`),
`credits`, `additional_rate_limits`, `rate_limit_reached_type`. All current-window percentages. No
history, no per-model split, no token counts.

**Cost:** one ~20 ms HTTPS GET each, already paid on every refresh. Zero marginal cost — and zero
marginal information for this question. This is consistent with ADR-0001: the endpoint is the
authority on *quota*, and it simply does not carry a *breakdown*.

---

## 4. What a real scan costs

Measured with a standalone Swift binary mirroring `TranscriptTokenReader`'s hot path exactly:
`FileManager.enumerator` + `contentModificationDate` pre-filter, 4 MB chunked `FileHandle` reads,
the `"input_tokens"` byte-marker line pre-filter, `JSONDecoder` with `.convertFromSnakeCase`, dedup
by `message.id`, bucketing by local day. Compiled `swiftc -O`. Timings are from a warm page cache
on this machine — I did not `purge`, so treat these as the steady-state figure a resident menu-bar
app would actually see, not a worst-case first-boot read.

### Corpus

| Root | Files | Bytes | Days of content | Layout |
|---|---:|---:|---:|---|
| `~/.claude/projects` | 311 | 178 MB | 25 | `<project>/<session>.jsonl` + `<session>/subagents/agent-*.jsonl` |
| `~/.codex/sessions` | 382 | 421 MB | 45 | **`YYYY/MM/DD/rollout-*.jsonl`** |
| `~/.codex/archived_sessions` | 301 | 540 MB | — | flat, `rollout-<ISO>-<uuid>.jsonl`; **not scanned today** |

### Timings

| Range | Root | Files matched | Skipped by mtime | Bytes read | Enumerate+stat | Parse | **Total** |
|---|---|---:|---:|---:|---:|---:|---:|
| today | claude | 39 | 272 | 38 MB | 9.5 ms | 415 ms | **425 ms** |
| 7d | claude | 74 | 237 | 64 MB | 8.4 ms | 622 ms | **630 ms** |
| 30d | claude | 305 | 6 | 178 MB | 9.1 ms | 1772 ms | **1781 ms** |
| all | claude | 311 | 0 | 178 MB | 25 ms | 1771 ms | **1796 ms** |
| 7d | codex | 18 | 364 | 35 MB | 6.1 ms | 254 ms | **260 ms** |
| 30d | codex | 165 | 217 | 298 MB | 6.6 ms | 2269 ms | **2276 ms** |
| all | codex | 382 | 0 | 421 MB | 6.8 ms | 3227 ms | **3234 ms** |

Repeat runs: claude/all 1796, 1836, 1736 ms; codex/all 3234, 3274, 3072 ms. Roughly ±5%.

**Both roots, full corpus: ~5.0 s, 600 MB read.** Both roots, 7d: **~0.9 s**. Both roots, 30d:
**~4.1 s**.

Throughput is ~100–130 MB/s of transcript, dominated by `JSONDecoder`. The mtime pre-filter is
essentially free (6–25 ms to enumerate and stat the whole tree) and prunes hard at short ranges.

### Two facts that bound what a scan can even answer

**Claude transcripts are pruned at ~30 days.** Oldest `.jsonl` mtime under `~/.claude/projects` is
2026-06-25 against a newest of 2026-07-27 — 32 days. `~/.claude/.last-cleanup` was touched today
(`2026-07-27T13:08:29.687Z`), and `cleanupPeriodDays` is a real settings key in 2.1.220 (the user has
not set it, so the default applies). This is why the 30d and "all" rows above are nearly identical:
**for Claude Code, a 30-day range already *is* the full corpus.** It also means `stats-cache.json`
holds history — back to 2025-12-23 — that no scan can ever reconstruct, because the transcripts it
was computed from are gone. If a range longer than ~30 days is ever wanted for Claude, the cache is
the only local source of it, warts and all.

**Codex is date-partitioned.** `~/.codex/sessions/YYYY/MM/DD/` means a date range can be pruned by
*directory path* before any `stat` — cheaper still than the mtime filter, and exact rather than
approximate (mtime is when the file was last appended, not when its entries happened). Codex retains
much more: the live tree spans 2026-05 → 2026-07 with entries on 45 distinct days (oldest file mtime
2026-05-05), plus a further 301 files / 540 MB in `archived_sessions` that TokenStats does not
currently scan. Whether archived rollouts belong in a Tokens total is an open question this ticket
does not answer.

### If an index is built instead

Sizing, not a recommendation. The full corpus yields 7,717 deduped Claude responses and 17,488 Codex
`token_count` events. Rolled up to (day × agent × model × kind) that is on the order of a few hundred
rows for the whole retained history — kilobytes. The build cost is exactly the ~5 s scan above, paid
once; incremental maintenance is what `TranscriptTokenReader` already does (remembered byte offset
per file, `TranscriptTokenReader.swift:67-77`). The genuinely new work is durability: ADR-0003
explicitly decided Tokens Today stays in-process and in-memory with no persistence, and its
"Negative" clause names the exact condition for reopening. Any index proposal contradicts ADR-0003 as
written and has to say so.

---

## Summary

| Source | Historical? | Per-model? | Per-kind? | Cost | Blocking problem |
|---|---|---|---|---|---|
| `~/.claude/stats-cache.json` `dailyModelTokens` | ✅ to 2025-12-23 | ✅ | ❌ in+out only | ~1 ms | Measures a different quantity (~16× off Tokens Today); UTC days; no dedup; refreshes only when the user opens Claude Code's stats UI (10 days stale here); v1→v4 in six months |
| `~/.claude/stats-cache.json` `modelUsage` | ❌ lifetime total | ✅ | ✅ | ~1 ms | No day axis at all |
| `~/.codex/state_5.sqlite` `threads` | ✅ to 2025-10-17 | ~ one label per thread | ❌ | ~1 ms | One scalar per thread; threads span days; no kind split |
| `~/.codex/logs_2.sqlite` | ❌ 10-day window | ❌ | ❌ | 499 MB of debug text | Not an aggregate |
| Claude `oauth/usage` | ❌ | quota % only | ❌ | ~20 ms (already paid) | Current Usage Windows only; no token counts |
| Codex `wham/usage` | ❌ | ❌ | ❌ | ~20 ms (already paid) | Current Usage Windows only; no token counts |
| Scan `~/.claude/projects` | ≤ ~30 days (pruned) | ✅ | ✅ | 0.43 s today · 0.63 s 7d · 1.8 s 30d/all | 30d ≈ full corpus; nothing older survives |
| Scan `~/.codex/sessions` | ✅ 45 days of entries, 2026-05 → now | ❌ needs `turn_context` correlation (map #24) | ✅ (no cache-write) | 0.26 s 7d · 2.3 s 30d · 3.2 s all | Model attribution is a separate problem |

### What I could not establish

- Whether Anthropic or OpenAI expose historical usage through any surface **other** than the client
  endpoints — a web console export, an admin/org API. I read what the shipped clients request and
  decode; I did not make live authenticated calls, and did not touch the user's stored tokens.
- Whether `cleanupPeriodDays` has always been ~30 on this machine, or whether the older Claude
  history in `stats-cache.json` reflects a period with different retention.
- Cold-cache (post-reboot) scan timings — `purge` needs sudo. The figures above are warm-cache
  steady state.
- Why the live v4 cache starts 2025-12-23 when the abandoned v1 temp reaches back to 2025-11-18. A
  migration dropped it, but I did not recover the v1→v4 migration path to say which step.
