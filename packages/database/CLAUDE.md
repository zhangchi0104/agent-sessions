# @repo/database

A Drizzle + Effect (SQLite/Bun) database package.

<!-- effect-solutions:start -->
## Effect Best Practices

**IMPORTANT:** Always consult effect-solutions before writing Effect code.

1. Run `effect-solutions list` to see available guides
2. Run `effect-solutions show <topic>...` for relevant patterns (supports multiple topics)
3. Search `~/.local/share/effect-solutions/effect` for real implementations

Topics: quick-start, project-setup, tsconfig, basics, services-and-layers, data-modeling, error-handling, config, testing, cli.

Never guess at Effect patterns - check the guide first.
<!-- effect-solutions:end -->

## Stack

- `bun:sqlite` — the underlying SQLite driver.
- `drizzle-orm/bun-sqlite` — the Drizzle adapter (no Effect wrapper exists yet for bun-sqlite, so the package wires the connection into a `Layer.effect` with `Effect.acquireRelease` for open/close lifecycle).
- `Database` is a `Context.Service` exposing the Drizzle instance; consumers `yield* Database` and call `.select()`/`.insert()`/etc.

## Environment

- `DATABASE_PATH` — path to the SQLite file when `layer()` is called without a `filename`. Defaults to `./local.db` if unset. Use `:memory:` for in-process databases. drizzle-kit reads the same variable directly via `process.env`.

## Scripts

- `bun run build` — TypeScript build to `dist/`
- `bun run check` — biome lint + `tsc --noEmit -p tsconfig.test.json`
- `bun test` — runs an in-memory smoke test (`getUserById` against `:memory:`)
- `bun run db:generate` — generate migrations from `src/schema.ts` into `drizzle/`
- `bun run db:migrate` — apply pending migrations against `DATABASE_PATH`
- `bun run db:push` — push schema directly (development only)
- `bun run db:studio` — open Drizzle Studio against `DATABASE_PATH`

## Adding tables

Edit `src/schema.ts` using `drizzle-orm/sqlite-core`, then run `bun run db:generate`.
