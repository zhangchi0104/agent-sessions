# 1. Bundled-JS hook CLI run by bun

Date: 2026-06-10

Status: Accepted

## Context

Claude Code and Codex both invoke external commands at lifecycle moments (hooks). We want those hooks to update an Agent Session's **Status** (RUNNING / PENDING_APPROVAL / IDLE) in a shared SQLite database that the TUI reads.

The pre-existing approach was a **standalone Bun script** bundled inside a Codex marketplace plugin (`plugins/codex-session-event-writer/`). It deliberately imported no monorepo code ("only requires Bun") so it could run on a machine that doesn't have this repo checked out. But it only appended raw rows to `session_events` — it never upserted the `sessions` row or derived Status, which is the whole point of the new work.

Doing status derivation properly means reusing assets that already live in the monorepo: the full Claude Code hook-event schema and `SessionsRepo` in `@repo/actions`, and the Drizzle schema in `@repo/database`. A standalone, repo-free script cannot import those without duplicating them.

Constraints in tension:
- The hook is a **hot path** — it fires on every tool call and blocks the agent until it returns.
- The integration must still run on a user's machine **without the monorepo present** (especially the Codex plugin, distributed via a marketplace).
- We want **one** implementation of status derivation, not one per agent.

An earlier draft of this decision compiled the CLI to a native single-file executable (`bun build --compile`). That produced a ~64 MB, **platform-specific** artifact that had to be committed to version control — heavy, and wrong for any machine of a different OS/arch. Since the target machine always has `bun` available, a native executable buys nothing over a bundled script.

## Decision

Build a single CLI (`apps/agent-sessions-cli`) that depends on `@repo/actions` and `@repo/database`, and bundle it to **one self-contained `.js` file** with `bun build --target=bun` (no `--compile`). Both agents call the same bundle via `bun`:

- `bun agent-sessions-cli.js claude <EventName>`
- `bun agent-sessions-cli.js codex <EventName>`

Each plugin's `hooks.json` invokes `bun <plugin>/bin/agent-sessions-cli.js <agent> <Event>`. The bundle (~0.5 MB) is **gitignored on source branches**, not committed to `main`: a GitHub Action builds it and force-pushes a `release` branch (`main` + the built `plugins/*/bin/agent-sessions-cli.js`), which is the branch users add as a marketplace (`…agent-sessions.git#release`). Local development builds it on demand with `bun run build:bundle`.

Everything except `bun`'s own builtins (notably `bun:sqlite`) is bundled in, including the schema DDL — which is an inline string in `@repo/database` (`ensureSchema`), not a file read — so the bundle needs neither the monorepo nor a separate SQLite install at runtime.

## Consequences

- **Positive:** one codepath for status derivation, shared with the TUI's data model and covered by the existing `@repo/actions` tests; the committed artifact is small (~0.5 MB) and **platform-independent** — the same `.js` runs on any OS/arch that has `bun`. No native-binary build matrix.
- **Negative:** `bun` must be on `PATH` at hook time (an accepted assumption for this project). The bundle is a build artifact that must be rebuilt after changing the CLI or its monorepo deps — automated by the release workflow, or `bun run build:bundle` locally. Installing the marketplace must use the `release` branch (via the full git URL `#release`), since the `owner/repo` shorthand only reads the default branch, which has no bundle.
- The original standalone Bun script and the duplicate `packages/database/scripts/write-session-event.ts` are removed; their behavior is subsumed by the CLI.
