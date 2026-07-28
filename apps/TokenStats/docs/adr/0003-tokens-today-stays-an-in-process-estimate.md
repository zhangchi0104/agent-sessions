# Tokens Today stays an in-process estimate, not a shared-DB figure

**Tokens Today** — the raw sum of input/output/cache tokens across every Claude Code transcript touched since local midnight — is computed **in-process inside TokenStats**, from local transcript files, held in memory. It is deliberately **not** promoted to the shared SQLite database, a watcher daemon, or any IPC surface. The popover's Usage tab refreshes it by **watching `~/.claude/projects` with FSEvents while visible** instead of polling on a timer.

This sits under ADR-0001: Tokens Today is the *estimate-grade* local-file figure that ADR-0001 rejected as the source of truth for the authoritative **Usage Window**. It survives only as a separate informational odometer (see `CONTEXT.md`), never as a quota measure.

## Context

The Usage tab showed Tokens Today by re-walking the entire `~/.claude/projects` tree every 5 seconds while the popover was open (`TokensTodayModel.pollWhileVisible` → `dailyUsage`). On a machine with many projects that is a per-poll filesystem enumeration plus a `stat` per file — wasteful, and it ran even when the agent was idle.

The repo already has the obvious-looking machinery to "do this properly": a hook CLI (`apps/agent-sessions-cli`, ADR agent-sessions/0001) that writes session lifecycle events into a shared SQLite database with WAL tuned for concurrent writers. So the tempting path is to have something parse transcripts and write token totals into that DB, leaving TokenStats to read a cheap `SUM`.

We walked that path and several escalations of it:

- **Hooks write tokens to the DB.** Rejected: hook payloads don't carry token usage (only `transcript_path`), so each hook would have to parse the transcript itself; and each hook is a separate short-lived `bun` invocation, so per-call cold-start cost and no reusable in-memory cursor/dedup state.
- **A resident watcher daemon (launchd) writes tokens to the DB.** A single long-lived process fixes the cold-start and state-reuse problems. But its only justification was sharing the figure across consumers — and **there are no other consumers**: the TUI (`apps/agent-sessions-tui`) and the shared `@repo/actions` / `@repo/database` packages reference no token data. Tokens Today is read by exactly one process, the TokenStats popover, which is *already* a resident menu-bar app.
- **Watcher exposes the figure over IPC instead of the DB.** Avoids persistence but is strictly more code (socket server + protocol + a Swift client + a bun client) and strictly less robust (daemon down = no data at all; state lost on restart) — for a number only one already-running app ever displays.

With the sole consumer being a resident app and the menu-bar label driven by the *Usage Window* (not Tokens Today), nothing displays Tokens Today when the popover is closed. The perf problem was never "polls when closed" — `pollWhileVisible` already gates on visibility — it was the **repeated full-tree walk while open**.

## Decision

Keep Tokens Today **in-process and in-memory** in TokenStats. Do not add a token table, a watcher daemon, or an IPC surface.

Replace the Usage tab's 5-second poll with an **FSEvents watch on `~/.claude/projects`, armed only while the Usage tab is visible**. On a coalesced change event, re-run the existing `dailyUsage` walk wholesale (no narrowing by changed path):

- **Coalescing latency ~1s** is mandatory, not optional — it collapses a burst of transcript appends into one walk, so an active session triggers at most ~one walk/second and an idle-but-open popover triggers none.
- The full-tree walk is **reused, not refactored**: `dailyUsage` already handles enumeration, the today/yesterday filter, incremental parsing, and per-response dedup. We swap only its *trigger* (timer → FSEvents).

Scope is the **Usage tab's Tokens Today loop only**. The Sessions tab's poll is unchanged: its cost is bounded by the known session list, and its source of truth is the **sessions DB** (new sessions arrive as hook-written rows), which a `~/.claude/projects` file-watch would not observe.

## Consequences

- **Positive:** the repeated full-tree walk is gone — idle popover does zero filesystem work, active use does ~one walk/second. No second process, no launchd plist to install/codesign/keep alive, no schema migration, no IPC protocol or reconnect logic, no cross-language client. The change is small and reuses proven code. Estimate-grade data stays out of the shared persistence layer, so the DB keeps meaning "authoritative session state," not "a cache of guesses."
- **Negative:** the figure exists only while TokenStats runs — there is no durable record of Tokens Today, and a future headless consumer (or a TUI tokens column) would have nothing to read. If such a consumer ever appears, this decision must be revisited, and the watcher-daemon-writes-DB option above becomes the natural answer (its only missing justification today is that second consumer).
- The **first** popover open after launch still pays one full-tree enumeration (a cold read); we accept that latency rather than pre-warm with an always-on watcher, because pre-warming means parsing transcripts all day for an off-screen number.
- **Midnight rollover** is not specially handled: if the popover stays open across local midnight with no further file activity, the displayed day is stale until the next change event re-runs `dailyUsage`. Accepted as rare.
- Choosing **(A) re-walk on change** over narrowing to the event's changed paths trades some redundant walks during active bursts for zero new code and no new bug surface. If active-session walk cost ever bites, narrowing by changed path (parse only changed files, sum today's buckets from the in-memory `states`) is the escalation — it removes the walk entirely after the seed.

## Amendment — 2026-07-28

The decision above is unchanged: the figure stays **in-process and in-memory**, with no token table, no watcher daemon and no IPC surface, refreshed by an FSEvents watch armed only while visible. Two things around it moved.

**The vocabulary is retired.** `CONTEXT.md` replaced **Tokens Today** with the **Token Odometer**, which is the same measure over a *chosen range* rather than since local midnight. Read every "Tokens Today" below as "Token Odometer". The word is kept in this file's title and body because an ADR records what was decided when, not what it would be called today.

**The scope line moved tabs.** It read "the Usage tab's Tokens Today loop only". The combined figure has since been deleted from the Usage tab, which now shows Usage Window gauges and nothing else, and the watch is armed by the **Tokens tab** instead. The "watch only while visible" property is unaffected — SwiftUI arms the `.task` when that tab appears and cancels it when the tab or the popover goes away — and the Sessions tab the original scope line contrasted against no longer exists at all.

**What the ranges did *not* change.** A 7- or 30-day range re-reads more files on the first pass, but adds no persistence: the reader's per-file parse state is still the only cache and still in-memory, and states untouched for 48 hours are still dropped — on the next scan, since eviction runs inside the scan and the scan only runs while the tab is visible. A process that never sees the Tokens tab again holds what it has.

**What the ranges did change.** The first-open cost is no longer one figure. Measured on the research corpus with a **warm page cache**: a full 30-day scan across both roots is **~4.1s**, and the whole corpus ~5.0s; once every file's parse state is current, a re-scan is the **6–25ms** it takes to enumerate and stat the tree. A genuinely cold, post-reboot figure was never measured — `purge` needs sudo — so the 4.1s is a floor, not a worst case. The "consequences" note above still holds for Today, which is what a popover opens on; a 30-day range is a deliberate switch, and it is the range that pays.
