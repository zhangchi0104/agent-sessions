# TUI Concurrency and Live Refresh

**Date:** 2026-05-08
**Status:** Design — approved, ready for implementation plan
**Scope:** `packages/database`, `apps/agent-sessions-tui`

## Problem

`apps/agent-sessions-tui` opens `~/.local/agent-sessions/sessions.db` via `bun:sqlite` (Drizzle), reads sessions once at startup, and renders. Hook processes (separate OS processes that import `@repo/database`) write to the same file concurrently. Two issues follow:

1. **Concurrency safety.** With SQLite's default rollback journal mode, a writer takes an exclusive lock and concurrent readers immediately fail with `SQLITE_BUSY`. There is no per-connection retry timeout configured, so the TUI and hook processes can fail each other's queries under contention.
2. **Staleness.** The TUI loads once and renders. Sessions inserted or updated by hooks after that point are invisible until the user restarts the TUI.

## Goals

- The TUI and any number of hook processes can read and write the database concurrently without `SQLITE_BUSY` errors during normal operation.
- The TUI re-renders within ~1 second of a hook commit, with no manual user action.
- All connection-level safety settings live in `@repo/database` so consumers cannot accidentally bypass them.

## Non-goals

- Row-level diff animation or selection-state preservation. The TUI is currently read-only and has no selection.
- Checkpoint tuning. SQLite's default `wal_autocheckpoint = 1000 pages` is fine at current volume.
- Manual refresh keybinding. The watcher covers the use case.
- A notification protocol between hook processes and the TUI. The WAL file already serves that purpose.
- Multi-database or remote replication. Single local SQLite file remains the model.

## Design

### Part 1: Concurrency safety in `Database.layer`

In `packages/database/src/client.ts`, after `new BunDatabase(filename)` and before handing the client to `drizzle(...)`, apply these PRAGMAs:

```ts
if (filename !== ":memory:") {
  client.exec("PRAGMA journal_mode = WAL;");
}
client.exec("PRAGMA busy_timeout = 5000;");
client.exec("PRAGMA synchronous = NORMAL;");
client.exec("PRAGMA foreign_keys = ON;");
```

**Rationale per pragma:**

- `journal_mode = WAL` — persistent property of the database file, but re-applied on every open as a safety net. Allows N concurrent readers + 1 writer. Skipped for `:memory:` because WAL is meaningless there and SQLite logs a warning.
- `busy_timeout = 5000` — *per connection*; must be set on every open. Without it, a reader hitting a writer's lock fails immediately. With 5s, contention becomes a brief wait instead of an error.
- `synchronous = NORMAL` — the standard companion to WAL. No corruption risk on power loss; meaningfully faster than `FULL`.
- `foreign_keys = ON` — preventive. The current schema has no foreign keys but the cost is negligible.

**Migration safety.** The TUI runs `migrate` at startup. If a hook process runs simultaneously, `busy_timeout` makes it wait. Drizzle's migrator wraps each migration in a transaction and is idempotent against an already-migrated schema, so concurrent first-run startup is safe.

### Part 2: Live refresh via WAL file watching

The TUI watches `${dbPath}-wal` for filesystem events and re-queries on activity.

```
sessions.db-wal changes
        │
        ▼
  fs.watch event ('change' or 'rename')
        │
        ▼
  debounce 100 ms ──► repo.listSessions({}) ──► if rows differ, swap table + summary content
```

**Why the WAL file, not the main `.db`.** With WAL mode, every commit appends to `*.db-wal`. The main `.db` only changes at checkpoint, which can be minutes apart. Watching the main file would miss most writes.

**Bootstrapping.** If no hook has ever written, `*.db-wal` may not exist when the TUI starts. After `migrate` and before mounting the UI, the TUI runs a no-op write transaction (`BEGIN IMMEDIATE; COMMIT;`) to force WAL creation. This makes the watcher target deterministic.

**Debouncing.** A single hook commit can fire multiple `fs.watch` events on macOS (e.g., `change` plus `rename` on WAL truncation during checkpoint). The watcher coalesces events within a 100 ms window into one `listSessions` call.

**Re-render strategy.** Rather than tearing down `renderer.root` and re-mounting, the TUI holds references to the table renderable and the summary text renderable. On refresh, it updates their content props in place. This avoids flicker and keeps the renderable tree stable.

**Diff check.** Before swapping content, compare the new list against the last-rendered list (shallow comparison on `id` + `status` + `updatedAt`). If unchanged, skip the render. This protects against checkpoint-only WAL events that don't reflect data changes.

**macOS quirks.** `fs.watch` on Darwin can emit `rename` when SQLite truncates the WAL at checkpoint. Both `change` and `rename` are treated as "something happened, re-query." If the underlying watcher errors out, the surrounding fiber logs and re-creates a fresh `fs.watch` handle once before giving up — the outer `acquireRelease` still finalizes whichever handle is current at scope exit.

**Effect integration.**

- The watcher is exposed as a `Stream` of debounced "wal changed" events.
- A render fiber consumes the stream and calls `repo.listSessions({})` per event.
- The watcher itself is wrapped in `Effect.acquireRelease`, so the underlying `fs.watch` handle is closed when the TUI scope ends.
- The render fiber is forked into the TUI's main scope; quitting the TUI (q / Ctrl+C) tears it down.

### Part 3: File changes

**`packages/database/src/client.ts`**
- Add the PRAGMA block after `new BunDatabase(filename)`. ~6 lines.

**`apps/agent-sessions-tui/src/index.ts`**
- After `migrate`, run a no-op write transaction to force WAL creation.
- Refactor `mountUi` so it returns refs to the table renderable and summary text renderable (or holds them in closure).
- Add a watcher fiber: `fs.watch(${db}-wal)` → debounced stream → `repo.listSessions({})` → diff → update content.
- Make sure renderer cleanup tears down the watcher fiber.

## Testing

**`packages/database/tests/`**
- Open the layer twice against the same temp file path; assert `PRAGMA journal_mode` returns `wal` and `PRAGMA busy_timeout` returns `5000` on both connections.
- Concurrent write+read smoke test: open two layers, start a write transaction on one (held briefly), issue a select on the other; assert no `SQLITE_BUSY` and correct results.
- Confirm `:memory:` still works — opening with `filename: ":memory:"` does not error and does not run the WAL pragma.

**`apps/agent-sessions-tui`**
- TUI live-refresh integration testing is contingent on whether OpenTUI offers a tractable test harness. If wiring is cheap, add a test that spawns a writer in a child process and asserts the TUI's repo re-fires. If not, document manual verification steps and rely on the unit tests above. This decision is deferred to implementation time.

## Open questions

None blocking. OpenTUI's exact API for in-place content updates on `TextTableRenderable` will be confirmed at implementation time; if mutation-in-place is unavailable, fall back to removing and re-adding the renderable inside the same parent box (still avoids root re-mount).
