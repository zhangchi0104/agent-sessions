# Codex Session Event Writer

Standalone Codex plugin that captures hook payloads and writes them to a local
SQLite `session_events` table.

The hook command reads the Codex hook payload from stdin, creates the
`session_events` table if needed, and stores the raw JSON payload alongside
normalized columns for `session_id`, `event_name`, `tool_name`, `cwd`, and
`created_at`. It only requires Bun and does not import code from this
repository.

By default it writes to `~/.codex/agent-sessions/local.db`. Set
`DATABASE_PATH` or `AGENT_SESSIONS_DATABASE_PATH` to point at a different
SQLite database.

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
