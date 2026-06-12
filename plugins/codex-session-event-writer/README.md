# Codex Session Event Writer

Codex plugin that captures hook payloads and records both the raw event and the
derived **session status** into the shared agent-sessions SQLite database that
the TUI reads.

Each hook in `hooks.json` runs the bundled CLI with bun
(`bun ./bin/agent-sessions-cli.js codex <EventName>`). The CLI reads the Codex
hook payload from stdin, appends a `session_events` row, and upserts the
`sessions` row with the status derived from the event (RUNNING /
PENDING_APPROVAL / IDLE). It always exits 0 so a hook never blocks Codex.
Requires `bun` on `PATH`.

By default it writes to `~/.local/agent-sessions/sessions.db` (the canonical path
shared with the TUI and Claude Code). Override with `AGENT_SESSIONS_DB`.

## The bundled CLI

`bin/agent-sessions-cli.js` is a single self-contained JS bundle (~0.5 MB)
produced from `apps/agent-sessions-cli` via `bun build --target=bun` — it embeds
the schema and needs neither this monorepo nor a SQLite install at runtime, only
`bun`. It is platform-independent. The bundle is **gitignored on source
branches**; CI builds it and publishes it on the `release` branch. Build it
locally after changing the CLI:

```sh
cd apps/agent-sessions-cli && bun run build:bundle
```

See ADR-0001 (`apps/agent-sessions-tui/docs/adr/`) for why this is a bundled JS
run by bun rather than a native binary or a standalone script.

## Local Marketplace

To install from this repository as a local marketplace, add a marketplace entry
that points at the repository root:

```toml
[marketplaces.agent-sessions]
source_type = "local"
source = "/Users/alexzhang/code/github.com/zhangchi0104/agent-sessions"

[plugins."codex-session-event-writer@agent-sessions"]
enabled = true
```
