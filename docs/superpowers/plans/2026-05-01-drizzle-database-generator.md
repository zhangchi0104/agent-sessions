# Drizzle + Effect Database Generator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing `effect` Turborepo generator with a new `database` package type that scaffolds Drizzle-ORM-on-Effect packages, with separate template variants for PostgreSQL and SQLite (Bun runtime).

**Architecture:** Reuse the dispatch pattern in `turbo/generators/effect/index.ts` — add a third `ProjectType` (`"database"`), introduce an `Engine` union (`"postgresql" | "sqlite"`) gated by a `when:` callback on a new `engine` prompt, replace the static `TEMPLATE_BASE` constant with a `templateBase(type, engine?)` function, and branch `buildActions` to a new file list for the database type. Each engine gets its own template directory with all `.hbs` files (11 for PG, 12 for SQLite). Catalog entries for `drizzle-orm`, `drizzle-kit`, `@effect/sql-pg`, `@effect/sql-sqlite-bun`, and `@effect/sql-drizzle` are added to the root `package.json` once.

**Tech Stack:** Bun 1.3.x, Turborepo 2.x, `@turbo/gen` (plop), `drizzle-orm@1.0.0-beta.22`, `drizzle-kit@1.0.0-beta.22`, `@effect/sql-pg@4.0.0-beta.59`, `@effect/sql-sqlite-bun@4.0.0-beta.59`, `@effect/sql-drizzle@4.0.0-beta.59`, `effect@4.0.0-beta.59`, biome, TypeScript 5.x catalog.

**Project Convention:** All `@effect/*` catalog entries pin to the same exact version string as `effect` (`4.0.0-beta.59` here). Never use `latest` for `@effect/*`.

---

### Task 1: Add workspace catalog entries

**Files:**
- Modify: `package.json` (root, the `workspaces.catalog` block)

- [ ] **Step 1: Edit `package.json` to add five new catalog entries**

The `workspaces.catalog` block currently looks like:

```json
"catalog": {
  "typescript": "^6.0.3",
  "biome": "2.4.13",
  "@biomejs/biome": "2.4.13",
  "effect": "4.0.0-beta.59",
  "@effect/language-service": "latest",
  "@types/bun": "latest"
}
```

Replace it with:

```json
"catalog": {
  "typescript": "^6.0.3",
  "biome": "2.4.13",
  "@biomejs/biome": "2.4.13",
  "effect": "4.0.0-beta.59",
  "@effect/language-service": "latest",
  "@effect/sql-pg": "4.0.0-beta.59",
  "@effect/sql-sqlite-bun": "4.0.0-beta.59",
  "@effect/sql-drizzle": "4.0.0-beta.59",
  "drizzle-orm": "1.0.0-beta.22",
  "drizzle-kit": "1.0.0-beta.22",
  "@types/bun": "latest"
}
```

The `@effect/*` versions must match `effect`'s `4.0.0-beta.59` per project convention — they are tightly coupled and skew breaks types/runtime.

- [ ] **Step 2: Run `bun install` to resolve the catalog**

Run: `bun install`

Expected: install completes without error. The new entries are not yet referenced by any workspace package, so no extra packages are downloaded — but bun parses the catalog block on every install, so a typo or unresolvable version would fail here.

- [ ] **Step 3: Commit**

```bash
git add package.json bun.lock
git commit -m "chore(catalog): add drizzle and @effect/sql-* entries"
```

---

### Task 2: Add PostgreSQL templates

**Files:**
- Create: `turbo/generators/effect/templates/database/postgresql/package.json.hbs`
- Create: `turbo/generators/effect/templates/database/postgresql/tsconfig.json.hbs`
- Create: `turbo/generators/effect/templates/database/postgresql/tsconfig.test.json.hbs`
- Create: `turbo/generators/effect/templates/database/postgresql/biome.json.hbs`
- Create: `turbo/generators/effect/templates/database/postgresql/CLAUDE.md.hbs`
- Create: `turbo/generators/effect/templates/database/postgresql/src-index.ts.hbs`
- Create: `turbo/generators/effect/templates/database/postgresql/src-schema.ts.hbs`
- Create: `turbo/generators/effect/templates/database/postgresql/src-client.ts.hbs`
- Create: `turbo/generators/effect/templates/database/postgresql/tests-index.spec.ts.hbs`
- Create: `turbo/generators/effect/templates/database/postgresql/drizzle.config.ts.hbs`
- Create: `turbo/generators/effect/templates/database/postgresql/drizzle-gitkeep.hbs`

- [ ] **Step 1: Create `package.json.hbs`**

```hbs
{
  "name": "@repo/{{ packageName }}",
  "version": "0.0.1",{{#if description}}
  "description": "{{ description }}",{{/if}}{{#if author}}
  "author": "{{ author }}",{{/if}}
  "private": true,
  "type": "module",
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "default": "./dist/index.js"
    }
  },
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "files": [
    "dist",
    "drizzle"
  ],
  "scripts": {
    "build": "tsc --build",
    "check": "biome check . && tsc --noEmit -p tsconfig.test.json",
    "test": "bun test",
    "db:generate": "drizzle-kit generate",
    "db:migrate": "drizzle-kit migrate",
    "db:push": "drizzle-kit push",
    "db:studio": "drizzle-kit studio",
    "prepare": "effect-language-service patch"
  },
  "dependencies": {
    "effect": "catalog:",
    "drizzle-orm": "catalog:",
    "@effect/sql-pg": "catalog:",
    "@effect/sql-drizzle": "catalog:"
  },
  "devDependencies": {
    "@biomejs/biome": "catalog:",
    "@effect/language-service": "catalog:",
    "@repo/biome-config": "workspace:*",
    "@repo/typescript-config": "workspace:*",
    "@types/bun": "catalog:",
    "drizzle-kit": "catalog:",
    "typescript": "catalog:"
  }
}
```

- [ ] **Step 2: Create `tsconfig.json.hbs`**

```hbs
{
  "$schema": "./node_modules/@effect/language-service/schema.json",
  "extends": "@repo/typescript-config/tsconfig.base.json",
  "compilerOptions": {
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "./dist",
    "rootDir": "./src",
    "plugins": [{ "name": "@effect/language-service" }]
  },
  "include": ["src/**/*"],
  "exclude": ["dist", "node_modules"]
}
```

- [ ] **Step 3: Create `tsconfig.test.json.hbs`**

```hbs
{
  "$schema": "./node_modules/@effect/language-service/schema.json",
  "extends": "@repo/typescript-config/tsconfig.base.json",
  "compilerOptions": {
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "noEmit": true,
    "composite": false,
    "declaration": false,
    "declarationMap": false,
    "rootDir": ".",
    "plugins": [{ "name": "@effect/language-service" }]
  },
  "include": ["src/**/*", "tests/**/*"],
  "exclude": ["dist", "node_modules"]
}
```

- [ ] **Step 4: Create `biome.json.hbs`**

```hbs
{
  "$schema": "./node_modules/@biomejs/biome/configuration_schema.json",
  "extends": ["@repo/biome-config/biome.json"],
  "files": {
    "includes": ["src/**", "tests/**", "*.json", "*.ts"]
  }
}
```

- [ ] **Step 5: Create `CLAUDE.md.hbs`**

```hbs
# @repo/{{ packageName }}

{{#if description}}{{ description }}{{else}}A Drizzle + Effect (PostgreSQL) database package.{{/if}}

<!-- effect-solutions:start -->
## Effect Best Practices

**IMPORTANT:** Always consult effect-solutions before writing Effect code.

1. Run `effect-solutions list` to see available guides
2. Run `effect-solutions show <topic>...` for relevant patterns (supports multiple topics)
3. Search `~/.local/share/effect-solutions/effect` for real implementations

Topics: quick-start, project-setup, tsconfig, basics, services-and-layers, data-modeling, error-handling, config, testing, cli.

Never guess at Effect patterns - check the guide first.
<!-- effect-solutions:end -->

## Environment

- `DATABASE_URL` — required at runtime when `layer()` is called without a `url`. Read via `Config.redacted("DATABASE_URL")`. drizzle-kit reads the same variable directly via `process.env`.

## Scripts

- `bun run build` — TypeScript build to `dist/`
- `bun run check` — biome lint + `tsc --noEmit -p tsconfig.test.json`
- `bun test` — runs an import-only smoke test (no real database connection)
- `bun run db:generate` — generate migrations from `src/schema.ts` into `drizzle/`
- `bun run db:migrate` — apply pending migrations against `DATABASE_URL`
- `bun run db:push` — push schema directly (development only)
- `bun run db:studio` — open Drizzle Studio against `DATABASE_URL`

## Adding tables

Edit `src/schema.ts` using `drizzle-orm/pg-core`, then run `bun run db:generate`.
```

- [ ] **Step 6: Create `src-index.ts.hbs`**

```hbs
export * as schema from "./schema.ts";
export { layer, type DatabaseConfig } from "./client.ts";
```

- [ ] **Step 7: Create `src-schema.ts.hbs`**

```hbs
// Add Drizzle pg-core tables here, then run `bun run db:generate`.
//
// import { pgTable, serial, text, timestamp } from "drizzle-orm/pg-core";
//
// export const users = pgTable("users", {
//   id: serial("id").primaryKey(),
//   email: text("email").notNull().unique(),
//   createdAt: timestamp("created_at").notNull().defaultNow(),
// });
```

- [ ] **Step 8: Create `src-client.ts.hbs`**

```hbs
import { PgClient } from "@effect/sql-pg";
import { PgDrizzle } from "@effect/sql-drizzle/Pg";
import { Config, Layer, type Redacted } from "effect";

export interface DatabaseConfig {
  readonly url: Redacted.Redacted<string>;
}

export const layer = (config?: Partial<DatabaseConfig>) =>
  PgDrizzle.layer.pipe(
    Layer.provideMerge(
      PgClient.layerConfig({
        url: config?.url ?? Config.redacted("DATABASE_URL"),
      }),
    ),
  );
```

- [ ] **Step 9: Create `tests-index.spec.ts.hbs`**

```hbs
import { describe, expect, test } from "bun:test";
import { layer, schema } from "../src/index.ts";

describe("{{ packageName }}", () => {
  test("module exports are wired", () => {
    expect(typeof layer).toBe("function");
    expect(schema).toBeDefined();
  });
});
```

- [ ] **Step 10: Create `drizzle.config.ts.hbs`**

```hbs
import { defineConfig } from "drizzle-kit";

export default defineConfig({
  dialect: "postgresql",
  schema: "./src/schema.ts",
  out: "./drizzle",
  dbCredentials: { url: process.env.DATABASE_URL ?? "" },
});
```

- [ ] **Step 11: Create `drizzle-gitkeep.hbs`** (empty file — zero bytes)

The file must exist but contain nothing. After creating it, verify:

Run: `wc -c turbo/generators/effect/templates/database/postgresql/drizzle-gitkeep.hbs`
Expected: `0 turbo/generators/effect/templates/database/postgresql/drizzle-gitkeep.hbs`

- [ ] **Step 12: Commit**

```bash
git add turbo/generators/effect/templates/database/postgresql/
git commit -m "feat(generators): add postgresql database templates"
```

---

### Task 3: Add SQLite templates

**Files:**
- Create: `turbo/generators/effect/templates/database/sqlite/package.json.hbs`
- Create: `turbo/generators/effect/templates/database/sqlite/tsconfig.json.hbs`
- Create: `turbo/generators/effect/templates/database/sqlite/tsconfig.test.json.hbs`
- Create: `turbo/generators/effect/templates/database/sqlite/biome.json.hbs`
- Create: `turbo/generators/effect/templates/database/sqlite/CLAUDE.md.hbs`
- Create: `turbo/generators/effect/templates/database/sqlite/src-index.ts.hbs`
- Create: `turbo/generators/effect/templates/database/sqlite/src-schema.ts.hbs`
- Create: `turbo/generators/effect/templates/database/sqlite/src-client.ts.hbs`
- Create: `turbo/generators/effect/templates/database/sqlite/src-queries.ts.hbs`
- Create: `turbo/generators/effect/templates/database/sqlite/tests-index.spec.ts.hbs`
- Create: `turbo/generators/effect/templates/database/sqlite/drizzle.config.ts.hbs`
- Create: `turbo/generators/effect/templates/database/sqlite/drizzle-gitkeep.hbs`

- [ ] **Step 1: Create `package.json.hbs`**

```hbs
{
  "name": "@repo/{{ packageName }}",
  "version": "0.0.1",{{#if description}}
  "description": "{{ description }}",{{/if}}{{#if author}}
  "author": "{{ author }}",{{/if}}
  "private": true,
  "type": "module",
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "default": "./dist/index.js"
    }
  },
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "files": [
    "dist",
    "drizzle"
  ],
  "scripts": {
    "build": "tsc --build",
    "check": "biome check . && tsc --noEmit -p tsconfig.test.json",
    "test": "bun test",
    "db:generate": "drizzle-kit generate",
    "db:migrate": "drizzle-kit migrate",
    "db:push": "drizzle-kit push",
    "db:studio": "drizzle-kit studio",
    "prepare": "effect-language-service patch"
  },
  "dependencies": {
    "effect": "catalog:",
    "drizzle-orm": "catalog:",
    "@effect/sql-sqlite-bun": "catalog:",
    "@effect/sql-drizzle": "catalog:"
  },
  "devDependencies": {
    "@biomejs/biome": "catalog:",
    "@effect/language-service": "catalog:",
    "@repo/biome-config": "workspace:*",
    "@repo/typescript-config": "workspace:*",
    "@types/bun": "catalog:",
    "drizzle-kit": "catalog:",
    "typescript": "catalog:"
  }
}
```

- [ ] **Step 2: Create `tsconfig.json.hbs`** — identical to the PG variant

```hbs
{
  "$schema": "./node_modules/@effect/language-service/schema.json",
  "extends": "@repo/typescript-config/tsconfig.base.json",
  "compilerOptions": {
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "./dist",
    "rootDir": "./src",
    "plugins": [{ "name": "@effect/language-service" }]
  },
  "include": ["src/**/*"],
  "exclude": ["dist", "node_modules"]
}
```

- [ ] **Step 3: Create `tsconfig.test.json.hbs`** — identical to the PG variant

```hbs
{
  "$schema": "./node_modules/@effect/language-service/schema.json",
  "extends": "@repo/typescript-config/tsconfig.base.json",
  "compilerOptions": {
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "noEmit": true,
    "composite": false,
    "declaration": false,
    "declarationMap": false,
    "rootDir": ".",
    "plugins": [{ "name": "@effect/language-service" }]
  },
  "include": ["src/**/*", "tests/**/*"],
  "exclude": ["dist", "node_modules"]
}
```

- [ ] **Step 4: Create `biome.json.hbs`** — identical to the PG variant

```hbs
{
  "$schema": "./node_modules/@biomejs/biome/configuration_schema.json",
  "extends": ["@repo/biome-config/biome.json"],
  "files": {
    "includes": ["src/**", "tests/**", "*.json", "*.ts"]
  }
}
```

- [ ] **Step 5: Create `CLAUDE.md.hbs`**

```hbs
# @repo/{{ packageName }}

{{#if description}}{{ description }}{{else}}A Drizzle + Effect (SQLite/Bun) database package.{{/if}}

<!-- effect-solutions:start -->
## Effect Best Practices

**IMPORTANT:** Always consult effect-solutions before writing Effect code.

1. Run `effect-solutions list` to see available guides
2. Run `effect-solutions show <topic>...` for relevant patterns (supports multiple topics)
3. Search `~/.local/share/effect-solutions/effect` for real implementations

Topics: quick-start, project-setup, tsconfig, basics, services-and-layers, data-modeling, error-handling, config, testing, cli.

Never guess at Effect patterns - check the guide first.
<!-- effect-solutions:end -->

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
```

- [ ] **Step 6: Create `src-index.ts.hbs`**

```hbs
export * as schema from "./schema.ts";
export { layer, type DatabaseConfig } from "./client.ts";
export { getUserById } from "./queries.ts";
```

- [ ] **Step 7: Create `src-schema.ts.hbs`**

```hbs
import { sql } from "drizzle-orm";
import { integer, sqliteTable, text } from "drizzle-orm/sqlite-core";

export const users = sqliteTable("users", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  email: text("email").notNull().unique(),
  createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
});
```

- [ ] **Step 8: Create `src-client.ts.hbs`**

```hbs
import { SqliteClient } from "@effect/sql-sqlite-bun";
import { SqliteDrizzle } from "@effect/sql-drizzle/Sqlite";
import { Config, Layer } from "effect";

export interface DatabaseConfig {
  readonly filename: string;
}

export const layer = (config?: Partial<DatabaseConfig>) =>
  SqliteDrizzle.layer.pipe(
    Layer.provideMerge(
      SqliteClient.layerConfig({
        filename:
          config?.filename ??
          Config.string("DATABASE_PATH").pipe(Config.withDefault("./local.db")),
      }),
    ),
  );
```

- [ ] **Step 9: Create `src-queries.ts.hbs`**

```hbs
import { eq } from "drizzle-orm";
import { SqliteDrizzle } from "@effect/sql-drizzle/Sqlite";
import { Effect } from "effect";
import { users } from "./schema.ts";

export const getUserById = (id: number) =>
  Effect.gen(function* () {
    const db = yield* SqliteDrizzle;
    const rows = yield* db.select().from(users).where(eq(users.id, id));
    return rows[0];
  });
```

- [ ] **Step 10: Create `tests-index.spec.ts.hbs`**

```hbs
import { describe, expect, test } from "bun:test";
import { SqliteClient } from "@effect/sql-sqlite-bun";
import { Effect } from "effect";
import { getUserById, layer } from "../src/index.ts";

const inMemory = layer({ filename: ":memory:" });

describe("{{ packageName }}", () => {
  test("getUserById returns undefined for missing user", async () => {
    const program = Effect.gen(function* () {
      const sqlClient = yield* SqliteClient.SqliteClient;
      yield* sqlClient`CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )`;
      return yield* getUserById(1);
    }).pipe(Effect.provide(inMemory));

    const result = await Effect.runPromise(program);
    expect(result).toBeUndefined();
  });
});
```

- [ ] **Step 11: Create `drizzle.config.ts.hbs`**

```hbs
import { defineConfig } from "drizzle-kit";

export default defineConfig({
  dialect: "sqlite",
  schema: "./src/schema.ts",
  out: "./drizzle",
  dbCredentials: { url: process.env.DATABASE_PATH ?? "./local.db" },
});
```

- [ ] **Step 12: Create `drizzle-gitkeep.hbs`** (empty file — zero bytes)

Run: `wc -c turbo/generators/effect/templates/database/sqlite/drizzle-gitkeep.hbs`
Expected: `0 turbo/generators/effect/templates/database/sqlite/drizzle-gitkeep.hbs`

- [ ] **Step 13: Commit**

```bash
git add turbo/generators/effect/templates/database/sqlite/
git commit -m "feat(generators): add sqlite database templates"
```

---

### Task 4: Update the generator module

**Files:**
- Modify: `turbo/generators/effect/index.ts`

- [ ] **Step 1: Replace the entire contents of `turbo/generators/effect/index.ts`**

```ts
import { execSync } from "node:child_process";
import { existsSync, symlinkSync } from "node:fs";
import path from "node:path";
import type { PlopTypes } from "@turbo/gen";

const KEBAB_CASE = /^[a-z0-9]+(-[a-z0-9]+)*$/;

type ProjectType = "library" | "app" | "database";
type Engine = "postgresql" | "sqlite";

interface EffectAnswers {
  type: ProjectType;
  engine?: Engine;
  packageName: string;
  description: string;
  author: string;
}

const SUBDIR: Record<ProjectType, string> = {
  library: "packages",
  app: "apps",
  database: "packages",
};

function templateBase(type: ProjectType, engine?: Engine): string {
  if (type === "database") {
    if (!engine) throw new Error("engine is required when type is 'database'");
    return `effect/templates/database/${engine}`;
  }
  if (type === "app") return "effect/templates/app";
  return "effect/templates";
}

const COMMON_FILES: ReadonlyArray<readonly [string, string]> = [
  ["package.json.hbs", "package.json"],
  ["tsconfig.json.hbs", "tsconfig.json"],
  ["biome.json.hbs", "biome.json"],
  ["src-index.ts.hbs", "src/index.ts"],
  ["CLAUDE.md.hbs", "CLAUDE.md"],
];

const LIBRARY_EXTRA_FILES: ReadonlyArray<readonly [string, string]> = [
  ["tsconfig.test.json.hbs", "tsconfig.test.json"],
  ["tests-index.spec.ts.hbs", "tests/index.spec.ts"],
];

const DATABASE_COMMON_FILES: ReadonlyArray<readonly [string, string]> = [
  ["package.json.hbs", "package.json"],
  ["tsconfig.json.hbs", "tsconfig.json"],
  ["tsconfig.test.json.hbs", "tsconfig.test.json"],
  ["biome.json.hbs", "biome.json"],
  ["CLAUDE.md.hbs", "CLAUDE.md"],
  ["src-index.ts.hbs", "src/index.ts"],
  ["src-schema.ts.hbs", "src/schema.ts"],
  ["src-client.ts.hbs", "src/client.ts"],
  ["tests-index.spec.ts.hbs", "tests/index.spec.ts"],
  ["drizzle.config.ts.hbs", "drizzle.config.ts"],
  ["drizzle-gitkeep.hbs", "drizzle/.gitkeep"],
];

const DATABASE_SQLITE_EXTRA: ReadonlyArray<readonly [string, string]> = [
  ["src-queries.ts.hbs", "src/queries.ts"],
];

function validateName(input: string, workspaceRoot: string, type: ProjectType): true | string {
  if (!input) return "name is required";
  if (!KEBAB_CASE.test(input)) {
    return "name must be kebab-case (lowercase letters, digits, hyphens; no leading/trailing hyphens)";
  }
  if (existsSync(path.join(workspaceRoot, SUBDIR[type], input))) {
    return `${SUBDIR[type]}/${input} already exists`;
  }
  return true;
}

function getGitUserName(): string {
  try {
    return execSync("git config user.name", { encoding: "utf8" }).trim();
  } catch {
    return "";
  }
}

export function registerEffectGenerator(plop: PlopTypes.NodePlopAPI): void {
  const workspaceRoot = plop.getDestBasePath();

  plop.setActionType("symlinkAgentsMd", (rawAnswers) => {
    const answers = rawAnswers as EffectAnswers;
    const dir = path.join(workspaceRoot, SUBDIR[answers.type], answers.packageName);
    symlinkSync("CLAUDE.md", path.join(dir, "AGENTS.md"));
    return `symlinked AGENTS.md -> CLAUDE.md in ${SUBDIR[answers.type]}/${answers.packageName}`;
  });

  plop.setGenerator("effect", {
    description: "Scaffold a new Effect v4 library, application, or database package",
    prompts: [
      {
        type: "list",
        name: "type",
        message: "What are you scaffolding?",
        choices: [
          { name: "library (packages/<name>)", value: "library" },
          { name: "app (apps/<name>)", value: "app" },
          { name: "database (packages/<name>, Drizzle + Effect SQL)", value: "database" },
        ],
        default: "library",
      },
      {
        type: "list",
        name: "engine",
        message: "Which database engine?",
        choices: [
          { name: "PostgreSQL (@effect/sql-pg + drizzle-orm/pg-core)", value: "postgresql" },
          { name: "SQLite via Bun (@effect/sql-sqlite-bun + drizzle-orm/sqlite-core)", value: "sqlite" },
        ],
        when: (answers: Pick<EffectAnswers, "type">) => answers.type === "database",
      },
      {
        type: "input",
        name: "packageName",
        message: (answers: Pick<EffectAnswers, "type">) =>
          `Name (kebab-case, becomes ${SUBDIR[answers.type]}/<name>):`,
        validate: (input: string, answers: Pick<EffectAnswers, "type">) =>
          validateName(input, workspaceRoot, answers.type),
      },
      {
        type: "input",
        name: "description",
        message: "Description (optional):",
        default: "",
      },
      {
        type: "input",
        name: "author",
        message: "Author:",
        default: getGitUserName,
      },
    ],
    actions: (data) => {
      if (!data) return [];
      const { type, engine } = data as Pick<EffectAnswers, "type" | "engine">;
      return buildActions(type, engine);
    },
  });
}

function buildActions(type: ProjectType, engine?: Engine): PlopTypes.ActionType[] {
  const root = `{{ turbo.paths.root }}/${SUBDIR[type]}/{{ packageName }}`;
  const tplBase = templateBase(type, engine);
  let files: ReadonlyArray<readonly [string, string]>;
  if (type === "database") {
    files =
      engine === "sqlite"
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

- [ ] **Step 2: Sanity-check that the generator file at least parses**

Run: `bun --print "import('./turbo/generators/effect/index.ts').then(() => 'ok')"`

Expected: prints `ok` (a Promise resolves). If a syntax/import error fires, fix it before continuing.

- [ ] **Step 3: Verify the generator lists the new prompts**

Run: `bun turbo gen effect --help` (best-effort — turbo may simply launch the prompt UI; if it does, press Ctrl+C). The point of this step is to confirm the generator loads without throwing. Any thrown error here means the file has a runtime issue.

Expected: either help text appears, or the interactive prompt starts (in which case abort it). No stack trace.

- [ ] **Step 4: Commit**

```bash
git add turbo/generators/effect/index.ts
git commit -m "feat(generators): add database type with postgresql/sqlite engines"
```

---

### Task 5: End-to-end verification — PostgreSQL scaffold

This task scaffolds a temporary database package, runs its full check/build/test cycle, then deletes it. Nothing is committed; the goal is to prove the generator produces a working package.

**Files:**
- Temporary: `packages/tmp-db-pg/` (created and deleted within this task)

- [ ] **Step 1: Run the generator non-interactively**

Plop accepts `--<promptName>=<value>` flags that bypass interactive prompts. Run:

```bash
bun turbo gen effect --type=database --engine=postgresql --packageName=tmp-db-pg --description= --author=
```

Expected: plop prints `add` lines for each scaffolded file plus the `symlinked AGENTS.md -> CLAUDE.md ...` line. New directory at `packages/tmp-db-pg/` exists.

If the flag form doesn't work in your turbo version, fall back to piping answers via stdin:

```bash
printf 'database\npostgresql\ntmp-db-pg\n\n\n' | bun turbo gen effect
```

- [ ] **Step 2: Verify the AGENTS.md symlink**

Run: `readlink packages/tmp-db-pg/AGENTS.md`
Expected: `CLAUDE.md`

- [ ] **Step 3: Install the new package's dependencies**

Run (from repo root): `bun install`
Expected: succeeds; resolves `drizzle-orm@1.0.0-beta.22`, `drizzle-kit@1.0.0-beta.22`, `@effect/sql-pg@4.0.0-beta.59`, `@effect/sql-drizzle@4.0.0-beta.59`.

- [ ] **Step 4: Run `bun run check` inside the new package**

Run: `cd packages/tmp-db-pg && bun run check`
Expected: biome reports no findings; `tsc --noEmit -p tsconfig.test.json` exits 0. If TypeScript complains about `@effect/sql-drizzle/Pg` not resolving, inspect `node_modules/@effect/sql-drizzle/package.json` to find the actual export path (e.g., it may be `@effect/sql-drizzle` for a barrel) and update the templates accordingly. Re-run.

- [ ] **Step 5: Run `bun run build`**

Run: `cd packages/tmp-db-pg && bun run build`
Expected: `dist/` is created with `index.js`, `index.d.ts`, `client.js`, `client.d.ts`, `schema.js`, `schema.d.ts`. No errors.

- [ ] **Step 6: Run the smoke test**

Run: `cd packages/tmp-db-pg && bun test`
Expected: 1 test passes — `module exports are wired`.

- [ ] **Step 7: Run `bun run db:generate`**

Run: `cd packages/tmp-db-pg && bun run db:generate`
Expected: drizzle-kit reports `No schema changes` (or similar) because `src/schema.ts` only contains commented-out tables. No file is written into `drizzle/`. Exit 0.

- [ ] **Step 8: Delete the temporary package**

Run from repo root:
```bash
rm -rf packages/tmp-db-pg
bun install
```

Expected: directory removed; bun reconciles the workspace and removes the now-orphaned dependency entries from `bun.lock`.

- [ ] **Step 9: Verify no stray changes are uncommitted**

Run: `git status --short`
Expected: only `bun.lock` may show as modified due to the install/uninstall cycle. If the lockfile churn is benign, restore it:

```bash
git checkout -- bun.lock
```

If anything else is dirty, investigate before continuing.

---

### Task 6: End-to-end verification — SQLite scaffold

**Files:**
- Temporary: `packages/tmp-db-sqlite/` (created and deleted within this task)

- [ ] **Step 1: Run the generator non-interactively**

```bash
bun turbo gen effect --type=database --engine=sqlite --packageName=tmp-db-sqlite --description= --author=
```

Fallback (interactive): `printf 'database\nsqlite\ntmp-db-sqlite\n\n\n' | bun turbo gen effect`

Expected: scaffolding succeeds; `packages/tmp-db-sqlite/` exists with `src/queries.ts` present (in addition to the database common files).

- [ ] **Step 2: Verify the AGENTS.md symlink**

Run: `readlink packages/tmp-db-sqlite/AGENTS.md`
Expected: `CLAUDE.md`

- [ ] **Step 3: Install dependencies**

Run: `bun install`
Expected: resolves `@effect/sql-sqlite-bun@4.0.0-beta.59` (in addition to the previously-cached drizzle and effect/sql-drizzle).

- [ ] **Step 4: Run `bun run check`**

Run: `cd packages/tmp-db-sqlite && bun run check`
Expected: biome + tsc both pass. If `@effect/sql-drizzle/Sqlite` doesn't resolve, inspect the installed package's `package.json#exports` and update the templates.

- [ ] **Step 5: Run `bun run build`**

Run: `cd packages/tmp-db-sqlite && bun run build`
Expected: `dist/` contains `index.js`, `index.d.ts`, `client.js`, `client.d.ts`, `schema.js`, `schema.d.ts`, `queries.js`, `queries.d.ts`.

- [ ] **Step 6: Run the in-memory smoke test**

Run: `cd packages/tmp-db-sqlite && bun test`
Expected: 1 test passes — `getUserById returns undefined for missing user`. Test runtime should be under one second.

- [ ] **Step 7: Run `bun run db:generate`**

Run: `cd packages/tmp-db-sqlite && bun run db:generate`
Expected: drizzle-kit reads `src/schema.ts` (with the `users` table) and writes an initial migration into `drizzle/` (e.g., `drizzle/0000_<name>.sql`) plus a meta directory. Exit 0.

- [ ] **Step 8: Verify the migration file exists**

Run: `ls packages/tmp-db-sqlite/drizzle/`
Expected: at least one `.sql` file plus a `meta/` directory.

- [ ] **Step 9: Delete the temporary package**

```bash
rm -rf packages/tmp-db-sqlite
bun install
git checkout -- bun.lock
```

Expected: directory removed; lockfile restored to the committed state.

- [ ] **Step 10: Final repo cleanliness check**

Run: `git status --short`
Expected: empty output. If anything is dirty, investigate before declaring the plan complete.

---

## Self-Review Notes

The plan covers each section of the spec:

- Generator architecture (Spec §"Generator Module Changes") — Task 4.
- Prompts (Spec §"Interactive Prompts") — Task 4 (single source of truth for the prompt list).
- Generated package layout (Spec §"Generated Package Layout") — Tasks 2, 3.
- Common file specifications and engine-specific files — Tasks 2, 3 with full template content.
- Workspace catalog additions (Spec §"Workspace Catalog Additions") — Task 1.
- Validation & success criteria (Spec §"Validation & Success Criteria") — Tasks 5, 6.

No placeholders. Every code-bearing step ships full content. Type/import names (`PgClient`, `PgDrizzle`, `SqliteClient`, `SqliteDrizzle`, `Layer.provideMerge`, `Config.redacted`, `Config.string`, `Config.withDefault`, `DatabaseConfig`, `layer`, `getUserById`) are consistent across templates and the verification tasks. The two verification tasks include fallback instructions for `@effect/sql-drizzle/Pg`/`@effect/sql-drizzle/Sqlite` import paths in case the actual installed package surfaces a different export shape — the API surface should be verified against the real `node_modules` during Tasks 5/6.
