# Tokens Today stays an in-process estimate, not a shared-DB figure

The **Token Odometer** is computed **in-process inside TokenStats** from local
transcript files. Its shared raw total is the sum of the four disjoint Token
Kinds: direct input, output, cache write, and cache read. Both clients keep
parse ownership in process. ADR-0007 permits Windows to persist disposable
per-file parse checkpoints, and ADR-0008 permits the equivalent optimization
on macOS. Neither cache changes the source-of-truth boundary.

Both native clients additionally derive two optional summaries from the same
records: Billing tokens excludes cache read, while API equivalent applies the
recorded Model's standard list prices to all four Token Kinds. Unknown Models
remain unpriced and make the estimate partial. These summaries do not redefine
the Token Odometer.

No token parse state or derived estimate is promoted to the shared SQLite
database, a watcher daemon, or any IPC surface. The platform-local caches from
ADR-0007 and ADR-0008 are disposable and never authoritative. macOS watches
its transcript roots only while the Tokens tab is visible. Windows fully
reconciles its persisted range at app startup and keeps an event-driven
`FileSystemWatcher` inside the resident tray process so the tray's objective
Token summary remains current (see the 2026-07-29 amendment). Neither platform
polls transcript contents on a timer.

This sits under ADR-0001: the Token Odometer is the *estimate-grade* local-file
figure that ADR-0001 rejected as the source of truth for the authoritative
**Usage Window**. It survives only as a separate informational reading (see
`CONTEXT.md`), never as a quota measure or an actual bill.

## Context

The Usage tab showed Tokens Today by re-walking the entire `~/.claude/projects` tree every 5 seconds while the popover was open (`TokensTodayModel.pollWhileVisible` → `dailyUsage`). On a machine with many projects that is a per-poll filesystem enumeration plus a `stat` per file — wasteful, and it ran even when the agent was idle.

The repo already has the obvious-looking machinery to "do this properly": a hook CLI (`apps/agent-sessions-cli`, ADR agent-sessions/0001) that writes session lifecycle events into a shared SQLite database with WAL tuned for concurrent writers. So the tempting path is to have something parse transcripts and write token totals into that DB, leaving TokenStats to read a cheap `SUM`.

We walked that path and several escalations of it:

- **Hooks write tokens to the DB.** Rejected: hook payloads don't carry token usage (only `transcript_path`), so each hook would have to parse the transcript itself; and each hook is a separate short-lived `bun` invocation, so per-call cold-start cost and no reusable in-memory cursor/dedup state.
- **A resident watcher daemon (launchd) writes tokens to the DB.** A single long-lived process fixes the cold-start and state-reuse problems. But its only justification was sharing the figure across consumers — and **there are no other consumers**: the TUI (`apps/agent-sessions-tui`) and the shared `@repo/actions` / `@repo/database` packages reference no token data. Tokens Today is read by exactly one process, the TokenStats popover, which is *already* a resident menu-bar app.
- **Watcher exposes the figure over IPC instead of the DB.** Avoids persistence but is strictly more code (socket server + protocol + a Swift client + a bun client) and strictly less robust (daemon down = no data at all; state lost on restart) — for a number only one already-running app ever displays.

With the sole consumer being a resident app and the menu-bar label driven by the *Usage Window* (not Tokens Today), nothing displays Tokens Today when the popover is closed. The perf problem was never "polls when closed" — `pollWhileVisible` already gates on visibility — it was the **repeated full-tree walk while open**.

## Decision

Keep the Today counter **in-process** in TokenStats. Do not add a token table, a
watcher daemon, or an IPC surface. The original implementation kept every parse
checkpoint in memory; ADR-0007 and
[ADR-0008](0008-macos-transcript-parse-checkpoints.md) now permit narrow,
platform-local disposable disk caches without changing the source-of-truth
decision. The Usage view is a pure derivation over reconciled transcript
records and a versioned list-price catalog.

Replace the Usage tab's 5-second poll with an **FSEvents watch on `~/.claude/projects`, armed only while the Usage tab is visible**. On a coalesced change event, re-run the existing `dailyUsage` walk wholesale (no narrowing by changed path):

- **Coalescing latency ~1s** is mandatory, not optional — it collapses a burst of transcript appends into one walk, so an active session triggers at most ~one walk/second and an idle-but-open popover triggers none.
- The full-tree walk is **reused, not refactored**: `dailyUsage` already handles enumeration, the today/yesterday filter, incremental parsing, and per-response dedup. We swap only its *trigger* (timer → FSEvents).

Scope is the **Usage tab's Tokens Today loop only**. The Sessions tab's poll is unchanged: its cost is bounded by the known session list, and its source of truth is the **sessions DB** (new sessions arrive as hook-written rows), which a `~/.claude/projects` file-watch would not observe.

## Consequences

- **Positive:** the repeated full-tree walk is gone — idle popover does zero filesystem work, active use does ~one walk/second. No second process, no launchd plist to install/codesign/keep alive, no schema migration, no IPC protocol or reconnect logic, no cross-language client. The change is small and reuses proven code. Estimate-grade data stays out of the shared persistence layer, so the DB keeps meaning "authoritative session state," not "a cache of guesses."
- **Negative:** there is no durable, authoritative record of Tokens Today, and a future headless consumer (or a TUI tokens column) would have nothing supported to read. The disposable caches are not APIs or historical ledgers. If such a consumer ever appears, this decision must be revisited, and the watcher-daemon-writes-DB option above becomes the natural answer.
- On macOS, the **first** popover open after launch still pays one full-tree enumeration. Valid ADR-0008 checkpoints avoid re-parsing unchanged committed transcript content, but there is no startup pre-warm or cache-wide scan: a pre-warm would add launch-time work for an off-screen number, while an always-on watcher would keep doing hidden work. Windows instead performs a startup reconciliation and may hydrate unchanged files from ADR-0007 checkpoints.
- **Midnight rollover** is not specially handled: if the popover stays open across local midnight with no further file activity, the displayed day is stale until the next change event re-runs `dailyUsage`. Accepted as rare.
- On macOS, choosing **(A) re-walk on change** over narrowing to the event's
  changed paths trades some redundant walks during active bursts for zero new
  code and no new bug surface. Windows instead uses ADR-0007's targeted
  reconciliation, with a full reconciliation after startup, manual refresh, or
  an unsafe watcher event.

## Amendment — 2026-07-28

At the time of this amendment the figure stayed **in-process and in-memory**,
with no token table, watcher daemon, or IPC surface, refreshed by an FSEvents
watch armed only while visible. ADR-0007 and ADR-0008 later revise only the
platform-local parse-checkpoint persistence boundaries.

**The vocabulary is retired.** `CONTEXT.md` replaced **Tokens Today** with the **Token Odometer**, which is the same measure over a *chosen range* rather than since local midnight. Read every "Tokens Today" below as "Token Odometer". The word is kept in this file's title and body because an ADR records what was decided when, not what it would be called today.

**The scope line moved tabs.** It read "the Usage tab's Tokens Today loop only". The combined figure has since been deleted from the Usage tab, which now shows Usage Window gauges and nothing else, and the watch is armed by the **Tokens tab** instead. The "watch only while visible" property is unaffected — SwiftUI arms the `.task` when that tab appears and cancels it when the tab or the popover goes away — and the Sessions tab the original scope line contrasted against no longer exists at all.

**What the ranges did *not* change.** On macOS, a 7- or 30-day range
does not persist transcript records or app-level aggregate readings, and it
does not extend the Tokens tab's visibility-gated scan lifecycle. The selected
range is a presentation preference and may survive a restart. The reader's
active per-file parse state remains in memory, and states untouched for 48
hours are still dropped on a later visible scan. ADR-0008 permits those files
to hydrate from disposable disk checkpoints after memory eviction or process
restart; ADR-0007 permits the equivalent optimization on Windows.

**What the ranges did change.** The first-open cost is no longer one figure. Measured on the research corpus with a **warm page cache**: a full 30-day scan across both roots is **~4.1s**, and the whole corpus ~5.0s; once every file's parse state is current, a re-scan is the **6–25ms** it takes to enumerate and stat the tree. A genuinely cold, post-reboot figure was never measured — `purge` needs sudo — so the 4.1s is a floor, not a worst case. The "consequences" note above still holds for Today. If another range is persisted, that range is scanned the next time the Tokens tab appears and it is the range that pays.

## Amendment — 2026-07-29

The in-process boundary remains unchanged, but the Windows watcher's lifetime
changes. This amendment supersedes the Windows portion of the 2026-07-28
"watch only while visible" statement; the macOS watcher lifetime remains
tab-visible. ADR-0007 later supersedes this amendment's strictly in-memory
Windows boundary, and ADR-0008 separately adds disposable macOS parse
checkpoints without changing that visibility gate.

### Context

The original visibility gate relied on the fact that nothing consumed the
Token Odometer while the popover was closed. Windows now places the persisted
range's objective Billing tokens or API-equivalent summary in the
notification-area tooltip. That status-area
consumer remains visible while the WPF flyout is closed, so a watcher stopped
with the Tokens tab would leave the tooltip stale.

The selected total is a display projection: the sum of the currently enabled
Token Kinds. Token Kind headings can be toggled, and cells can present a value,
that kind's share of the row's selected total, or `value (percentage)`. None of
those choices changes the raw four-kind Token Odometer, the objective
Billing/API-equivalent summary, or the tray tooltip. A disabled Token Kind
retains a dimmed raw value, has no composition percentage, and is excluded from
the percentage denominator. None of these readings is promoted to a quota
measure.

### Decision

On Windows:

- Fully reconcile the persisted Today, 7-day, or 30-day range in the background
  when the resident tray application starts.
- Arm recursive `FileSystemWatcher` subscriptions for the native Claude Code
  and Codex transcript roots for the application's lifetime. Coalesce change
  bursts before reusing the in-process incremental reader; do not add periodic
  full-tree polling.
- Recompute the table projection and objective tray summary separately from the
  same reconciled in-memory result used by the flyout.
- Persist presentation preferences such as the selected range and pin choice.
  ADR-0007 additionally permits disposable per-file parse checkpoints, but not
  an authoritative aggregate, transcript content, credentials, or a database.

This is still one native application process. It adds no service or watcher
daemon, no SQLite table, no IPC protocol, and no second source of truth.

### Consequences

- The Windows notification-area summary can stay current without opening the
  Tokens tab.
- Windows performs one full reconciliation on every application launch. A cold
  or invalidated 30-day cache can therefore incur the measured multi-second
  parse at startup, while valid ADR-0007 checkpoints avoid re-parsing unchanged
  files. Reconciliation must not block tray creation or UI activation.
- File-system subscriptions remain armed while the tray process is resident,
  but idle operation performs no repeated enumeration; work follows transcript
  events and the existing coalescing policy.
- The raw Token Odometer remains the sum of all four Token Kinds. A filtered
  selected total is only a table projection and must be labelled as such in UI,
  accessibility text, tests, and documentation; it must not alter the objective
  Billing/API-equivalent summary.

### macOS interaction parity

macOS now persists the selected Today, 7-day, or 30-day range and Token Kind
selection as presentation preferences. It also exposes the selected-total
projection and the objective Billing/API-equivalent summary in the Tokens tab.
The presentation preferences do not persist transcript records or app-level
aggregate readings, and they do not extend the FSEvents watch beyond the Tokens
tab's visible lifetime. ADR-0008 separately permits bounded, disposable parser
checkpoints. When the tab next appears, the reader scans the authoritative
files for the persisted range, restoring valid checkpoints where available,
before resuming its event-driven updates.
