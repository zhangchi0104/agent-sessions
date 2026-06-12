# @repo/agent-sessions-cli

Hook CLI that updates agent **Session Status** from Claude Code and Codex hooks.
See `apps/agent-sessions-tui/CONTEXT.md` for the domain glossary and
`apps/agent-sessions-tui/docs/adr/` for the design decisions (ADR-0001 bundled
JS run by bun, ADR-0002 no ENDED status).

<!-- effect-solutions:start -->
## Effect Best Practices

**IMPORTANT:** Always consult effect-solutions before writing Effect code.

1. Run `effect-solutions list` to see available guides
2. Run `effect-solutions show <topic>...` for relevant patterns (supports multiple topics)
3. Search `~/.local/share/effect-solutions/effect` for real implementations

Topics: quick-start, project-setup, tsconfig, basics, services-and-layers, data-modeling, error-handling, config, testing, cli.

Never guess at Effect patterns - check the guide first.
<!-- effect-solutions:end -->

## What it does

`agent-sessions-cli <claude|codex> <HookEventName>` reads a hook payload from
stdin, then via `@repo/actions` `applyHookEvent` appends a `session_events` row
and upserts the `sessions` row with the derived status. It is a thin runner; all
logic lives in `@repo/actions` (`deriveStatus`, `applyHookEvent`) and the schema
in `@repo/database` (`ensureSchema`).

Contract: the agent is the subcommand, the event name is the positional arg
(falling back to `AGENT_SESSIONS_HOOK_EVENT`), the payload is stdin. It **always
exits 0** so a hook never breaks the agent.

## Scripts

- `bun run start` — run against source
- `bun run build:bundle` — bundle the self-contained JS into the Codex plugin's `bin/`
- `bun run check` — biome lint + `tsc --noEmit`
