# Claude Session Event Writer

Claude Code plugin that captures hook payloads and records both the raw event and
the derived **session status** into the shared agent-sessions SQLite database that
the TUI reads. The Claude counterpart of `codex-session-event-writer`.

Each hook in `hooks/hooks.json` runs the bundled CLI with bun
(`bun "${CLAUDE_PLUGIN_ROOT}/bin/agent-sessions-cli.js" claude <EventName>`). The
CLI reads the hook payload from stdin, appends a `session_events` row, and upserts
the `sessions` row with the status derived from the event. It always exits 0 so a
hook never blocks Claude. Requires `bun` on `PATH`.

Subscribed events: `SessionStart`, `UserPromptSubmit`, `PreToolUse`,
`PostToolUse`, `PermissionRequest`, `Notification`, `Stop`, `SessionEnd`.

By default it writes to `~/.local/agent-sessions/sessions.db` (the canonical path
shared with the TUI and Codex). Override with `AGENT_SESSIONS_DB`.

## The bundled CLI

`bin/agent-sessions-cli.js` is a single self-contained JS bundle produced from
`apps/agent-sessions-cli` via `bun build --target=bun` — it embeds the schema and
needs neither this monorepo nor a SQLite install at runtime, only `bun`. It is
platform-independent. It is **gitignored on source branches**; CI builds it and
publishes it on the `release` branch (alongside this plugin), so installs from
the `release` branch include it. Rebuild locally after changing the CLI:

```sh
cd apps/agent-sessions-cli && bun run build:bundle
```

See ADR-0001 (`apps/agent-sessions-tui/docs/adr/`) for why this is a bundled JS
run by bun rather than a native binary or a standalone script.

## Install

From a Claude Code session, add the `release` branch as a plugin marketplace (it
carries the built bundle) and install the plugin:

```
/plugin marketplace add https://github.com/zhangchi0104/agent-sessions.git#release
/plugin install claude-session-event-writer@agent-sessions
```

Or, for local development, build the bundle and point the marketplace at your
checkout:

```
cd apps/agent-sessions-cli && bun run build:bundle
/plugin marketplace add /Users/alexzhang/code/github.com/zhangchi0104/agent-sessions
```
