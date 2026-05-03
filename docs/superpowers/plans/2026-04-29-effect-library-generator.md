# Effect Library Generator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an interactive `turbo gen effect` generator that scaffolds a new Effect v4 beta library at `packages/<name>/` with consistent structure, TypeScript config inheritance, biome+tsc checks, bun test setup, and AGENTS.md → CLAUDE.md symlink.

**Architecture:** The generator lives in `turbo/generators/effect/` as its own module (separate from the existing `example` generator). It exports a registration function called by `turbo/generators/config.ts`. Templates are individual `.hbs` files; the generator file holds prompts, validation, the symlink custom action, and the action list. A trivial integration test exercises the generated package end-to-end (build, check, test).

**Tech Stack:**
- Node + TypeScript (the generator runs under `@turbo/gen` 2.9.6)
- Plop API exposed by `@turbo/gen`
- Handlebars templates
- Bun 1.3.13 (workspace package manager + test runner)
- TypeScript catalog (^6.0.3), biome (2.4.13), effect (4.0.0-beta.59)

---

## Resolved Spec Open Questions

The spec listed several items to confirm during implementation. Resolved by inspecting the repo:

- **npm scope:** `@repo/` (from `packages/typescript-config/package.json` and `packages/biome-config/package.json`).
- **TypeScript config to extend:** `@repo/typescript-config/tsconfig.base.json`. The `tsconfig.tsc.json` is just a fragment (`module: NodeNext`); the generated package will set its `module` directly.
- **Biome:** `packages/biome-config` currently has only a `package.json` shell — no shared config exists yet. The generated package will run biome via `bunx biome check .` against its own files. If a shared biome config is added later it can be wired in by editing the template.
- **Test runner:** `bun test` (built-in). The catalog contains no vitest; `tsconfig.base.json` has `"types": ["bun"]`; bun discovers `*.spec.ts` automatically.
- **`exports` field shape:** No existing library precedent in this repo. Use the standard dual entry pattern: `"exports": { ".": { "types": "./dist/index.d.ts", "default": "./dist/index.js" } }`.
- **Workspace catalog reference syntax in bun:** `"effect": "catalog:"` (bun reads the named entry from the root `workspaces.catalog`).

---

## File Structure

**New files:**

- `turbo/generators/effect/index.ts` — generator registration function, prompts, validator, symlink action, action list.
- `turbo/generators/effect/templates/package.json.hbs` — package.json template.
- `turbo/generators/effect/templates/tsconfig.json.hbs` — tsconfig template.
- `turbo/generators/effect/templates/src-index.ts.hbs` — `src/index.ts` placeholder.
- `turbo/generators/effect/templates/tests-index.spec.ts.hbs` — `tests/index.spec.ts` placeholder.
- `turbo/generators/effect/templates/CLAUDE.md.hbs` — CLAUDE.md with Effect best-practices block.

**Modified files:**

- `turbo/generators/config.ts` — import and call the effect generator's registration function alongside the existing example generator.

**Why this split:** keeps the existing `example` generator untouched, isolates effect-specific logic, and lets each template be edited without scrolling through a large config file. If more generators are added later (CLI, HTTP), they each get their own subdirectory under `turbo/generators/`.

---

## Task 1: Scaffold the effect generator module skeleton

**Files:**
- Create: `turbo/generators/effect/index.ts`
- Create: `turbo/generators/effect/templates/.gitkeep`

- [ ] **Step 1: Create the templates directory placeholder**

```bash
mkdir -p turbo/generators/effect/templates
touch turbo/generators/effect/templates/.gitkeep
```

- [ ] **Step 2: Create the generator skeleton at `turbo/generators/effect/index.ts`**

```ts
import type { PlopTypes } from "@turbo/gen";

export function registerEffectGenerator(plop: PlopTypes.NodePlopAPI): void {
  plop.setGenerator("effect", {
    description: "Scaffold a new Effect v4 library package under packages/<name>/",
    prompts: [],
    actions: [],
  });
}
```

- [ ] **Step 3: Verify TypeScript accepts the new file**

Run: `bunx tsc --noEmit -p turbo/generators/tsconfig.json 2>/dev/null || bunx tsc --noEmit turbo/generators/effect/index.ts turbo/generators/config.ts`

Expected: No errors. (If `turbo/generators/tsconfig.json` doesn't exist, the second command tells the compiler what files to check directly.)

- [ ] **Step 4: Commit**

```bash
git add turbo/generators/effect/index.ts turbo/generators/effect/templates/.gitkeep
git commit -m "feat(generators): scaffold effect generator module skeleton"
```

---

## Task 2: Wire the effect generator into config.ts

**Files:**
- Modify: `turbo/generators/config.ts`

- [ ] **Step 1: Replace `turbo/generators/config.ts` with the wiring**

Read the file first, then replace its contents with:

```ts
import type { PlopTypes } from "@turbo/gen";
import { registerEffectGenerator } from "./effect/index.ts";

export default function generator(plop: PlopTypes.NodePlopAPI): void {
  plop.setGenerator("example", {
    description:
      "An example Turborepo generator - creates a new file at the root of the project",
    prompts: [
      {
        type: "input",
        name: "file",
        message: "What is the name of the new file to create?",
        validate: (input: string) => {
          if (input.includes(".")) {
            return "file name cannot include an extension";
          }
          if (input.includes(" ")) {
            return "file name cannot include spaces";
          }
          if (!input) {
            return "file name is required";
          }
          return true;
        },
      },
      {
        type: "list",
        name: "type",
        message: "What type of file should be created?",
        choices: [".md", ".txt"],
      },
      {
        type: "input",
        name: "title",
        message: "What should be the title of the new file?",
      },
    ],
    actions: [
      {
        type: "add",
        path: "{{ turbo.paths.root }}/{{ dashCase file }}{{ type }}",
        templateFile: "templates/turborepo-generators.hbs",
      },
    ],
  });

  registerEffectGenerator(plop);
}
```

- [ ] **Step 2: Verify the generator is discovered**

Run: `bunx turbo gen --help 2>&1 | head -50`

Expected: output includes both `example` and `effect` generator names. (Exact format depends on turbo version; you should see `effect` listed.)

- [ ] **Step 3: Commit**

```bash
git add turbo/generators/config.ts
git commit -m "feat(generators): register effect generator alongside example"
```

---

## Task 3: Add package name validation and prompts

**Files:**
- Modify: `turbo/generators/effect/index.ts`

- [ ] **Step 1: Replace `turbo/generators/effect/index.ts` with validator + prompts**

```ts
import { execSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import type { PlopTypes } from "@turbo/gen";

const KEBAB_CASE = /^[a-z0-9]+(-[a-z0-9]+)*$/;

function validatePackageName(input: string, workspaceRoot: string): true | string {
  if (!input) return "package name is required";
  if (!KEBAB_CASE.test(input)) {
    return "package name must be kebab-case (lowercase letters, digits, hyphens; no leading/trailing hyphens)";
  }
  const target = path.join(workspaceRoot, "packages", input);
  if (existsSync(target)) {
    return `packages/${input} already exists`;
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

  plop.setGenerator("effect", {
    description: "Scaffold a new Effect v4 library package under packages/<name>/",
    prompts: [
      {
        type: "input",
        name: "packageName",
        message: "Package name (kebab-case, becomes packages/<name>):",
        validate: (input: string) => validatePackageName(input, workspaceRoot),
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
        default: getGitUserName(),
      },
    ],
    actions: [],
  });
}
```

- [ ] **Step 2: Verify the file compiles**

Run: `bunx tsc --noEmit turbo/generators/effect/index.ts turbo/generators/config.ts`

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add turbo/generators/effect/index.ts
git commit -m "feat(generators): add prompts and validation for effect generator"
```

---

## Task 4: Add the package.json template

**Files:**
- Create: `turbo/generators/effect/templates/package.json.hbs`

- [ ] **Step 1: Create `turbo/generators/effect/templates/package.json.hbs`**

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
  "files": ["dist"],
  "scripts": {
    "build": "tsc --build",
    "check": "bunx biome check . && tsc --noEmit",
    "test": "bun test"
  },
  "dependencies": {
    "effect": "catalog:"
  },
  "devDependencies": {
    "@repo/typescript-config": "workspace:*",
    "typescript": "catalog:"
  }
}
```

- [ ] **Step 2: Sanity-check it's valid JSON after a dry render**

Run a quick render check by feeding sample values through node:

```bash
node -e '
const Handlebars = require("handlebars");
const fs = require("fs");
const tpl = fs.readFileSync("turbo/generators/effect/templates/package.json.hbs", "utf8");
const out = Handlebars.compile(tpl)({ packageName: "demo", description: "A demo", author: "Alex" });
JSON.parse(out);
console.log("OK");
'
```

Expected: prints `OK`. If `handlebars` is not on the path, install ad-hoc with `bun add -d handlebars` first, or skip this step (it's optional verification).

- [ ] **Step 3: Commit**

```bash
git add turbo/generators/effect/templates/package.json.hbs
git commit -m "feat(generators): add package.json template for effect generator"
```

---

## Task 5: Add the tsconfig.json template

**Files:**
- Create: `turbo/generators/effect/templates/tsconfig.json.hbs`

- [ ] **Step 1: Create `turbo/generators/effect/templates/tsconfig.json.hbs`**

```hbs
{
  "$schema": "https://json.schemastore.org/tsconfig",
  "extends": "@repo/typescript-config/tsconfig.base.json",
  "compilerOptions": {
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "./dist",
    "rootDir": "."
  },
  "include": ["src/**/*", "tests/**/*"],
  "exclude": ["dist", "node_modules"]
}
```

- [ ] **Step 2: Verify it parses as JSON (handlebars produces no substitutions here, so it's a static check)**

Run: `node -e 'JSON.parse(require("fs").readFileSync("turbo/generators/effect/templates/tsconfig.json.hbs", "utf8"))'`

Expected: no output, no error.

- [ ] **Step 3: Commit**

```bash
git add turbo/generators/effect/templates/tsconfig.json.hbs
git commit -m "feat(generators): add tsconfig.json template for effect generator"
```

---

## Task 6: Add src/index.ts and tests/index.spec.ts templates

**Files:**
- Create: `turbo/generators/effect/templates/src-index.ts.hbs`
- Create: `turbo/generators/effect/templates/tests-index.spec.ts.hbs`

- [ ] **Step 1: Create `turbo/generators/effect/templates/src-index.ts.hbs`**

```hbs
import { Effect } from "effect";

export const greet = (name: string): Effect.Effect<string> =>
  Effect.succeed(`Hello, ${name}!`);
```

- [ ] **Step 2: Create `turbo/generators/effect/templates/tests-index.spec.ts.hbs`**

```hbs
import { describe, expect, test } from "bun:test";
import { Effect } from "effect";
import { greet } from "../src/index.ts";

describe("{{ packageName }}", () => {
  test("greet returns a hello message", async () => {
    const result = await Effect.runPromise(greet("world"));
    expect(result).toBe("Hello, world!");
  });
});
```

- [ ] **Step 3: Commit**

```bash
git add turbo/generators/effect/templates/src-index.ts.hbs turbo/generators/effect/templates/tests-index.spec.ts.hbs
git commit -m "feat(generators): add src and test templates for effect generator"
```

---

## Task 7: Add the CLAUDE.md template

**Files:**
- Create: `turbo/generators/effect/templates/CLAUDE.md.hbs`

- [ ] **Step 1: Create `turbo/generators/effect/templates/CLAUDE.md.hbs`**

```hbs
# @repo/{{ packageName }}

{{#if description}}{{ description }}{{else}}An Effect v4 library.{{/if}}

<!-- effect-solutions:start -->
## Effect Best Practices

**IMPORTANT:** Always consult effect-solutions before writing Effect code.

1. Run `effect-solutions list` to see available guides
2. Run `effect-solutions show <topic>...` for relevant patterns (supports multiple topics)
3. Search `~/.local/share/effect-solutions/effect` for real implementations

Topics: quick-start, project-setup, tsconfig, basics, services-and-layers, data-modeling, error-handling, config, testing, cli.

Never guess at Effect patterns - check the guide first.
<!-- effect-solutions:end -->

## Scripts

- `bun run build` — TypeScript build to `dist/`
- `bun run check` — biome lint + `tsc --noEmit`
- `bun test` — run tests
```

- [ ] **Step 2: Commit**

```bash
git add turbo/generators/effect/templates/CLAUDE.md.hbs
git commit -m "feat(generators): add CLAUDE.md template for effect generator"
```

---

## Task 8: Wire all `add` actions into the generator

**Files:**
- Modify: `turbo/generators/effect/index.ts`

- [ ] **Step 1: Update the `actions` array in `registerEffectGenerator`**

Replace the empty `actions: [],` line with:

```ts
    actions: [
      {
        type: "add",
        path: "{{ turbo.paths.root }}/packages/{{ packageName }}/package.json",
        templateFile: "effect/templates/package.json.hbs",
      },
      {
        type: "add",
        path: "{{ turbo.paths.root }}/packages/{{ packageName }}/tsconfig.json",
        templateFile: "effect/templates/tsconfig.json.hbs",
      },
      {
        type: "add",
        path: "{{ turbo.paths.root }}/packages/{{ packageName }}/src/index.ts",
        templateFile: "effect/templates/src-index.ts.hbs",
      },
      {
        type: "add",
        path: "{{ turbo.paths.root }}/packages/{{ packageName }}/tests/index.spec.ts",
        templateFile: "effect/templates/tests-index.spec.ts.hbs",
      },
      {
        type: "add",
        path: "{{ turbo.paths.root }}/packages/{{ packageName }}/CLAUDE.md",
        templateFile: "effect/templates/CLAUDE.md.hbs",
      },
    ],
```

- [ ] **Step 2: Verify the file still compiles**

Run: `bunx tsc --noEmit turbo/generators/effect/index.ts turbo/generators/config.ts`

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add turbo/generators/effect/index.ts
git commit -m "feat(generators): wire add actions for effect generator templates"
```

---

## Task 9: Add the symlink custom action for AGENTS.md

**Files:**
- Modify: `turbo/generators/effect/index.ts`

- [ ] **Step 1: Add the custom action and append it to the actions array**

Add this near the top of the file, after the existing imports:

```ts
import { symlinkSync } from "node:fs";
```

Inside `registerEffectGenerator`, before `plop.setGenerator(...)`, register the custom action:

```ts
  plop.setActionType("symlinkAgentsMd", (answers) => {
    const packageName = (answers as { packageName: string }).packageName;
    const target = path.join(workspaceRoot, "packages", packageName, "AGENTS.md");
    symlinkSync("CLAUDE.md", target);
    return `symlinked AGENTS.md -> CLAUDE.md in packages/${packageName}`;
  });
```

Then append this entry to the `actions` array (after the CLAUDE.md add):

```ts
      {
        type: "symlinkAgentsMd",
      },
```

- [ ] **Step 2: Verify compilation**

Run: `bunx tsc --noEmit turbo/generators/effect/index.ts turbo/generators/config.ts`

Expected: No errors. (`symlinkAgentsMd` is a string identifier; plop accepts custom action types.)

- [ ] **Step 3: Commit**

```bash
git add turbo/generators/effect/index.ts
git commit -m "feat(generators): add AGENTS.md→CLAUDE.md symlink action"
```

---

## Task 10: End-to-end verification on a throwaway package

**Files:**
- (no files modified — this is a verification task)

- [ ] **Step 1: Generate a test package non-interactively**

Plop accepts answers via CLI flags. Run:

```bash
bunx turbo gen effect --args genfx-demo "demo package for verifying generator" "Generator Test"
```

If positional args don't bind to your prompts in this turbo version, fall back to interactive: `bunx turbo gen effect` and type `genfx-demo`, a description, and an author.

Expected: `packages/genfx-demo/` is created with the structure:
```
packages/genfx-demo/
├── AGENTS.md -> CLAUDE.md
├── CLAUDE.md
├── package.json
├── src/index.ts
├── tests/index.spec.ts
└── tsconfig.json
```

- [ ] **Step 2: Verify the symlink resolves**

Run: `readlink packages/genfx-demo/AGENTS.md`

Expected: `CLAUDE.md`

- [ ] **Step 3: Install workspace dependencies so the new package resolves**

Run: `bun install`

Expected: completes without error; `packages/genfx-demo/node_modules` (or the workspace-root symlink layout) contains `effect` and `@repo/typescript-config`.

- [ ] **Step 4: Run check**

Run: `cd packages/genfx-demo && bun run check && cd ../..`

Expected: biome reports no issues; `tsc --noEmit` exits 0.

- [ ] **Step 5: Run build**

Run: `cd packages/genfx-demo && bun run build && cd ../..`

Expected: `packages/genfx-demo/dist/index.js` and `dist/index.d.ts` exist.

- [ ] **Step 6: Run tests**

Run: `cd packages/genfx-demo && bun test && cd ../..`

Expected: 1 passing test (`greet returns a hello message`).

- [ ] **Step 7: Verify duplicate-name rejection**

Run: `bunx turbo gen effect` and at the package-name prompt enter `genfx-demo`.

Expected: validation error "packages/genfx-demo already exists". Cancel out of the prompt.

- [ ] **Step 8: Clean up the throwaway package**

Run: `rm -rf packages/genfx-demo && bun install`

Expected: directory removed, `bun install` succeeds without it.

- [ ] **Step 9: Commit nothing — no source changes from this task**

This task changes no source files. Skip the commit step.

---

## Task 11: Update root README/CLAUDE.md with usage note (optional)

**Files:**
- Modify: `CLAUDE.md` (root) if it exists; otherwise skip.

- [ ] **Step 1: Check whether a root CLAUDE.md exists**

Run: `ls CLAUDE.md AGENTS.md 2>/dev/null`

If neither exists, skip this task entirely — no docs update is required by the spec.

- [ ] **Step 2: If a root CLAUDE.md exists, append a section**

Add (idempotently — check it isn't already there):

```markdown
## Generators

- `bunx turbo gen effect` — scaffold a new Effect library at `packages/<name>/`. See `turbo/generators/effect/`.
```

- [ ] **Step 3: Commit (only if step 2 made a change)**

```bash
git add CLAUDE.md
git commit -m "docs: note effect generator in root CLAUDE.md"
```

---

## Self-Review

**Spec coverage:**
- Interactive prompts (name, description, author): Task 3 ✓
- Package structure (src, tests, package.json, tsconfig.json, CLAUDE.md, AGENTS.md): Tasks 4–7, 9 ✓
- `package.json` with effect from catalog, biome+tsc check, bun test: Task 4 ✓
- `tsconfig.json` extending `@repo/typescript-config`: Task 5 ✓
- AGENTS.md → CLAUDE.md symlink: Task 9 ✓
- Validation on package name (kebab-case, no collisions): Task 3 ✓
- Wire-up in `turbo/generators/config.ts`: Task 2 ✓
- End-to-end build/check/test passing: Task 10 ✓

**Placeholder scan:** All steps include exact code or exact commands. No "TBD"/"add validation"/"similar to" references.

**Type consistency:** `registerEffectGenerator` is the single exported symbol from `turbo/generators/effect/index.ts` and is imported by `turbo/generators/config.ts`. The `symlinkAgentsMd` custom action name matches between definition and usage.

**Note for executor:** Task 10 step 1 — turbo gen's CLI arg passing for prompt answers varies by version. If the non-interactive form fails, just use the interactive prompt; the verification still completes the test. If turbo gen has a different non-interactive flag in 2.9.6 (e.g., `--name`), adjust accordingly.
