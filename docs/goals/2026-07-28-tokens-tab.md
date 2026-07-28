# Goal spec: the TokenStats popover has a Tokens tab breaking consumption down by Coding Agent, Model and Token Kind

Execution target for an autonomous run on branch `feat/token-stats-tab`.
Working directory: `/Users/alexzhang/code/github.com/zhangchi0104/agent-sessions`.
This file is the run's own instructions — do not delete or rewrite it during the run.

## 1. Goal

**The popover carries two tabs, `Usage | Tokens`; the Tokens tab reports the Token Odometer for a selected range as a table grouped by Coding Agent then Model, with the four Token Kinds per row; and the Codex figures behind it are correct for the first time.**

The run is complete when every assertion in §2 holds simultaneously.

## 2. Success criteria

Run from the repository root. Every criterion below **fails on the untouched tree** except where noted, and each was executed before this file was written.

| # | Command | Passing result |
|---|---|---|
| S1 | `rg -q 'case tokens' apps/TokenStats/TokenStats --glob '*.swift'` | exit 0 — a `PopoverTab` case for the Tokens tab exists |
| S2 | `test -f apps/TokenStats/TokenStats/GlassTabBar.swift` | exit 0 — the tab bar is back |
| S3 | `! test -e apps/TokenStats/TokenStats/Tokens/TokensTodayHero.swift` | exit 0 — the hero is deleted, not moved |
| S4 | `! rg -qi 'tokens today' apps/TokenStats/TokenStats --glob '*.swift'` | exit 0 — the retired term appears in no Swift source. **8 sites today**, listed in §8 |
| S5 | `rg -q 'totalTokenUsage' apps/TokenStats/TokenStats/Tokens/TranscriptTokenReader.swift` | exit 0 — the reader decodes the running total it now derives from |
| S6 | `rg -q 'turn_context' apps/TokenStats/TokenStats/Tokens/TranscriptTokenReader.swift` | exit 0 — the pre-filter admits model-bearing Codex lines |
| S7 | `! rg -q 'sum equals the session' apps/TokenStats/TokenStats/Tokens/TranscriptTokenReader.swift` | exit 0 — the false claim at line 210 is gone |
| S8 | `rg -q 'token_count' apps/TokenStats/TokenStatsTests --glob '*.swift'` | exit 0 — Codex fixtures exist under test. **Zero today**: every fixture is a Claude usage line |
| S9 | `rg -q -e selectedRange -e 'enum TokenRange' -e 'case sevenDays' apps/TokenStats/TokenStats --glob '*.swift'` | exit 0 — the model carries a selected range |
| S10 | **Manual.** `cd apps/TokenStats && npm run dev`, open the popover, select each range | A human confirms the Tokens tab matches the prototype in §8: no grand total, swatch and coloured label per header, a proportion bar under each row, and a Codex row showing a missing cache-write segment. **Run last.** |

## 3. Invariants

These hold after **every** milestone, not only at the end.

| # | Command | Passing result |
|---|---|---|
| I1 | `cd apps/TokenStats && npm test` | `** TEST SUCCEEDED **`. Baseline before any work: **88 tests in 14 suites** |
| I2 | `git status --porcelain` | Every changed path is under `apps/TokenStats/` or `docs/goals/`. `?? .claude/` is pre-existing and stays untracked |
| I3 | `rg -q 'Token Odometer' apps/TokenStats/CONTEXT.md` | exit 0 — the glossary landed in `285ec13` and must not be reverted |
| I4 | `! rg -q -e UserDefaults -e SQLite -e CoreData -e GRDB apps/TokenStats/TokenStats/Tokens` | exit 0 — ADR-0003 holds: the odometer stays in-process and in-memory, with no persistence added. **Written with `-e` rather than `\|` alternation on purpose: the escaped form matches nothing and would pass forever** |

## 4. Milestones

Each is one commit on `feat/token-stats-tab`, revertible on its own.

### M0 — Codex token counting becomes exact

**Goal.** The reader stops double-counting Codex, independently of any UI work. This is a live defect in the shipped figure and can land alone.

1. Add Codex fixture builders to the test target: a `turn_context` line and a `token_count` line carrying a running `total_token_usage`. `TokensTodayWatchTests` already has the temp-directory and change-source apparatus to reuse.
2. Write the failing test first: two identical consecutive `token_count` events contribute the tokens of one.
3. Decode `total_token_usage` alongside `last_token_usage` in the Codex rollout line.
4. Carry the previous per-component total in `ParseState` and derive each event's contribution from the delta. Keep the existing non-negative guard when subtracting cached from input.
5. Correct the reader's header comment: the per-event deltas do **not** sum to the session total.

**Expected breakage:** none. Existing tests only cover Claude transcripts.

**Exit gate:** S5, S7, S8 pass; all invariants pass; `git show --stat HEAD` names only files under `apps/TokenStats/TokenStats/Tokens/` and `apps/TokenStats/TokenStatsTests/Tokens/`.

### M1 — Codex tokens are attributed to a Model

**Goal.** Every Codex figure carries the Model that produced it, and the per-file aggregate is keyed by day and model.

1. Widen the reader's pre-filter so `turn_context` and `thread_settings_applied` lines reach the decoder. It matches **zero** of them today, so no model is ever decoded.
2. Carry the current model in `ParseState` beside `consumedBytes`; attribute each `token_count` to the most recent preceding model.
3. Accumulate usage seen before a file's first model into a bounded pending bucket; flush it into that model when it first appears. A file that never declares one keeps its usage under `unknown`.
4. Re-key the per-file day bucket by day **and** model.
5. Publish a per-agent, per-model breakdown from the model, summed over the day keys in range.

**Exit gate:** S6 passes; all invariants pass; new tests assert attribution, backfill, and the `unknown` fallback.

### M2 — the Tokens tab exists and the hero is gone

**Goal.** The popover has two tabs; the combined figure is deleted; the retired term is out of the Swift sources.

1. Recover the tab bar: `git show 12e584f^:apps/TokenStats/TokenStats/GlassTabBar.swift > apps/TokenStats/TokenStats/GlassTabBar.swift` (85 lines), then rename the `sessions` case to `tokens` and its label. **Keep the `#available(macOS 26.0, *)` fallback** — the deployment target is 14.6.
2. Delete `TokensTodayHero.swift` and its single call site in `PopoverView`.
3. Delete `TokenUsage.breakdownDescription` and `TokenUsage.compactTotal`; the hero was their only consumer. Keep `TokenUsage.compact`, which the table uses.
4. Rename `TokensTodayModel` across the four files listed in §8, and its file.
5. Retire the term from Swift sources — including the **user-visible onboarding copy** at `OnboardingDisclosureStep.swift:26`, which is a deliberate copy change, not an incidental sweep.

**Exit gate:** S1, S2, S3, S4 pass; all invariants pass; `rg -q 'available(macOS 26' apps/TokenStats/TokenStats/GlassTabBar.swift` exits 0.

### M3 — the breakdown table and its range control

**Goal.** The Tokens tab renders the table and switches ranges.

1. Add the range to the model as state, defaulting to Today and not persisted.
2. Publish the in-flight state — which range is pending, and which range the displayed rows belong to — so the view binds rather than computes.
3. Build the table: agent group headers with subtotals, model rows with four Token Kinds in compact units, a proportion bar beneath each row, swatch and coloured label per column header, header tooltips carrying the full names.
4. Render an agent group with no usage in range as a worded line, distinct from the scanning state.

**Exit gate:** S9 passes; all invariants pass; S10 is handed to a human.

## 5. Decision rules

- **D1** — A new `.swift` file needs no `project.pbxproj` edit. The target uses `PBXFileSystemSynchronizedRootGroup` (5 occurrences); files are picked up by path. Do not hand-edit the project file.
- **D2** — `npm test` runs from `apps/TokenStats`, never the repository root. There is no root-level test script.
- **D3** — Where the recovered `GlassTabBar` needs cosmetic adjustment to seat two tabs, adjust it. Do not rewrite it from scratch; its Liquid Glass and fallback paths are both load-bearing.
- **D4** — Where a test needs a Codex rollout shape not yet in the fixtures, add the builder rather than reading a real file from `~/.codex`. Tests must not touch the developer's own transcripts.
- **D5** — Where the term "Tokens Today" appears in a comment, rewrite the comment to the glossary term rather than deleting the sentence.
- **D6** — `reasoning_output_tokens` is a subset of `output_tokens`. Do not add it separately to any total.

## 6. Stop conditions

- **H1** — `npm test` fails on the untouched tree before any work begins. The baseline is 88 tests in 14 suites passing; a red baseline means the environment differs from the one this file was written against.
- **H2** — `git show 12e584f^:apps/TokenStats/TokenStats/GlassTabBar.swift` does not resolve. M2 depends on recovering it; history rewriting invalidates the plan.
- **H3** — A ninth site for the retired term appears that is neither in §8's list nor a file this run created. The list is closed; a surprise site means the sweep is larger than scoped.
- **H4** — Deriving from `total_token_usage` deltas makes any existing test fail. The measurement behind M0 says the running total never decreases across 372 rollouts; a failure means the assumption does not hold for the fixture shapes in use.
- **H5** — The popover cannot seat the table within roughly 600pt at the 30-day range. The prototype measured 539pt for 11 model rows, but in HTML rather than SwiftUI; a large miss means the layout needs redesigning, not squeezing.

## 7. Non-goals

- Cost or pricing in any form. Most tokens are on Codex model names with no public price.
- Project as a grouping axis.
- Trend charts, sparklines, export, copy or share.
- Reading `~/.codex/archived_sessions`.
- Any range longer than 30 days.
- A persistent index, database, watcher daemon or IPC surface. ADR-0003 stands.
- Touching the Usage tab's gauges, the Settings window, or onboarding beyond the single copy line in M2 step 5.
- Reformatting files the plan does not otherwise change.

## 8. Context the run needs

**Tree state at the time of writing.** Branch `feat/token-stats-tab`, tracking `origin`. `git status --porcelain` shows exactly `?? .claude/`, which is pre-existing agent scratch and must stay untracked.

**Toolchain.** Xcode 26.6 locally. CI (`.github/workflows/test-tokenstats.yml`) runs on `macos-15` and selects an Xcode 26 explicitly, because the project is objectVersion 77 and the runner default cannot read it. CI runs the same `npm test`.

**The retired term's 8 Swift sites** — this list is closed, and a ninth is stop condition H3:
`Onboarding/OnboardingDisclosureStep.swift:26` (user-visible copy), `Tokens/TranscriptChangeSource.swift:5`, `Tokens/TokensTodayHero.swift:42`, `Tokens/TokensTodayModel.swift:5`, `App/TokenStatsApp.swift:68`, `App/PopoverView.swift:5`, `Agents/CodingAgentIntegration.swift:73`, `Agents/CodingAgentRegistry.swift:31`.

**Consumers, enumerated.** `TokensTodayModel` is referenced in exactly four files: `App/TokenStatsApp.swift`, `App/PopoverView.swift`, `TokenStatsTests/Tokens/TokensTodayWatchTests.swift`, and a comment in `Tokens/TranscriptChangeSource.swift`. `TokensTodayHero` has one call site, `App/PopoverView.swift`. `breakdownDescription` and `compactTotal` have one consumer between them, `TokensTodayHero`.

**Docs that are already right.** `apps/TokenStats/CONTEXT.md` carries **Token Odometer**, **Model** and **Token Kind**; use that vocabulary in code, comments and commit messages. `Tokens Today` is retired — it is not a synonym.

**Design record.** The ten resolution comments on map issue #24, and the spec at issue #36. The layout prototype is committed at `apps/TokenStats/prototypes/2026-07-28-tokens-tab-layouts.html` — a design record, not production code, and its pixel figures are indicative: the same page measured 443pt and 484pt in two browsers.

**Research notes** under `apps/TokenStats/docs/research/` document the vendor formats this depends on. They are observations of local artefacts with no first-party documentation behind them.

**Obsolete history not to consult.** Map issue #12 and its tickets were closed as obsolete when session tracking was deleted; the Sessions tab, hook CLI and all TypeScript are gone. Do not resurrect them.

**Commit convention.** `type(TokenStats): subject` — `feat`, `fix`, `docs`, `refactor`, `test`. semantic-release reads these. Each commit ends with the `Co-Authored-By` trailer this repo already uses.
