# Nitro App Generator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Nitro v3 as a third app-framework option in the `scaffold` generator. Bootstrap with `bun create nitro-app@latest`, optionally patch the default handler with Effect.

**Architecture:** Nitro joins the existing shell-out pattern (Hono, Elysia). Add a `nitro` entry to `FRAMEWORK_CONFIGS` with two new struct fields: `entryFile` (so the Effect-patch action can target `server/api/hello.ts` instead of the hard-coded `src/index.ts`) and an optional `postCreate` hook (so Nitro can inject a missing `name` field into `package.json` and remove the starter's pre-existing `AGENTS.md` file before our `symlinkAgentsMd` action runs).

**Tech Stack:** TypeScript, Bun test, plop (via `@turbo/gen`), `bun create nitro-app@latest`.

**Spec:** `docs/superpowers/specs/2026-05-02-nitro-app-generator-design.md`

---

## File Structure

- **Modify:** `turbo/generators/scaffold/index.ts` — extend `Framework`, `FrameworkConfig`, `FRAMEWORK_CONFIGS`; add Nitro builders; generalize `patchAppEffectInstall`; thread `postCreate` through the create-action loop.
- **Modify:** `turbo/generators/scaffold/index.test.ts` — add Nitro test cases mirroring the Hono/Elysia coverage; update the framework-choices assertion.

No new files. All changes are additive to existing tests except the prompt-choices assertion.

---

## Task 1: Extend `Framework` type and add `nitro` to the framework prompt

**Files:**
- Modify: `turbo/generators/scaffold/index.ts:17` (the `Framework` type) and `turbo/generators/scaffold/index.ts:283-294` (the framework prompt's `choices`)
- Modify: `turbo/generators/scaffold/index.ts:227-229` (the `isShellOutFramework` guard)
- Test: `turbo/generators/scaffold/index.test.ts`

- [ ] **Step 1: Add a failing test that asserts Nitro appears in the framework prompt's choices**

Add to `turbo/generators/scaffold/index.test.ts` inside `describe("scaffold generator", () => { ... })`, right after the existing prompt assertion test:

```ts
it("offers Nitro as a framework choice", () => {
  const prompts = getScaffoldPrompts("/repo");
  const framework = prompts.find((p) => p.name === "framework") as {
    choices?: ReadonlyArray<{ name: string; value: string }>;
  };
  expect(framework.choices).toContainEqual({ name: "Nitro", value: "nitro" });
});
```

- [ ] **Step 2: Run the new test to verify it fails**

Run: `cd turbo/generators && bun test scaffold/index.test.ts -t "offers Nitro"`
Expected: FAIL — `framework.choices` does not contain `{ name: "Nitro", value: "nitro" }`.

- [ ] **Step 3: Extend the `Framework` union and add the choice**

In `turbo/generators/scaffold/index.ts` line 17, change:

```ts
type Framework = "bun" | "hono" | "elysia";
```

to:

```ts
type Framework = "bun" | "hono" | "elysia" | "nitro";
```

In the same file, update the framework prompt's `choices` array (around line 286-291) so it reads:

```ts
choices: [
  { name: "Bun (no framework)", value: "bun" },
  { name: "Hono", value: "hono" },
  { name: "Elysia", value: "elysia" },
  { name: "Nitro", value: "nitro" },
],
```

Update `isShellOutFramework` (around line 227-229) to:

```ts
function isShellOutFramework(fw?: Framework): fw is ShellOutFramework {
  return fw === "hono" || fw === "elysia" || fw === "nitro";
}
```

Update the `ShellOutFramework` type (around line 206) to:

```ts
type ShellOutFramework = "hono" | "elysia" | "nitro";
```

- [ ] **Step 4: Run the new test to confirm it passes**

Run: `cd turbo/generators && bun test scaffold/index.test.ts -t "offers Nitro"`
Expected: PASS.

- [ ] **Step 5: Run the full test file to confirm no regressions**

Run: `cd turbo/generators && bun test scaffold/index.test.ts`
Expected: All pre-existing tests still pass. (TypeScript will complain that the `nitro` key is missing from `FRAMEWORK_CONFIGS` — that's resolved in Task 3. If `bun test` runs the file successfully despite the type error, proceed; if not, temporarily comment out the new framework choice and re-add it in Task 3. In practice Bun's runtime ignores TS type errors, so the suite should run.)

- [ ] **Step 6: Commit**

```bash
git add turbo/generators/scaffold/index.ts turbo/generators/scaffold/index.test.ts
git commit -m "feat(generators): add nitro to framework choices"
```

---

## Task 2: Add `entryFile` to `FrameworkConfig` and generalize `patchAppEffectInstall`

This task makes `patchAppEffectInstall` configurable so Nitro can patch `server/api/hello.ts` instead of the hard-coded `src/index.ts`. Hono and Elysia keep their existing `src/index.ts` entry — no behavior change for them.

**Files:**
- Modify: `turbo/generators/scaffold/index.ts:208-212` (the `FrameworkConfig` interface), lines 214-225 (the `FRAMEWORK_CONFIGS` map), lines 324-342 (`patchAppEffectInstall`), and the `patch${label}Effect` action registration at lines 391-399.
- Test: `turbo/generators/scaffold/index.test.ts` — no new tests needed; existing tests cover the action sequence and the call site change is internal. Type checking is the verification.

- [ ] **Step 1: Add `entryFile` to `FrameworkConfig`**

In `turbo/generators/scaffold/index.ts`, change the `FrameworkConfig` interface (around line 208) to:

```ts
interface FrameworkConfig {
  label: string;
  entryFile: string;
  buildCommand: (workspaceRoot: string, packageName: string) => CommandSpec;
  buildEffectIndexSource: () => string;
}
```

- [ ] **Step 2: Backfill `entryFile` on the existing Hono and Elysia configs**

Update `FRAMEWORK_CONFIGS` (around line 214) so each entry includes `entryFile: "src/index.ts"`:

```ts
const FRAMEWORK_CONFIGS: Record<ShellOutFramework, FrameworkConfig> = {
  hono: {
    label: "Hono",
    entryFile: "src/index.ts",
    buildCommand: buildCreateHonoCommand,
    buildEffectIndexSource: buildHonoEffectIndexSource,
  },
  elysia: {
    label: "Elysia",
    entryFile: "src/index.ts",
    buildCommand: buildCreateElysiaCommand,
    buildEffectIndexSource: buildElysiaEffectIndexSource,
  },
};
```

(Don't add the `nitro` entry yet — Task 3.)

- [ ] **Step 3: Generalize `patchAppEffectInstall` to take an entry file path**

Replace the function definition (around line 324-342) with:

```ts
function patchAppEffectInstall(
  workspaceRoot: string,
  packageName: string,
  entryFile: string,
  indexSource: string,
): void {
  const appDir = path.join(workspaceRoot, SUBDIR.app, packageName);
  const packageJsonPath = path.join(appDir, "package.json");

  const packageJson = JSON.parse(readFileSync(packageJsonPath, "utf8")) as {
    dependencies?: Record<string, string>;
  };
  packageJson.dependencies = {
    ...packageJson.dependencies,
    effect: packageJson.dependencies?.effect ?? "catalog:",
  };
  writeFileSync(packageJsonPath, `${JSON.stringify(packageJson, null, 2)}\n`);

  writeFileSync(path.join(appDir, entryFile), indexSource);
}
```

- [ ] **Step 4: Update the `patch${label}Effect` call site to pass `config.entryFile`**

In the `for (const config of Object.values(FRAMEWORK_CONFIGS))` loop (around line 391), update the `patch${label}Effect` action body so it reads:

```ts
plop.setActionType(`patch${config.label}Effect`, (rawAnswers) => {
  const answers = rawAnswers as ScaffoldAnswers;
  patchAppEffectInstall(
    workspaceRoot,
    answers.packageName,
    config.entryFile,
    config.buildEffectIndexSource(),
  );
  return `configured Effect in ${SUBDIR.app}/${answers.packageName}`;
});
```

- [ ] **Step 5: Run the full test file to confirm no regressions**

Run: `cd turbo/generators && bun test scaffold/index.test.ts`
Expected: All tests pass. (No behavior change — Hono and Elysia still target `src/index.ts`.)

- [ ] **Step 6: Commit**

```bash
git add turbo/generators/scaffold/index.ts
git commit -m "refactor(generators): make effect-patch entry file configurable per framework"
```

---

## Task 3: Add Nitro builders, `postCreate` hook plumbing, and the `nitro` config entry

This is the meat of the change. Adds Nitro's create command, Effect-patched handler source, and `postCreate` hook (which adds `name` to package.json and removes the starter's AGENTS.md). Wires Nitro into `FRAMEWORK_CONFIGS` so the existing loop registers `createNitroApp` and `patchNitroEffect` action types.

**Files:**
- Modify: `turbo/generators/scaffold/index.ts` — add `buildCreateNitroCommand`, `buildNitroEffectIndexSource`, `postCreate?` field on `FrameworkConfig`, the `nitro` entry in `FRAMEWORK_CONFIGS`, and the `postCreate` invocation in the `create${label}App` action.
- Test: `turbo/generators/scaffold/index.test.ts` — add tests for action sequences, command shape, and Effect index source contents.

- [ ] **Step 1: Write failing tests for Nitro action sequences and helpers**

Add to `turbo/generators/scaffold/index.test.ts` (anywhere inside the `describe` block, after the existing Elysia tests is natural). Note: `buildCreateNitroCommand` and `buildNitroEffectIndexSource` need to be added to the import list at the top of the test file.

Update the import block at the top of the file:

```ts
import {
  buildCreateElysiaCommand,
  buildCreateHonoCommand,
  buildCreateNitroCommand,
  buildElysiaEffectIndexSource,
  buildHonoEffectIndexSource,
  buildNitroEffectIndexSource,
  buildScaffoldActions,
  getScaffoldPrompts,
} from "./index.ts";
```

Add these four `it(...)` blocks:

```ts
it("scaffolds a nitro app via shell-out, no effect patch when disabled", () => {
  const actions = buildScaffoldActions({
    type: "app",
    framework: "nitro",
    useEffect: false,
  });
  expect(actionTypes(actions)).toEqual([
    "createNitroApp",
    "symlinkAgentsMd",
    "installWorkspace",
  ]);
});

it("scaffolds a nitro app with effect patch when enabled", () => {
  const actions = buildScaffoldActions({
    type: "app",
    framework: "nitro",
    useEffect: true,
  });
  expect(actionTypes(actions)).toEqual([
    "createNitroApp",
    "patchNitroEffect",
    "symlinkAgentsMd",
    "installWorkspace",
  ]);
});

it("creates nitro apps via `bun create nitro-app@latest <name> --no-install` (cwd=apps/)", () => {
  expect(buildCreateNitroCommand("/repo", "api")).toEqual({
    command: "bun",
    args: ["create", "nitro-app@latest", "api", "--no-install"],
    cwd: "/repo/apps",
  });
});

it("generates a Nitro handler backed by Effect", () => {
  const source = buildNitroEffectIndexSource();
  expect(source).toContain('import { Console, Effect } from "effect";');
  expect(source).toContain('import { defineHandler } from "nitro";');
  expect(source).toContain("Effect.runPromise");
  expect(source).toContain("defineHandler");
});
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `cd turbo/generators && bun test scaffold/index.test.ts -t "nitro"`
Expected: FAIL — module does not export `buildCreateNitroCommand` or `buildNitroEffectIndexSource`; `buildScaffoldActions` doesn't return the Nitro action sequence.

- [ ] **Step 3: Add `postCreate` to `FrameworkConfig`**

Update the `FrameworkConfig` interface in `turbo/generators/scaffold/index.ts` (the one you edited in Task 2) to:

```ts
interface FrameworkConfig {
  label: string;
  entryFile: string;
  buildCommand: (workspaceRoot: string, packageName: string) => CommandSpec;
  buildEffectIndexSource: () => string;
  postCreate?: (workspaceRoot: string, packageName: string) => void;
}
```

- [ ] **Step 4: Add `buildCreateNitroCommand` and `buildNitroEffectIndexSource`**

In `turbo/generators/scaffold/index.ts`, add these two exported helpers immediately after `buildElysiaEffectIndexSource` (around line 204):

```ts
export function buildCreateNitroCommand(
  workspaceRoot: string,
  packageName: string,
): CommandSpec {
  return {
    command: "bun",
    args: ["create", "nitro-app@latest", packageName, "--no-install"],
    cwd: path.join(workspaceRoot, SUBDIR.app),
  };
}

export function buildNitroEffectIndexSource(): string {
  return `import { Console, Effect } from "effect";
import { defineHandler } from "nitro";

export default defineHandler(() =>
  Effect.runPromise(
    Effect.gen(function* () {
      yield* Console.log("GET /api/hello");
      return { api: "works with Effect!" };
    }),
  ),
);
`;
}
```

- [ ] **Step 5: Add the `nitro` entry to `FRAMEWORK_CONFIGS`**

Update `FRAMEWORK_CONFIGS` (the one you edited in Task 2) to include nitro. Final shape:

```ts
const FRAMEWORK_CONFIGS: Record<ShellOutFramework, FrameworkConfig> = {
  hono: {
    label: "Hono",
    entryFile: "src/index.ts",
    buildCommand: buildCreateHonoCommand,
    buildEffectIndexSource: buildHonoEffectIndexSource,
  },
  elysia: {
    label: "Elysia",
    entryFile: "src/index.ts",
    buildCommand: buildCreateElysiaCommand,
    buildEffectIndexSource: buildElysiaEffectIndexSource,
  },
  nitro: {
    label: "Nitro",
    entryFile: "server/api/hello.ts",
    buildCommand: buildCreateNitroCommand,
    buildEffectIndexSource: buildNitroEffectIndexSource,
    postCreate: (workspaceRoot, packageName) => {
      const appDir = path.join(workspaceRoot, SUBDIR.app, packageName);

      // create-nitro-app generates a package.json with no name field;
      // Bun workspaces need one to resolve the package.
      const pkgPath = path.join(appDir, "package.json");
      const pkg = JSON.parse(readFileSync(pkgPath, "utf8")) as {
        name?: string;
      };
      pkg.name = packageName;
      writeFileSync(pkgPath, `${JSON.stringify(pkg, null, 2)}\n`);

      // Starter ships AGENTS.md as a real file; remove it so the
      // symlinkAgentsMd action can create the AGENTS.md -> CLAUDE.md symlink.
      rmSync(path.join(appDir, "AGENTS.md"), { force: true });
    },
  },
};
```

- [ ] **Step 6: Invoke `postCreate` in the generic `create${label}App` action**

In the `for (const config of Object.values(FRAMEWORK_CONFIGS))` loop, update the `create${label}App` action body so that after the existing `rmSync(node_modules)` and `rmSync(bun.lock)` it calls `postCreate` if defined. The full action body becomes:

```ts
plop.setActionType(`create${config.label}App`, (rawAnswers) => {
  const answers = rawAnswers as ScaffoldAnswers;
  mkdirSync(path.join(workspaceRoot, SUBDIR.app), { recursive: true });

  const { command, args, cwd } = config.buildCommand(
    workspaceRoot,
    answers.packageName,
  );
  execFileSync(command, args, { cwd, stdio: "inherit" });

  // Some create CLIs install locally; drop those artifacts so the
  // workspace-root install is the single source of truth.
  const appDir = path.join(workspaceRoot, SUBDIR.app, answers.packageName);
  rmSync(path.join(appDir, "node_modules"), {
    recursive: true,
    force: true,
  });
  rmSync(path.join(appDir, "bun.lock"), { force: true });

  config.postCreate?.(workspaceRoot, answers.packageName);

  return `created ${config.label} app in ${SUBDIR.app}/${answers.packageName}`;
});
```

- [ ] **Step 7: Run the new tests to confirm they pass**

Run: `cd turbo/generators && bun test scaffold/index.test.ts -t "nitro"`
Expected: PASS — all four nitro tests pass.

- [ ] **Step 8: Run the full test file to confirm no regressions**

Run: `cd turbo/generators && bun test scaffold/index.test.ts`
Expected: All tests pass.

- [ ] **Step 9: TypeScript check**

Run: `cd turbo/generators && bunx tsc --noEmit`
Expected: No errors. (If the `tsc` command isn't wired up at this path, run from the workspace root: `bunx tsc --noEmit -p turbo/generators/tsconfig.json` if such a tsconfig exists; otherwise skip — Bun's runtime is the source of truth in this repo.)

- [ ] **Step 10: Commit**

```bash
git add turbo/generators/scaffold/index.ts turbo/generators/scaffold/index.test.ts
git commit -m "feat(generators): add nitro framework with optional effect patch"
```

---

## Task 4: End-to-end smoke test (manual)

Automated tests cover action sequences and helper outputs, but the actual `bun create nitro-app@latest` invocation, `postCreate` filesystem effects, and `bun install` workspace integration are only verified end-to-end. This task runs the generator once against a throwaway package name and confirms the result.

**Files:** None modified. Manual verification only. Generates a real package under `apps/<smoke-name>` that should be deleted before commit.

- [ ] **Step 1: Run the scaffold generator end-to-end without Effect**

Run from the repo root:

```bash
bun turbo gen scaffold
```

Answer the prompts:
- type: `app`
- framework: `Nitro`
- useEffect: `n`
- packageName: `nitro-smoke-plain`
- description: (blank)
- author: (accept default)

Expected:
- Command runs to completion without errors.
- `apps/nitro-smoke-plain/` exists.
- `apps/nitro-smoke-plain/server/api/hello.ts` is the unmodified Nitro starter content (no Effect imports).
- `apps/nitro-smoke-plain/package.json` has `"name": "nitro-smoke-plain"`.
- `apps/nitro-smoke-plain/AGENTS.md` is a symlink pointing to `CLAUDE.md` (verify with `ls -l apps/nitro-smoke-plain/AGENTS.md`).
- `apps/nitro-smoke-plain/node_modules` does not exist (workspace install handled deps).
- Workspace install happened (no installer errors in stdout).

- [ ] **Step 2: Run the scaffold generator end-to-end with Effect**

Run from the repo root:

```bash
bun turbo gen scaffold
```

Answer the prompts:
- type: `app`
- framework: `Nitro`
- useEffect: `Y`
- packageName: `nitro-smoke-effect`
- description: (blank)
- author: (accept default)

Expected:
- All of the above, PLUS:
- `apps/nitro-smoke-effect/server/api/hello.ts` matches `buildNitroEffectIndexSource()` (Console+Effect imports, `Effect.runPromise` wrapping `defineHandler`).
- `apps/nitro-smoke-effect/package.json` has `effect: "catalog:"` in `dependencies`.

- [ ] **Step 3: Boot one of the smoke apps to confirm it runs**

Run from the repo root:

```bash
cd apps/nitro-smoke-effect && bun run dev
```

Expected: Vite + Nitro dev server starts, prints a local URL, no immediate crash. Hit the URL + `/api/hello` (e.g. `curl http://localhost:3000/api/hello`); expect `{"api":"works with Effect!"}`. Stop the server with Ctrl-C.

If the dev server crashes or `/api/hello` returns a non-Effect-shaped response, the patch is misaligned with the Nitro v3 starter; revisit `buildNitroEffectIndexSource()` and the `entryFile` path.

- [ ] **Step 4: Clean up smoke artifacts**

Run from the repo root:

```bash
rm -rf apps/nitro-smoke-plain apps/nitro-smoke-effect
bun install
```

Confirm `git status` shows only the changes from Tasks 1-3 (no leftover smoke directories, no stray bun.lock changes that aren't from removing the smoke deps).

- [ ] **Step 5: No commit for this task** — manual verification only. If smoke uncovered any issues, add a follow-up task to fix them and re-run the smoke.

---

## Summary

After all tasks complete:
- The `scaffold` generator offers `Nitro` as a framework option.
- Choosing Nitro shells out to `bun create nitro-app@latest <name> --no-install`, fixes the missing `name` field and the AGENTS.md collision, and (if Effect is requested) rewrites `server/api/hello.ts` to wrap the response in an Effect runtime.
- Existing Hono/Elysia behavior is unchanged — they keep targeting `src/index.ts` because each framework now declares its own `entryFile` in `FRAMEWORK_CONFIGS`.
