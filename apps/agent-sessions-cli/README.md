# agent-sessions-cli

A hook CLI that keeps the agent-sessions database in sync with what each Claude
Code / Codex session is doing. Both agents run the same bundled JS via `bun` on
their lifecycle hooks; the TUI reads the result.

```
bun agent-sessions-cli.js <claude|codex> <HookEventName>     # hook payload on stdin
```

- **Agent** is the subcommand (`claude` → `ClaudeCode`, `codex` → `Codex`).
- **Event name** is the positional arg, or `AGENT_SESSIONS_HOOK_EVENT`.
- **Payload** is read from stdin (raw hook JSON), stored verbatim.
- **Database** defaults to `~/.local/agent-sessions/sessions.db`; override with `AGENT_SESSIONS_DB`.
- Always exits 0 — a hook must never break the agent.

## Status mapping

Status answers "who are we waiting on?" (see `apps/agent-sessions-tui/CONTEXT.md`).

| → | Claude Code | Codex |
|---|---|---|
| `RUNNING` | UserPromptSubmit, PreToolUse, PostToolUse, PostToolBatch, SubagentStart | UserPromptSubmit, PreToolUse, PostToolUse |
| `PENDING_APPROVAL` | PermissionRequest, Notification{permission_prompt} | any Notification |
| `IDLE` | Stop, SessionEnd, Notification{idle_prompt} | Stop, SessionEnd |

Every other event is logged to `session_events` but leaves the status unchanged.

## Build the bundle

```sh
bun run build:bundle   # bun build --target=bun -> ../../plugins/codex-session-event-writer/bin/agent-sessions-cli.js
```

The output is a single self-contained JS file (~0.5 MB, schema embedded, no
monorepo/SQLite needed at runtime — only `bun`) and is platform-independent.
Rebuild after changing the CLI or its monorepo deps.

## Wiring

Both agents are wired via plugins that ship the bundle in their own `bin/` and
call it on the relevant hooks — no hand-editing of settings files.

**Codex** — enable `plugins/codex-session-event-writer/` (see its README).

**Claude Code** — install `claude-session-event-writer` from the repo's `release`
branch (CI builds the bundle there; the bundle is gitignored on `main`):

```
/plugin marketplace add https://github.com/zhangchi0104/agent-sessions.git#release
/plugin install claude-session-event-writer@agent-sessions
```

For local development, build the bundle and point the marketplace at your
checkout instead:
`cd apps/agent-sessions-cli && bun run build:bundle` then
`/plugin marketplace add /path/to/agent-sessions`.

Both plugins write to the same canonical database, so the TUI shows Claude and
Codex sessions together.
