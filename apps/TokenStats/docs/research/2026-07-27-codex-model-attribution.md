# Can every Codex `token_count` event be attributed to a model?

Research note for issue [#26](https://github.com/zhangchi0104/agent-sessions/issues/26) (part of [#24](https://github.com/zhangchi0104/agent-sessions/issues/24)).

**Answer: not every one, but 98.64% of them — and the cheap rule is as accurate as the expensive one.**
A "most recent preceding model wins" scan attributes 17,250 of 17,488 usage-bearing
`token_count` events (98.6391%), covering 98.6302% of the tokens the reader actually sums.
It never disagrees with an exact `turn_id` join — 0 disagreements in 17,230 events where both
rules produce an answer. Every one of the 238 failures sits in **3 files out of 382**, all of them
multi-agent sub-agent rollouts, in the run of events before the file's first `turn_context`.

The catch is in `TranscriptTokenReader`: the model **cannot** be derived on demand and **must** be
persisted in `ParseState` next to `consumedBytes`. Worse, the reader's `usageMarker` pre-filter
discards 100% of model-bearing lines before they are ever decoded, so this is not a free addition.

---

## Sources

Everything below was measured against the local rollout corpus, not inferred from documentation:

- **`~/.codex/sessions/`** — 382 `.jsonl` files, 101,878 lines, 421,177,012 bytes,
  spanning `2026/05/05` to `2026/07/25`. Codex CLI versions `0.128.0` through `0.144.5`;
  originators `codex-tui`, `Codex Desktop`; sources `vscode` (316), `subagent` (211),
  `cli` (80), `exec` (10).
- **`apps/TokenStats/TokenStats/Tokens/TranscriptTokenReader.swift`** at `698e6ea`.
- **`~/.claude/projects/`** — 311 transcripts, used only to re-confirm the Claude-side premise.

Throwaway Python scripts were run against the real files; every number below is a count that was
actually measured. Percentages of `token_count` events are always over the **17,488 usage-bearing**
events, not the 17,555 total (see §1).

---

## 1. What actually carries what

Across the whole corpus, exactly two line kinds carry a model:

| Line | Model path | Count |
| --- | --- | --- |
| `{"type":"turn_context","payload":{…}}` | `payload.model` | 2,632 |
| `{"type":"event_msg","payload":{"type":"thread_settings_applied",…}}` | `payload.thread_settings.model` | 1,257 |

No other line kind has a `model` field anywhere. `session_meta` carries only
`model_provider` (`"openai"` in all 617 occurrences) — **not** a model name.

`token_count` events have a completely fixed shape. Their top-level keys are always
`("payload","timestamp","type")` and their payload keys are always `("info","rate_limits","type")`
— all 17,555 of them.

> **There is no `turn_id` on a `token_count` event.** The ticket asks to check `turn_id`
> correlation "if `token_count` events carry one". They do not — not at the top level, not in
> `payload`, not in `info`. Correlation has to be positional.

Two sub-populations matter:

- **17,488** events carry `info` as an object → real usage.
- **67** events carry `info: null` → rate-limit-only heartbeats, no usage at all. These are
  already invisible to the reader (see §5) and are excluded from every rate below.

`info` is always `("last_token_usage","model_context_window","total_token_usage")`.
Both usage objects have one of two key sets:

```
("cached_input_tokens","input_tokens","output_tokens","reasoning_output_tokens","total_tokens")                              — 14,066
("cache_write_input_tokens","cached_input_tokens","input_tokens","output_tokens","reasoning_output_tokens","total_tokens")   —  3,422
```

Five distinct models appear: `codex-auto-review` (1,790 `turn_context`s), `gpt-5.5` (407),
`gpt-5.6-sol` (404), `gpt-5.6-terra` (20), `gpt-5.6-luna` (11).

---

## 2. The ordering invariant

**Established: `turn_context` always precedes the `token_count` events of the turn it describes —
but it does *not* precede `task_started`.**

The real per-turn order, contrary to what the name suggests, is:

```
L297   event_msg/task_started   turn_id=019df598-7efb-73a2-a85c-4272875b9d67
L298   turn_context             turn_id=019df598-7efb-73a2-a85c-4272875b9d67  model="gpt-5.5"
L301   event_msg/token_count    last_token_usage={…}
L309   event_msg/token_count    last_token_usage={…}
  …
       event_msg/task_complete  turn_id=019df598-7efb-73a2-a85c-4272875b9d67
```
<sup>`~/.codex/sessions/2026/05/05/rollout-2026-05-05T10-39-14-019df593-25e2-7cd1-808e-bc8e397f7b0d.jsonl`</sup>

Evidence:

- Reducing each file to its `turn_context`/`task_started` markers, the dominant patterns are
  `SCSCSCSC` (132 files), `SC` (112), `SCSC` (80), `SCSCSC` (21) — **`S` before `C`, always
  alternating.** Measured directly: **0 of 382 files** open with a `turn_context` rather than a
  `task_started`.
- `turn_context` and `task_started` **do share a `turn_id` namespace**: 2,567 ids appear on both,
  across 377 of 382 files. (An earlier "0 matches" reading was an artefact of only looking
  backwards from `task_started`.)
- `turn_context` carries `turn_id` on **all 2,632** occurrences — 0 missing.
- 17,241 of 17,488 usage events (98.5876%) fall inside a `task_started … task_complete` window.

**Invariants established**

| # | Invariant | Evidence |
| --- | --- | --- |
| I1 | Every `turn_context` carries a `turn_id`. | 2,632 / 2,632, 0 missing |
| I2 | A `token_count` never carries a `turn_id`. | 17,555 / 17,555 payload key sets identical |
| I3 | Within a turn, `turn_context` precedes every `token_count` of that turn. | 17,230 events joined exactly by `turn_id`; 11 in-turn exceptions (§4) |
| I4 | A file's model set does not change under resume. | 106 carried-model checks after a mid-file `session_meta`: 106 same, **0 different** |
| I5 | A file's model set does not change under compaction. | 42 carried-model checks after `compacted`/`context_compacted`: 42 same, **0 different** |
| I6 | The cheap rule never contradicts the exact rule. | **0** disagreements / 17,230 events where both answer |

**Invariant disproved**

| # | Claim | Finding |
| --- | --- | --- |
| D1 | "One session mixes models — `gpt-5.6-sol` on work turns, `codex-auto-review` on review turns." (map #24) | True of a *session tree*, **false of a rollout file**. See §6. |

`turn_id` is not unique within a file: 65 `turn_context` lines repeat a `turn_id` already seen in
the same file. Re-emission is benign here (the model repeats too), but a `turn_id → model` map must
tolerate overwrite rather than assert uniqueness.

---

## 3. The attribution rate

Two rules were run over all 17,488 usage-bearing events.

**Rule A — exact.** Join each `token_count` to the enclosing `task_started`'s `turn_id`, then to the
`turn_context` that declared that `turn_id`.

**Rule B — heuristic.** Most recent preceding model wins, from either carrier
(`turn_context.payload.model` or `thread_settings_applied.payload.thread_settings.model`).

| | Rule A (exact) | Rule B (most recent wins) |
| --- | --- | --- |
| Attributed | 17,230 (**98.5247%**) | 17,250 (**98.6391%**) |
| Unattributable | 258 | 238 |
| — inside a turn, no `turn_context` for that `turn_id` | 11 | — |
| — outside any turn window | 247 | — |

**Rule B is both cheaper and strictly more complete**, and the two never conflict:
**0 disagreements**. Rule B recovers 20 events Rule A drops — the 9 out-of-turn events where a model
was still carried, plus the 11 in-turn events whose own `turn_context` was missing.

By tokens, using exactly what the reader sums (`input_tokens + output_tokens`, since it splits
`cached_input_tokens` back out of `input_tokens`):

```
attributed     1,847,173,254   98.630239%
unattributed      25,653,255    1.369761%
total          1,872,826,509
```

Using `last_token_usage.total_tokens` instead gives 98.627804% — the same answer to three decimals.

**Failure rate: 1.36% of events, 1.37% of tokens.**

---

## 4. What the failures look like

All 238 unattributable events live in **3 files**. Not a long tail — a cliff.

| File (under `~/.codex/sessions/`) | Unattributed | First model line | Sub-agent nickname / `agent_path` |
| --- | --- | --- | --- |
| `2026/07/13/rollout-2026-07-13T20-39-15-019f5b0f-….jsonl` | 103 / 186 | L170 `thread_settings_applied` | `Carver` / `/root/offline_3d_harness` |
| `2026/07/16/rollout-2026-07-16T21-19-48-019f6aa7-….jsonl` | 8 / 24 | L22 `turn_context` | `Kepler` / `/root/adb_baseline` |
| `2026/07/16/rollout-2026-07-16T21-51-30-019f6ac4-….jsonl` | 127 / 167 | L357 `turn_context` | `Newton` / `/root/source_review` |

All three are `session_meta.source = {"subagent":{"thread_spawn":{…}}}` at `depth: 1` with
`thread_source: "subagent"` and `multi_agent_version: "v2"`, from `Codex Desktop` `0.144.x`.
`Kepler` and `Newton` share the parent thread `019f6aa6-adb8-7ca1-924d-48f80ac917e9`; `Carver`'s
parent is `019f5aea-0338-7373-8d08-5d671e0e61aa`.

`Carver`'s file also embeds its **parent's** `session_meta` at L174
(`{"id":"019f5aea-0338-…","source":"vscode","thread_source":"user"}`) — a child rollout can contain
a second `session_meta` describing the thread that spawned it, so "the file's `session_meta`" is not
a single well-defined thing.

The literal shape of the failure — a sub-agent streams usage *before* it declares a turn:

```
L1    session_meta   source={"subagent":{"thread_spawn":{"parent_thread_id":"019f6aa6-…",
                              "depth":1,"agent_path":"/root/adb_baseline","agent_nickname":"Kepler"}}}
                     thread_source="subagent"  multi_agent_version="v2"
L6    token_count    last={"input_tokens":23960,"cached_input_tokens":9984,"output_tokens":575,…}   ← orphan
L7    token_count    last={"input_tokens":24579,…}                                                  ← orphan
  …   (L8, L9, L10, L11, L13, L15 — 8 orphans in total)
L16   task_started   turn_id=019f6aa7-7da3-7722-8033-86c878d33c21
L22   turn_context   model="gpt-5.6-sol"  turn_id=019f6aa7-7da3-7722-8033-86c878d33c21
L30   token_count    last={…}                                                                       ← attributable
```
<sup>`~/.codex/sessions/2026/07/16/rollout-2026-07-16T21-19-48-019f6aa7-7849-7993-a7ce-53ceab6e38e8.jsonl`</sup>

**Characterisation:** unattributable events are **always a leading prefix of the file**, never a
gap in the middle and never a consequence of resume or compaction. Once a file declares its first
model, nothing later in that file is unattributable. This follows from I4/I5: in 148 checks across
resumes and compactions, the carried model was never contradicted.

Worth recording for the follow-up ticket that decides what happens to these tokens: in all 3 files
the model **is** eventually declared, and each file only ever uses one model, so the orphans are
recoverable by backfill. Whether to backfill, bucket as unknown, or drop is **not decided here.**

Separately, 5 files contain no model-bearing line at all — but none of them contains a usage-bearing
`token_count`, so they cost nothing.

---

## 5. Does the model survive `TranscriptTokenReader`'s lifecycle?

**The model must be persisted in `ParseState` alongside `consumedBytes`. It cannot be derived on
demand.** And before any of that matters, the pre-filter has to change.

### 5a. The pre-filter discards every model-bearing line

`parse(line:into:)` opens with:

```swift
guard line.range(of: Self.usageMarker) != nil else { return }
```

with `usageMarker = Data("\"input_tokens\"".utf8)`. Measured against the corpus:

| Line kind | Contains `"input_tokens"` |
| --- | --- |
| `turn_context` | **0 of 2,632** |
| `thread_settings_applied` | **0 of 1,257** |
| `token_count` with `info` | 17,488 of 17,488 |
| `token_count` with `info: null` | 0 of 67 |

So today the reader never even decodes a line that could tell it the model. This is a real change to
the hot path, not a decoder-only tweak. Costs, measured over 101,878 lines:

| Candidate marker | Lines admitted | Share | False positives |
| --- | --- | --- | --- |
| `"input_tokens"` (current) | 17,488 | 17.166% | none |
| `"turn_context"` | 2,632 | 2.583% | none |
| `"thread_settings"` | 1,257 | 1.234% | none |
| `"model"` | 4,241 | 4.163% | 347 `session_meta`, 5 `tool_search_output` |

`"turn_context"` and `"thread_settings"` are exact — they admit precisely the lines wanted and
nothing else. Adding both widens the filter by 3,889 lines (+3.817% of corpus lines, a ~22%
increase over the 17,488 lines already decoded). `"model"` is the worse choice: it admits 352
useless lines, and `session_meta` lines are among the largest in the corpus (they embed
`base_instructions`).

The 67 `info: null` heartbeats are already free — none contains the marker.

### 5b. Chunk boundaries and `partialLine` — safe

`ingest` prepends `state.partialLine`, splits on `0x0A`, and hands only complete lines to
`parse`; the tail becomes the new `partialLine`. Lines are therefore parsed exactly once, in file
order, regardless of where a 4 MiB chunk boundary falls. A model assigned inside `parse` is safe
across chunk boundaries with no extra work.

Line sizes are near the limit but do not break this: the longest line in the corpus is
**3,793,467 bytes** (a `response_item/custom_tool_call_output`) against `chunkSize` of 4,194,304 —
and even an over-sized line would be handled, since `partialLine` simply keeps accumulating until a
newline arrives.

### 5c. Resuming a file across polls — **this is where it breaks**

`usage(forTranscriptAt:)` seeks to `state.consumedBytes` and reads only what was appended. A
`turn_context` consumed by an earlier poll is **never re-read**. If the model lived only in a local
variable, every poll after the first would begin with no model and mis-attribute until the next
`turn_context` arrived.

This is not a corner case. There are 17,488 usage events against 2,576 turns — a mean of **6.8
`token_count` events per turn**, with the largest single turn window holding **156**. Since
`TokensTodayModel` is FSEvents-driven, polls routinely land mid-turn, exactly where the model would
be unknown.

**→ `ParseState` needs a `currentModel: String?` field, updated in `parse` and read in `record`.**
Because `record` is where the per-day bucket is written, the model has to be resolved at that
moment; it cannot be applied afterwards.

### 5d. The reset paths — all self-healing, no persistence needed beyond the field

Every path that discards state discards it **whole**, and all of them re-read from byte 0:

- **File shrank** — `if size < state.consumedBytes { state = ParseState() }` resets `consumedBytes`
  to 0 along with everything else, so the file is re-parsed from the top and the first
  `turn_context` is seen again.
- **48-hour `evictStaleStates`** — `states.filter { $0.value.lastAccessed > cutoff }` drops the
  entry entirely; the next call builds a fresh `ParseState` from offset 0.
- **Missing file** — `states[path] = nil`, same effect.

So the model needs no on-disk persistence and no separate cache. It only needs to live in
`ParseState`, so that it is dropped *together with* `consumedBytes` and never *without* it.

**The one rule a future change must not break:** never evict or clear part of a `ParseState` while
keeping `consumedBytes`. If, say, `seenResponseIDs` were ever cleared to reclaim memory while
parsing continued from the same offset, `currentModel` would have to be explicitly exempted.

There is no cross-format hazard: state is per file, and a file is either a Claude transcript or a
Codex rollout. Claude lines carry `message.model` inline, so a `currentModel` field is simply never
read on that path.

---

## 6. Corrections and incidental findings

**D1 — models do not mix within a rollout file.** Measured per-file distinct model counts:

```
0 distinct models :   5 files
1 distinct model  : 376 files
2 distinct models :   1 file   (gpt-5.6-luna → gpt-5.6-sol, via thread_settings_applied)
```
<sup>the one mixed file: `2026/07/11/rollout-2026-07-11T08-22-18-019f4e1f-dbd9-78a2-96ad-c93bee36e8dd.jsonl`</sup>

Per-file model sets: `codex-auto-review` alone in 151 files, `gpt-5.5` alone in 121,
`gpt-5.6-sol` alone in 99. **`codex-auto-review` gets its own rollout file** — all 151 such files
have `session_meta.source = {"subagent": …}` (138 also `thread_source: "subagent"`), e.g.
`{"subagent":{"other":"guardian"}}`.

The map's premise holds for a *session* in the user's sense — a work thread and its review threads
belong together — but a per-file parser like `TranscriptTokenReader` sees them as separate files
with one model each. Only **1 file in 382** ever needs to switch model mid-parse. The model state of
§5 is therefore mostly a correctness guard for that one case plus the sub-agent prefixes, not a
frequently-exercised path.

**`cache_write_input_tokens` exists but is always zero.** The field appears in 3,422 of 17,488
usage objects (newer CLI versions). Non-zero occurrences: **0**. Sum: **0**. The map's "Codex has
no cache-write concept, a cache-write column is Claude-only" is confirmed — but note the field is
now *present* in the schema, so a decoder must not treat its presence as evidence of the feature.

**Claude-side premise re-confirmed.** Across 311 transcripts under `~/.claude/projects`, 18,183
lines carry `message.usage`, and **18,183 of them (100.0000%)** also carry `message.model` on the
same line.

### Out of scope, but found while measuring — worth their own tickets

These are recorded, not resolved. Neither is a model-attribution question.

1. **~2.57% of `token_count` events duplicate their immediate predecessor.** 450 of 17,488 events
   repeat the previous event's `last_token_usage` field-for-field. They cluster at turn boundaries
   — a new turn re-emits the previous turn's final usage. Since the reader sums every event, these
   are double-counted. Consistent with this, `sum(last_token_usage.input_tokens)` divided by the
   file's final `total_token_usage.input_tokens` rounds to 1 for 357 files but to **2 for 15
   files**, with individual ratios up to 1.62. The reader's source comment — "their sum equals the
   session's cumulative total" — is approximately right, not exact.

2. **93 events report `total_tokens > 0` with every component field at 0.** e.g.
   `{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":21079}`
   in `2026/05/28/rollout-2026-05-28T11-31-18-019e6c35-….jsonl`. 65 of the 93 immediately follow a
   `turn_context`; the rest follow `turn_aborted` (8), `compacted` (8) or `context_compacted` (8).
   The reader sums components, so it scores these as 0 — about 2.88M tokens corpus-wide (~0.15%)
   that are visible in `total_tokens` but invisible to the reader.

---

## 7. `reasoning_output_tokens` is a **subset** of `output_tokens`

Not additive. Three independent measurements over all 17,488 usage objects agree:

| Check | Result |
| --- | --- |
| `reasoning_output_tokens <= output_tokens` | 17,488 / 17,488 — **0 violations** |
| `reasoning_output_tokens > output_tokens` | **0** |
| `total_tokens == input_tokens + output_tokens` | 17,395 (99.4682%) |
| `total_tokens == input_tokens + output_tokens + reasoning_output_tokens` | 2,202 (12.5915%) |

The second identity only ever holds where `reasoning_output_tokens == 0` (2,295 events), i.e. where
the two formulas coincide. The 93 residuals against the first identity are exactly the zeroed-component
events of §6. `cached_input_tokens <= input_tokens` also holds in 17,488 / 17,488 — 0 violations,
confirming the reader's existing `max(input - cached, 0)` split.

**Consequence for a per-model table:** adding `reasoning_output_tokens` to `output_tokens` would
double-count. It can only ever be shown as a *disclosure within* output — "of which reasoning" —
which is what the reader's current silence already implies is safe.

---

## What could not be established

- **Whether these invariants hold for Codex versions outside `0.128.0`–`0.144.5`.** The corpus is
  one machine, one user, an 81-day span. `turn_context` payload key sets already vary across 15+ shapes in
  that window, so the format is actively moving. The `token_count` payload shape, by contrast, was
  identical across all 17,555 events — that one looks stable.
- **Whether a sub-agent's orphan prefix can carry a model different from the one its file later
  declares.** In all 3 observed files only one model is ever used, so a backfill would be correct
  here — but 3 files is not enough to call it an invariant, and no counter-example exists locally
  to test against.
- **Why the 3 failing files emit usage before their first `turn_context`, while the other 207
  sub-agent-sourced files do not.** All 3 are `multi_agent_version: "v2"` from `Codex Desktop`
  `0.144.x`, but so are files that attribute cleanly. The trigger was not isolated.
- **Whether `codex-auto-review` sub-agent files are reachable from their parent.** The
  `guardian`-sourced review files carry `parent_thread_id: null`, so a review file cannot be linked
  back to the work thread it reviewed by any field observed here. This matters only if the Tokens
  tab ever wants to group a thread tree; it does not affect per-model attribution.
- **No first-party Codex documentation or source was consulted.** Every statement here is an
  observation of local artefacts. Where the two could differ — e.g. whether `total_tokens` is
  *defined* to exclude reasoning or merely happens to — only the observation is claimed.
