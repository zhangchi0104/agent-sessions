# Bun Monorepo Template

A Bun-first Turborepo template for TypeScript workspaces. It ships shared
TypeScript and Biome configuration packages plus a custom Turborepo generator
for scaffolding apps, libraries, and Drizzle database packages.

## What's Included

- Bun workspaces for `apps/*`, `packages/*`, and `hooks/*`.
- Turborepo tasks for `build`, `dev`, `lint`, and `check-types`.
- Shared TypeScript configs in `@repo/typescript-config`.
- Shared Biome config in `@repo/biome-config`.
- A custom `scaffold` generator under `turbo/generators`.
- Bun tests for the generator behavior.

## Repository Layout

```txt
.
├── packages/
│   ├── biome-config/         # Shared Biome config package
│   └── typescript-config/    # Shared TypeScript config package
├── turbo/
│   └── generators/           # Turborepo generator source, tests, and templates
├── docs/superpowers/         # Design notes and implementation plans
├── package.json
├── turbo.json
└── bun.lock
```

Generated projects are created in:

- `apps/<name>` for applications
- `packages/<name>` for libraries and database packages

## Requirements

- Bun `1.3.13` or newer compatible with the lockfile
- Node.js `>=18`

Install dependencies:

```sh
bun install
```

## Scripts

Run these from the repository root:

```sh
bun run build
bun run dev
bun run lint
bun run check-types
bun run format
```

The first four scripts delegate to Turborepo. `format` runs Prettier over
TypeScript and Markdown files.

## Scaffolding Projects

Use the custom Turborepo generator:

```sh
bunx turbo gen scaffold
```

The generator prompts for:

- project type: library or app
- library kind: blank or Drizzle database
- database engine: PostgreSQL or SQLite
- app framework: Bun, Hono, Elysia, Nitro, or Astro
- whether to include Effect
- package metadata

Blank libraries and Bun apps are generated entirely from local templates.
Hono, Elysia, Nitro, and Astro apps shell out to their official create commands,
then normalize the generated project for this workspace. When Effect is enabled,
the generator patches the app entrypoint, package metadata, and TypeScript
configuration as needed.

Every generated project also gets an `AGENTS.md` symlink pointing at
`CLAUDE.md`.

## Generator Templates

Templates live in `turbo/generators/scaffold/templates` and are organized by
project shape:

```txt
app/bun/{effect,plain}
library/blank/{effect,plain}
library/database/{postgresql,sqlite}/{effect,plain}
```

Database library templates include Drizzle configuration and schema/client
files. SQLite templates also include a starter `src/queries.ts`.

## Testing

Run the generator tests with Bun:

```sh
bun test turbo/generators/scaffold/index.test.ts
```

The tests cover prompt behavior, template selection, app create commands, and
Effect patch helpers.

## Shared Packages

### `@repo/typescript-config`

Provides reusable TypeScript configuration files:

- `tsconfig.base.json`
- `tsconfig.bundled.json`
- `tsconfig.tsc.json`

### `@repo/biome-config`

Provides the shared Biome configuration exported as `biome.json`.
