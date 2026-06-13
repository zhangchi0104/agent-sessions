# 2. No ENDED status; SessionEnd collapses into IDLE

Date: 2026-06-10

Status: Accepted

## Context

A Session's **Status** is one of `IDLE`, `RUNNING`, `PENDING_APPROVAL` (the existing `sessions.status` enum). Agents emit an explicit end-of-session hook (Claude `SessionEnd` with reasons like `logout`, `clear`, `prompt_input_exit`; Codex an equivalent). We had to decide how a finished session is represented.

Conceptually "ended" and "between turns" are distinguishable: an ended session is gone, while an IDLE-between-turns session is alive and awaiting the user's next prompt. Modeling that distinction would mean either a new `ENDED` enum value (a schema migration) or an `endedAt` column, and the TUI could then show "finished" separately from "your move."

But for the product's actual job — *"which session needs my attention right now?"* — both states are the same answer: nothing is happening and nothing is blocked. The user's next action (or inaction) is identical.

## Decision

Do **not** add an `ENDED` status. `SessionEnd` (and the Codex equivalent) maps to **IDLE**. `IDLE` is defined as "the agent is at rest — finished its turn *or* the session has ended; nothing is happening, your move." The Status model keeps exactly three values.

## Consequences

- **Positive:** no schema migration; the Status enum and the "who are we waiting on?" model stay minimal; the TUI's three-way display is unchanged.
- **Negative:** the TUI **cannot distinguish** a closed session from one that finished its turn and is idle. A stale ended session looks identical to a live idle one. If we later want a "recently finished / closed" affordance, we must add an `ENDED` status (migration) or an `endedAt` timestamp and revisit this.
- This intentionally overrides an earlier, finer distinction drawn while defining the glossary; `CONTEXT.md`'s definition of IDLE was updated to match.
