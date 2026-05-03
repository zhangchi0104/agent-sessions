# Effect Library Generator — Design

## Context

This monorepo (`astat`) uses Turbo with `@turbo/gen` and already has a generator scaffold at `turbo/generators/config.ts` containing an "example" generator. The workspace has Effect v4 beta (`effect@4.0.0-beta.59`) declared in the root `package.json` workspace catalog, alongside `typescript` and `biome`.

The team needs to spin up new Effect libraries quickly with consistent structure, configuration, and AI agent guidance baked in.

## Goal

Add an `effect` generator to `turbo/generators/config.ts` that scaffolds a new Effect library at `packages/<name>/` via `turbo gen effect`. The generator collects a few interactive inputs and emits a complete, buildable package with Effect from the workspace catalog, biome+tsc checks, vitest-style tests, and AI agent guidance files.

Out of scope: CLI apps, HTTP servers, workers, browser/UI packages, or any non-library variants.

## Interactive Prompts

The generator collects:

1. **Package name** (required) — string, validated as kebab-case (lowercase letters, digits, hyphens). Rejects spaces, dots, uppercase, leading/trailing hyphens. Rejects names that collide with an existing directory under `packages/`.
2. **Description** (optional) — short string for `package.json#description` and CLAUDE.md header. Defaults to empty.
3. **Author** (optional) — string for `package.json#author`. Defaults to the value of `git config user.name`, falling back to empty string if git is not configured.

## Generated Package Structure

```
packages/<name>/
├── src/
│   └── index.ts
├── tests/
│   └── index.spec.ts
├── package.json
├── tsconfig.json
├── CLAUDE.md
└── AGENTS.md → symlink to CLAUDE.md
```

## File Specifications

### `package.json`

- `name`: `@astat/<name>` (or matching the existing convention in the monorepo — must be confirmed against existing `packages/*/package.json` during implementation)
- `version`: `"0.0.1"`
- `description`: from prompt (omit field if empty)
- `author`: from prompt (omit field if empty)
- `private`: `true`
- `type`: `"module"`
- `main`/`module`/`exports`: pointing at the build output
- `scripts`:
  - `build`: TypeScript compile via `tsc -p tsconfig.json`
  - `check`: runs `biome check .` and `tsc --noEmit -p tsconfig.json`
  - `test`: runs the workspace's test runner (vitest expected; confirm during implementation by inspecting catalog/devDependencies)
- `dependencies`:
  - `effect`: uses workspace catalog reference (`"catalog:"` in bun)
- `devDependencies`:
  - `typescript`: catalog reference
  - `biome`: catalog reference (if biome is run per-package; otherwise inherit from root)
  - test runner: catalog reference if present

The exact dependency style and `exports` field shape must match the existing `packages/typescript-config/package.json` and `packages/biome-config/package.json` conventions.

### `tsconfig.json`

Extends `@astat/typescript-config/tsconfig.base.json` (or the equivalent name used by the existing `packages/typescript-config` package). Sets:

- `compilerOptions.outDir`: `"dist"`
- `compilerOptions.rootDir`: `"src"`
- `include`: `["src/**/*", "tests/**/*"]`

### `src/index.ts`

Minimal placeholder — a single named export so the package compiles and tests have something to import. Example:

```ts
export const hello = "hello";
```

### `tests/index.spec.ts`

A single trivial test that imports from `../src/index.ts` and asserts the placeholder, so `bun run test` passes immediately on a fresh package. Uses the workspace's test runner API (vitest expected).

### `CLAUDE.md`

Contains:

- Title with package name and the description (if provided)
- An "Effect Best Practices" section (the standard text from the Effect setup reference) with markers `<!-- effect-solutions:start -->` and `<!-- effect-solutions:end -->` so future tooling can update it idempotently

### `AGENTS.md`

A symlink to `CLAUDE.md`. Plop has no built-in symlink action; this is created by a custom plop action that runs `ln -s CLAUDE.md AGENTS.md` inside the new package directory after the other files are written.

## Implementation Approach

### Files Modified
- `turbo/generators/config.ts` — register a new `effect` generator alongside the existing `example` generator.

### Files Added
- `turbo/generators/effect/templates/package.json.hbs`
- `turbo/generators/effect/templates/tsconfig.json.hbs`
- `turbo/generators/effect/templates/src-index.ts.hbs`
- `turbo/generators/effect/templates/tests-index.spec.ts.hbs`
- `turbo/generators/effect/templates/CLAUDE.md.hbs`

### Plop Configuration Sketch

```ts
plop.setGenerator("effect", {
  description: "Scaffold a new Effect library package",
  prompts: [
    { type: "input", name: "packageName", message: "Package name (kebab-case):", validate: validatePackageName },
    { type: "input", name: "description", message: "Description (optional):" },
    { type: "input", name: "author", message: "Author:", default: getGitUserName() },
  ],
  actions: [
    { type: "add", path: "{{ turbo.paths.root }}/packages/{{ packageName }}/package.json", templateFile: "effect/templates/package.json.hbs" },
    { type: "add", path: "{{ turbo.paths.root }}/packages/{{ packageName }}/tsconfig.json", templateFile: "effect/templates/tsconfig.json.hbs" },
    { type: "add", path: "{{ turbo.paths.root }}/packages/{{ packageName }}/src/index.ts", templateFile: "effect/templates/src-index.ts.hbs" },
    { type: "add", path: "{{ turbo.paths.root }}/packages/{{ packageName }}/tests/index.spec.ts", templateFile: "effect/templates/tests-index.spec.ts.hbs" },
    { type: "add", path: "{{ turbo.paths.root }}/packages/{{ packageName }}/CLAUDE.md", templateFile: "effect/templates/CLAUDE.md.hbs" },
    createSymlinkAction, // custom plop action: ln -s CLAUDE.md AGENTS.md inside the package
  ],
});
```

`validatePackageName` checks the regex `/^[a-z0-9]+(-[a-z0-9]+)*$/` and that `packages/<name>` does not already exist on disk.

`getGitUserName` synchronously runs `git config user.name`, returning the trimmed output or `""` on failure.

`createSymlinkAction` is a custom action (function) registered via `plop.setActionType` that uses Node's `fs.symlinkSync(target, path)` with target `"CLAUDE.md"` and path `<package>/AGENTS.md`.

## Validation & Success Criteria

A run of `turbo gen effect` followed by entering a fresh package name produces a directory where all of the following succeed:

1. `bun install` at the workspace root completes without error.
2. `cd packages/<name> && bun run check` passes (biome + `tsc --noEmit`).
3. `cd packages/<name> && bun run build` produces a `dist/` directory.
4. `cd packages/<name> && bun run test` passes (placeholder test passes).
5. `readlink packages/<name>/AGENTS.md` resolves to `CLAUDE.md`.
6. Re-running the generator with the same name fails fast with a validation error rather than overwriting.

## Open Questions / To Confirm During Implementation

These items are deliberately left open because answering them requires inspecting other files in the repo that may have changed since this design was written. The implementation plan should resolve each one before writing templates:

- The exact npm scope used by existing packages (`@astat/<name>`? unscoped? something else?). Inspect `packages/typescript-config/package.json` and `packages/biome-config/package.json`.
- The exact filename of the typescript config to extend (`tsconfig.base.json` vs `tsconfig.tsc.json` vs `tsconfig.bundled.json` — three are present).
- Whether biome is run from each package or from the root (affects whether `biome` belongs in the package's devDependencies).
- The test runner in use (vitest expected, but confirm via root `package.json` and any existing test files).
- The shape of the `exports` field convention used elsewhere in the monorepo.

## Non-Goals

- No support for non-library Effect package types (CLI, HTTP, worker).
- No README.md generation — CLAUDE.md serves as the package's primary documentation entry point for now.
- No Code Connect, no language-service plugin wiring per-package — those live at the workspace root.
- No effect-solutions CLI integration in the generator itself — CLAUDE.md merely references it.
