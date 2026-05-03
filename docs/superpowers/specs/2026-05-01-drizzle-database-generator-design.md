# Drizzle + Effect Database Generator — Design

## Context

The repo already has an `effect` generator at `turbo/generators/effect/index.ts` that scaffolds Effect packages of two types: `library` (under `packages/<name>`) and `app` (under `apps/<name>`). The generator dispatches on a `type` prompt via two parallel maps:

```ts
const SUBDIR: Record<ProjectType, string> = { library: "packages", app: "apps" };
const TEMPLATE_BASE: Record<ProjectType, string> = {
  library: "effect/templates",
  app: "effect/templates/app",
};
```

The team needs a third package shape: a database package that wires Drizzle ORM into an Effect Layer using Effect's SQL packages, with first-class support for both PostgreSQL and SQLite (Bun runtime).

References:

- Drizzle's "Effect + PostgreSQL — new project" guide: https://orm.drizzle.team/docs/get-started/effect-postgresql-new
- `@effect/sql-pg`: https://effect-ts.github.io/effect/docs/sql-pg
- `@effect/sql-sqlite-bun`: https://effect-ts.github.io/effect/docs/sql-sqlite-bun

## Goal

Extend the existing `effect` generator with a third `type` value, `database`, plus a second list prompt `engine` (`postgresql | sqlite`) that fires only when `type === "database"`. The generator emits a buildable, testable package under `packages/<name>/` that:

- Defines Drizzle schema in `src/schema.ts`.
- Exposes an Effect `Layer` factory that wires Drizzle into an `Effect` runtime — using `drizzle-orm/effect-postgres` (built into drizzle 1.0.0-rc.1) for PostgreSQL, and `drizzle-orm/bun-sqlite` + a hand-rolled `Layer.effect` for SQLite (no Effect adapter exists for bun-sqlite yet).
- Ships drizzle-kit configuration and `db:*` scripts for migrations.
- Has a passing `bun test` on a fresh scaffold (in-memory smoke for SQLite, import-only smoke for PostgreSQL).

Out of scope: HTTP/RPC layers on top of the database, schema introspection from existing databases, migration runners written from scratch, multi-tenant connection pools.

## Interactive Prompts

The generator collects, in order:

1. **`type`** (list, required) — `library | app | database`. Default `library`.
2. **`engine`** (list, required, conditional) — `postgresql | sqlite`. Only prompted when `type === "database"` (via plop's `when:` callback). No default — force a deliberate choice.
3. **`packageName`** (input, required) — kebab-case (`/^[a-z0-9]+(-[a-z0-9]+)*$/`). Rejects collisions with an existing directory under the chosen `SUBDIR`.
4. **`description`** (input, optional) — short string for `package.json#description` and CLAUDE.md header.
5. **`author`** (input, optional) — defaults to `git config user.name`, falling back to empty.

The existing `validateName` and `getGitUserName` helpers are reused without modification. `EffectAnswers` gains an optional `engine?: Engine` field.

## Generator Module Changes

File: `turbo/generators/effect/index.ts`.

- Extend `ProjectType` union: `"library" | "app" | "database"`.
- Add `type Engine = "postgresql" | "sqlite"`.
- Update `SUBDIR` so `database -> "packages"`. Database packages are libraries that expose a Drizzle-backed service — same install/import semantics, same subdirectory.
- Replace the constant `TEMPLATE_BASE` with a function:

  ```ts
  function templateBase(type: ProjectType, engine?: Engine): string {
    if (type === "database") return `effect/templates/database/${engine}`;
    if (type === "app") return "effect/templates/app";
    return "effect/templates";
  }
  ```

- Add the `engine` prompt with `when: (a: Pick<EffectAnswers, "type">) => a.type === "database"`.
- Extend `buildActions` to accept `(type, engine?)` and branch on `type === "database"` for its own file list (see below). The existing `symlinkAgentsMd` action is reused unchanged.
- The action callback in `setGenerator` passes both `data.type` and `data.engine` into `buildActions`.

## Generated Package Layout (database type)

```
packages/<name>/
├── src/
│   ├── index.ts           # barrel: re-exports schema, client, queries
│   ├── schema.ts          # Drizzle table definitions
│   ├── client.ts          # layer(config?) factory + service tag
│   └── queries.ts         # SQLite only — example getUserById
├── tests/
│   └── index.spec.ts      # SQLite: in-memory smoke; PG: import-only smoke
├── drizzle/
│   └── .gitkeep           # migrations land here after `bun run db:generate`
├── drizzle.config.ts
├── package.json
├── tsconfig.json
├── tsconfig.test.json
├── biome.json
├── CLAUDE.md
└── AGENTS.md              # symlink → CLAUDE.md (created by symlinkAgentsMd action)
```

## Common File Specifications

### `package.json`

Inherits the existing library template's `name`, `version`, `description`/`author` conditional rendering, `private`, `type: "module"`, `exports`, `main`, `types`, `files`, and the catalog references for `effect`, `@biomejs/biome`, `@effect/language-service`, `@repo/biome-config`, `@repo/typescript-config`, `@types/bun`, `typescript`.

Additions for database packages:

- `dependencies` add:
  - `drizzle-orm`: `"catalog:"`
  - PG variant only: `@effect/sql-pg`: `"catalog:"` (provides `PgClient` for the connection Layer; `drizzle-orm/effect-postgres` is bundled with drizzle-orm itself)
  - SQLite variant: no extra dep beyond `drizzle-orm` (uses `drizzle-orm/bun-sqlite`, which is bundled, and `bun:sqlite`, which is built into the runtime)
- `devDependencies` add:
  - `drizzle-kit`: `"catalog:"`
- `scripts` add (alongside `build`, `check`, `test`, `prepare`):
  - `db:generate`: `"drizzle-kit generate"`
  - `db:migrate`: `"drizzle-kit migrate"`
  - `db:push`: `"drizzle-kit push"`
  - `db:studio`: `"drizzle-kit studio"`

### `tsconfig.json`

Identical to the existing library template (extends `@repo/typescript-config/tsconfig.base.json`, `outDir: "./dist"`, `rootDir: "./src"`, `@effect/language-service` plugin). No changes from `effect/templates/tsconfig.json.hbs`.

### `tsconfig.test.json`

Identical to the existing library template — already includes `tests/**/*` and turns off emit. No changes.

### `biome.json`

Same as the existing library template (extends `@repo/biome-config`). The `includes` glob (`["src/**", "tests/**", "*.json", "*.ts"]`) is already broad enough to cover `drizzle.config.ts` and `drizzle/` migrations.

### `CLAUDE.md`

Same shell as the existing library template (title, optional description, Effect best-practices block, scripts list). The scripts list adds the four `db:*` commands and notes the env var the package reads (`DATABASE_URL` for PG, `DATABASE_PATH` for SQLite).

### `src/index.ts`

```ts
export * as schema from "./schema.ts";
export { layer } from "./client.ts";
// SQLite variant additionally:
// export { getUserById } from "./queries.ts";
```

### `drizzle/.gitkeep`

Empty file. Ensures the migrations directory survives the initial commit before the user runs `db:generate`.

## PostgreSQL Variant

### `src/schema.ts`

Empty placeholder:

```ts
// Add Drizzle pg-core tables here, then run `bun run db:generate`.
// import { pgTable, serial, text, timestamp } from "drizzle-orm/pg-core";
```

### `src/client.ts`

```ts
import { PgClient } from "@effect/sql-pg";
import * as PgDrizzle from "drizzle-orm/effect-postgres";
import { Config, Context, Layer, type Redacted } from "effect";

export interface DatabaseConfig {
  readonly url: Redacted.Redacted<string>;
}

export class Database extends Context.Service<
  Database,
  PgDrizzle.EffectPgDatabase
>()("Database") {}

const pgClientLayer = (config?: Partial<DatabaseConfig>) =>
  config?.url
    ? PgClient.layer({ url: config.url })
    : PgClient.layerConfig({ url: Config.redacted("DATABASE_URL") });

export const layer = (config?: Partial<DatabaseConfig>) =>
  Layer.effect(Database, PgDrizzle.makeWithDefaults()).pipe(
    Layer.provide(pgClientLayer(config)),
  );
```

The `Database` service tag uses effect 4's `Context.Service` (replaces `Context.Tag` from effect 3). The Layer is split: the inner `PgClient` Layer is selected based on whether the caller passed an explicit `Redacted` URL (use `PgClient.layer`) or wants the env fallback (use `PgClient.layerConfig`), since `Config.Wrap` recursively wraps the inner shape and won't accept a plain `Redacted` value as a fallback for a `Config<Redacted>`.

### `drizzle.config.ts`

```ts
import { defineConfig } from "drizzle-kit";

export default defineConfig({
  dialect: "postgresql",
  schema: "./src/schema.ts",
  out: "./drizzle",
  dbCredentials: { url: process.env.DATABASE_URL ?? "" },
});
```

drizzle-kit isn't an Effect runtime, so it reads `process.env` directly. The runtime path uses `Config.redacted("DATABASE_URL")` so both end up reading the same variable.

### `tests/index.spec.ts`

```ts
import { describe, expect, test } from "bun:test";
import { layer, schema } from "../src/index.ts";

describe("{{ packageName }}", () => {
  test("module exports are wired", () => {
    expect(typeof layer).toBe("function");
    expect(schema).toBeDefined();
  });
});
```

PG tests don't open a real connection — running Postgres in CI is out of scope. The smoke test verifies the module compiles, types resolve, and the Layer factory is callable.

## SQLite Variant

### `src/schema.ts`

```ts
import { sql } from "drizzle-orm";
import { integer, sqliteTable, text } from "drizzle-orm/sqlite-core";

export const users = sqliteTable("users", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  email: text("email").notNull().unique(),
  createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
});
```

### `src/client.ts`

```ts
import { Database as BunDatabase } from "bun:sqlite";
import { drizzle, type SQLiteBunDatabase } from "drizzle-orm/bun-sqlite";
import { Config, Context, Effect, Layer } from "effect";
import * as schema from "./schema.ts";

export interface DatabaseConfig {
  readonly filename: string;
}

export class Database extends Context.Service<
  Database,
  SQLiteBunDatabase<typeof schema>
>()("Database") {}

export const layer = (config?: Partial<DatabaseConfig>) =>
  Layer.effect(
    Database,
    Effect.gen(function* () {
      const filename =
        config?.filename ??
        (yield* Config.string("DATABASE_PATH").pipe(
          Config.withDefault("./local.db"),
        ));
      const client = yield* Effect.acquireRelease(
        Effect.sync(() => new BunDatabase(filename)),
        (db) => Effect.sync(() => db.close()),
      );
      return drizzle({ client, schema });
    }),
  );
```

`drizzle-orm/bun-sqlite` does not ship an Effect-aware variant. The Layer opens the `bun:sqlite` Database in `Effect.acquireRelease` and closes it on scope finalization. `Layer.effect` (effect 4) takes an Effect that may use `Scope` and excludes `Scope` from the Layer's requirements, so consumers get a self-managing Layer.

### `src/queries.ts`

```ts
import { eq } from "drizzle-orm";
import { Effect } from "effect";
import { Database } from "./client.ts";
import { users } from "./schema.ts";

export const getUserById = (id: number) =>
  Effect.gen(function* () {
    const db = yield* Database;
    const rows = db.select().from(users).where(eq(users.id, id)).all();
    return rows[0];
  });
```

Drizzle's bun-sqlite driver is synchronous (`'sync'` query effect kind in 1.0.0-rc.1), so query terminals like `.all()`/`.get()` return arrays/values directly rather than Promises. The `Effect.gen` wrapper exists so the function still types as `Effect<...>` and composes with the rest of the runtime; the actual SQL is synchronous.

### `drizzle.config.ts`

```ts
import { defineConfig } from "drizzle-kit";

export default defineConfig({
  dialect: "sqlite",
  schema: "./src/schema.ts",
  out: "./drizzle",
  dbCredentials: { url: process.env.DATABASE_PATH ?? "./local.db" },
});
```

### `tests/index.spec.ts`

```ts
import { describe, expect, test } from "bun:test";
import { Effect } from "effect";
import { Database, getUserById, layer } from "../src/index.ts";

describe("{{ packageName }}", () => {
  test("getUserById returns undefined for missing user", async () => {
    const program = Effect.gen(function* () {
      const db = yield* Database;
      db.run(`CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )`);
      return yield* getUserById(1);
    }).pipe(Effect.provide(layer({ filename: ":memory:" })));

    const result = await Effect.runPromise(program);
    expect(result).toBeUndefined();
  });
});
```

The test creates the table via the underlying drizzle/bun-sqlite client (`db.run`) rather than depending on a generated migration — fresh scaffolds have no migrations until the user runs `db:generate`.

## Workspace Catalog Additions

Add to `package.json#workspaces.catalog` at the repo root in the same commit as the generator templates:

```json
"drizzle-orm": "1.0.0-rc.1",
"drizzle-kit": "1.0.0-rc.1",
"@effect/sql-pg": "4.0.0-beta.59"
```

`drizzle-orm` and `drizzle-kit` are pinned to `1.0.0-rc.1` (exact version) so the two stay coupled at a known-good pair while drizzle is in pre-1.0. `@effect/sql-pg` is pinned to `4.0.0-beta.59` — the exact version of the main `effect` package — because `@effect/*` betas are tightly coupled to `effect` and version skew causes subtle type/runtime incompatibilities. Whenever `effect` is bumped, every `@effect/*` catalog entry must be bumped to the same string in the same change. The pre-existing `@effect/language-service: "latest"` entry pre-dates this rule.

`@effect/sql-drizzle` is intentionally **not** in the catalog: its only published track (0.x) is locked to `effect@^3.21.0` and `drizzle-orm@>=0.43.1 <0.50`. There is no effect 4.x release. drizzle-orm 1.0.0-rc.1 ships its own Effect adapter at `drizzle-orm/effect-postgres`, which is what the PostgreSQL template uses.

`@effect/sql-sqlite-bun` is also not in the catalog: drizzle-orm 1.0.0-rc.1 has no `effect-bun-sqlite` submodule. The SQLite template uses `drizzle-orm/bun-sqlite` directly and wraps the connection in a `Layer.effect` with `Effect.acquireRelease` for lifecycle management.

## Files Modified

- `turbo/generators/effect/index.ts` — extend types, prompts, `templateBase`, `buildActions`.
- `package.json` — add catalog entries.

## Files Added

PostgreSQL templates under `turbo/generators/effect/templates/database/postgresql/`:

- `package.json.hbs`
- `tsconfig.json.hbs`
- `tsconfig.test.json.hbs`
- `biome.json.hbs`
- `CLAUDE.md.hbs`
- `src-index.ts.hbs`
- `src-schema.ts.hbs`
- `src-client.ts.hbs`
- `tests-index.spec.ts.hbs`
- `drizzle.config.ts.hbs`
- `drizzle-gitkeep.hbs` (renders to `drizzle/.gitkeep`)

SQLite templates under `turbo/generators/effect/templates/database/sqlite/`:

- All of the above, plus
- `src-queries.ts.hbs`

## Plop Configuration Sketch

```ts
const DATABASE_COMMON_FILES: ReadonlyArray<readonly [string, string]> = [
  ["package.json.hbs", "package.json"],
  ["tsconfig.json.hbs", "tsconfig.json"],
  ["tsconfig.test.json.hbs", "tsconfig.test.json"],
  ["biome.json.hbs", "biome.json"],
  ["src-index.ts.hbs", "src/index.ts"],
  ["src-schema.ts.hbs", "src/schema.ts"],
  ["src-client.ts.hbs", "src/client.ts"],
  ["tests-index.spec.ts.hbs", "tests/index.spec.ts"],
  ["CLAUDE.md.hbs", "CLAUDE.md"],
  ["drizzle.config.ts.hbs", "drizzle.config.ts"],
  ["drizzle-gitkeep.hbs", "drizzle/.gitkeep"],
];

const DATABASE_SQLITE_EXTRA: ReadonlyArray<readonly [string, string]> = [
  ["src-queries.ts.hbs", "src/queries.ts"],
];

function buildActions(type: ProjectType, engine?: Engine): PlopTypes.ActionType[] {
  const root = `{{ turbo.paths.root }}/${SUBDIR[type]}/{{ packageName }}`;
  const tplBase = templateBase(type, engine);
  let files: ReadonlyArray<readonly [string, string]>;
  if (type === "database") {
    files = engine === "sqlite"
      ? [...DATABASE_COMMON_FILES, ...DATABASE_SQLITE_EXTRA]
      : DATABASE_COMMON_FILES;
  } else if (type === "library") {
    files = [...COMMON_FILES, ...LIBRARY_EXTRA_FILES];
  } else {
    files = COMMON_FILES;
  }
  return [
    ...files.map(([template, output]) => ({
      type: "add",
      path: `${root}/${output}`,
      templateFile: `${tplBase}/${template}`,
    })),
    { type: "symlinkAgentsMd" },
  ];
}
```

## Validation & Success Criteria

For each engine, a fresh `turbo gen effect` choosing `database` + that engine produces a directory where:

1. `bun install` from the repo root completes without error.
2. `cd packages/<name> && bun run check` passes (biome + `tsc --noEmit -p tsconfig.test.json`).
3. `bun run build` produces `dist/` with `index.js`/`index.d.ts`/`client.js`/`client.d.ts`/`schema.js`/`schema.d.ts` (plus `queries.*` for SQLite).
4. `bun test` passes (PG: import-only smoke; SQLite: in-memory `getUserById`).
5. `bun run db:generate` runs without crashing. PG: produces an empty migration since the schema is empty; document this in CLAUDE.md. SQLite: produces an initial migration containing the `users` table.
6. `readlink AGENTS.md` resolves to `CLAUDE.md`.
7. Re-running `turbo gen effect` with the same `packageName` fails on the collision check rather than overwriting.

## Non-Goals

- No `app` variant of database packages (no runnable migration CLI shipped). Apps that own a database are scaffolded as `app` and depend on a `database` package.
- No connection pooling configuration knobs in the template — defaults from `@effect/sql-pg` (PG) and bun:sqlite (SQLite) are sufficient.
- No seed scripts. Adding one is left to package authors.
- No CI integration for spinning up Postgres in tests.
- No multi-engine packages (each package is exactly one of `postgresql` or `sqlite`).
