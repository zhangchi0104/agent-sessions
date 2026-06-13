# agent-sessions

A Bun-first Turborepo that hosts two related coding-agent tools, plus a Claude
Code plugin marketplace. Each tool is its own [bounded
context](CONTEXT-MAP.md) with its own glossary:

- **Agent Sessions** — track the live coding-agent **sessions** you have running
  (across Claude Code and Codex) and see at a glance which one is working, which
  is waiting on you, and which is idle. Lifecycle hooks record events into a
  shared SQLite database that a TUI reads. *(Documented below.)*
- **[TokenStats](apps/TokenStats/)** — a macOS status-bar app showing how much of
  a coding agent's usage allowance you've consumed and when it resets.
  *(See [TokenStats](#tokenstats).)*

This repository is also a **Claude Code plugin marketplace** (see
[Plugin marketplace](#plugin-marketplace)).

## How it works

```
Claude Code ─┐                      ┌─ sessions table (status per session)
             ├─ hooks ─> agent-sessions-cli ─> SQLite ─┤
Codex ───────┘                      └─ session_events (append-only log)
                                              ▲
                                  agent-sessions-tui reads it
```

Each agent runs a hook on its lifecycle events (prompt submitted, tool about to
run, turn stopped, …). The hook invokes a small bundled CLI that appends the raw
event and upserts the session's **status** — `RUNNING`, `PENDING_APPROVAL`, or
`IDLE` — answering "who are we waiting on?". See
[`apps/agent-sessions-tui/CONTEXT.md`](apps/agent-sessions-tui/CONTEXT.md) for the
domain glossary and [`apps/agent-sessions-tui/docs/adr/`](apps/agent-sessions-tui/docs/adr/)
for the design decisions.

## Plugin marketplace

The repo's root [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json)
makes it a Claude Code plugin marketplace. The plugin bundles are **not** on
`main` — CI builds them and publishes the **`release`** branch (see
[Releasing](#releasing)), so add the marketplace from that branch using the full
git URL (the `owner/repo` shorthand only reads the default branch):

```
/plugin marketplace add https://github.com/zhangchi0104/agent-sessions.git#release
/plugin install claude-session-event-writer@agent-sessions
```

For local development, build the bundles and point the marketplace at your
checkout instead:

```
cd apps/agent-sessions-cli && bun run build:bundle
/plugin marketplace add /path/to/agent-sessions
```

Available plugins:

| Plugin | Agent | What it does |
|--------|-------|--------------|
| [`claude-session-event-writer`](plugins/claude-session-event-writer/) | Claude Code | Records session hooks and derives status into the shared DB |
| [`codex-session-event-writer`](plugins/codex-session-event-writer/) | Codex | Same, for Codex (installed via Codex's marketplace — see its README) |

Both plugins run the same self-contained CLI bundle from their `bin/` and write to
the canonical database `~/.local/agent-sessions/sessions.db` (override with
`AGENT_SESSIONS_DB`), so the TUI shows Claude and Codex sessions together.

> The Codex plugin is a Codex-format plugin and is **not** listed in the Claude
> marketplace; it's registered separately in
> [`.agents/plugins/marketplace.json`](.agents/plugins/marketplace.json).

## TokenStats

[`apps/TokenStats/`](apps/TokenStats/) is a macOS status-bar app (Swift/SwiftUI)
that shows how much of a coding agent's usage allowance has been consumed and
when it resets. Claude Code is supported first; Codex support is being shaped
behind the same trust bar. It reads the agent's authoritative usage endpoint for
the gauge and sums local transcript files for an informational "tokens today"
odometer — see [`apps/TokenStats/CONTEXT.md`](apps/TokenStats/CONTEXT.md) for the
domain glossary and [`apps/TokenStats/docs/adr/`](apps/TokenStats/docs/adr/) for
the design decisions.

**Install:** download the latest codesigned, notarized `.dmg` from the
[releases](https://github.com/zhangchi0104/agent-sessions/releases) (tags are
scoped `tokenstats-v*`; betas are marked pre-release).

**Build locally** (requires Xcode):

```sh
cd apps/TokenStats
bun run dev      # build Debug and launch the app
bun run build    # build Release
```

Releases are fully automated — pushes to `dev` cut a beta `.dmg` and `main` cuts
a stable one. See [`apps/TokenStats/docs/release.md`](apps/TokenStats/docs/release.md).

## Layout

```txt
.
├── .claude-plugin/marketplace.json   # Claude Code plugin marketplace
├── apps/
│   ├── agent-sessions-cli/           # hook CLI (bundled into the plugins)
│   ├── agent-sessions-tui/           # terminal viewer + domain glossary/ADRs
│   └── TokenStats/                   # macOS usage-tracking app (own context)
├── packages/
│   ├── actions/                      # SessionsRepo, status derivation, hook schema
│   ├── database/                     # Drizzle schema + SQLite client
│   ├── biome-config/ typescript-config/
├── plugins/
│   ├── claude-session-event-writer/  # Claude plugin (hooks + bundled CLI)
│   └── codex-session-event-writer/   # Codex plugin (hooks + bundled CLI)
└── turbo/generators/                 # workspace scaffolding generator
```

## Development

Bun-first Turborepo. Requires Bun `1.3.13`+.

```sh
bun install
bun run build          # turbo build
bun run check-types
```

Rebuild the CLI bundle into both plugins after changing the CLI or its deps:

```sh
cd apps/agent-sessions-cli && bun run build:bundle
```

Per-package scripts (`check`, `test`, etc.) live in each package's `package.json`.

## Releasing

Two independent pipelines, each scoped to its own artifacts:

**Plugins.** The plugin bundles (`plugins/*/bin/agent-sessions-cli.js`) are
gitignored on source branches. The [`Publish release branch`](.github/workflows/release-plugins.yml)
GitHub Action builds them and force-pushes a **`release`** branch — `main` plus
the built bundles — on every relevant push to `main` (or via manual
`workflow_dispatch`). That branch is what users install as a marketplace
(`…agent-sessions.git#release`). Nothing about releasing requires committing a
build artifact to `main`.

**TokenStats.** The [`release-tokenstats`](.github/workflows/release-tokenstats.yml)
workflow runs semantic-release on pushes touching `apps/TokenStats/**`: `dev`
ships a beta `.dmg`, `main` a stable one, each codesigned, notarized, and
attached to a `tokenstats-v*` GitHub Release. See
[`apps/TokenStats/docs/release.md`](apps/TokenStats/docs/release.md).
