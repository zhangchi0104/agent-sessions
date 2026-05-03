# Nitro App Generator — Design

## Context

`turbo/generators/scaffold/index.ts` already supports two third-party app frameworks (Hono, Elysia) via a "shell out then optionally patch with Effect" pattern. Both share a small `FrameworkConfig` struct and a `FRAMEWORK_CONFIGS` map; the generator loop registers `create${label}App` and `patch${label}Effect` plop action types from that map.

The team needs Nitro v3 (https://nitro.build/docs/quick-start) as a third app framework option. The official scaffolder is `bun create nitro-app@latest <name>`, which generates a Vite + Nitro hybrid project.

## Goal

Add `nitro` to the framework choice in the `scaffold` generator. Bootstrap with `bun create nitro-app@latest`, then — if the user opts in — patch the default handler at `server/api/hello.ts` to wrap the response in an Effect runtime.

Out of scope: hand-rolled Nitro templates, Nuxt support, Vite plugin customization, additional Nitro presets.

## What `bun create nitro-app@latest <name> --no-install` produces

Verified by probe at `/tmp/nitro-probe/test-app`:

```
test-app/
├── .gitignore
├── AGENTS.md                  # ships as a real file (not a symlink)
├── CLAUDE.md
├── README.md
├── app/
│   ├── app.ts
│   ├── assets/{main.css,nitro.svg,vite.svg}
│   └── entry-client.ts
├── index.html
├── nitro.config.ts
├── package.json               # no "name" field
├── public/robots.txt
├── server/
│   └── api/hello.ts           # default handler — Effect patch target
├── tsconfig.json
└── vite.config.ts
```

Default `server/api/hello.ts`:

```ts
import { defineHandler } from "nitro";

export default defineHandler((event) => {
  return { api: "works!"}
});
```

Default `package.json`:

```json
{
  "type": "module",
  "scripts": { "build": "vite build", "dev": "vite dev", "preview": "vite preview" },
  "devDependencies": { "nitro": "latest", "vite": "latest" }
}
```

Two consequences for the existing scaffold pipeline:

1. **No `name` field.** Bun workspace install needs each member to have a name. We must inject `"name": "<packageName>"`.
2. **`AGENTS.md` already exists as a real file.** Our `symlinkAgentsMd` action calls `symlinkSync("CLAUDE.md", ".../AGENTS.md")`, which throws `EEXIST`. We must remove the pre-existing `AGENTS.md` before the symlink action runs.

## Interactive Prompts

No new prompts. The existing `framework` list (only shown when `type === "app"`) gains a third choice:

```ts
{ name: "Nitro", value: "nitro" }
```

The existing `useEffect` confirm prompt covers the Effect opt-in.

## Generator Module Changes (`turbo/generators/scaffold/index.ts`)

1. Extend `Framework`: `"bun" | "hono" | "elysia" | "nitro"`.
2. Extend `ShellOutFramework`: `"hono" | "elysia" | "nitro"`. Update `isShellOutFramework`.
3. Extend `FrameworkConfig` with two new fields:
   - `entryFile: string` — relative path of the file `patchAppEffectInstall` rewrites.
     Hono/Elysia: `"src/index.ts"`. Nitro: `"server/api/hello.ts"`.
   - `postCreate?: (workspaceRoot: string, packageName: string) => void` — optional hook
     called by the `create${label}App` action after the existing node_modules/bun.lock cleanup.
4. Add `buildCreateNitroCommand(workspaceRoot, packageName)`:

   ```ts
   {
     command: "bun",
     args: ["create", "nitro-app@latest", packageName, "--no-install"],
     cwd: path.join(workspaceRoot, SUBDIR.app),
   }
   ```

5. Add `buildNitroEffectIndexSource()` returning:

   ```ts
   import { Console, Effect } from "effect";
   import { defineHandler } from "nitro";

   export default defineHandler(() =>
     Effect.runPromise(
       Effect.gen(function* () {
         yield* Console.log("GET /api/hello");
         return { api: "works with Effect!" };
       }),
     ),
   );
   ```

6. Add a `nitro` entry to `FRAMEWORK_CONFIGS`:

   ```ts
   nitro: {
     label: "Nitro",
     buildCommand: buildCreateNitroCommand,
     buildEffectIndexSource: buildNitroEffectIndexSource,
     entryFile: "server/api/hello.ts",
     postCreate: (workspaceRoot, packageName) => {
       const appDir = path.join(workspaceRoot, SUBDIR.app, packageName);

       // Inject name field so Bun workspaces resolve the package.
       const pkgPath = path.join(appDir, "package.json");
       const pkg = JSON.parse(readFileSync(pkgPath, "utf8")) as { name?: string };
       pkg.name = packageName;
       writeFileSync(pkgPath, `${JSON.stringify(pkg, null, 2)}\n`);

       // Remove starter's AGENTS.md so symlinkAgentsMd can create the symlink.
       rmSync(path.join(appDir, "AGENTS.md"), { force: true });
     },
   }
   ```

7. Backfill `entryFile: "src/index.ts"` on the existing Hono and Elysia entries.
8. Generalize `patchAppEffectInstall` to take the entry file path from config:

   ```ts
   function patchAppEffectInstall(
     workspaceRoot: string,
     packageName: string,
     entryFile: string,
     indexSource: string,
   ): void { ... writeFileSync(path.join(appDir, entryFile), indexSource); }
   ```

   Update the call site in the `patch${label}Effect` action to pass `config.entryFile`.

9. In the generic `create${label}App` action, after the existing `rmSync(node_modules)` /
   `rmSync(bun.lock)` cleanup, call `config.postCreate?.(workspaceRoot, answers.packageName)`.

## Tests (`turbo/generators/scaffold/index.test.ts`)

Add cases that mirror the Hono/Elysia coverage:

- `buildScaffoldActions({ type: "app", framework: "nitro", useEffect: false })`
  → `["createNitroApp", "symlinkAgentsMd", "installWorkspace"]`
- `buildScaffoldActions({ type: "app", framework: "nitro", useEffect: true })`
  → `["createNitroApp", "patchNitroEffect", "symlinkAgentsMd", "installWorkspace"]`
- `buildCreateNitroCommand("/repo", "api")` →
  `{ command: "bun", args: ["create", "nitro-app@latest", "api", "--no-install"], cwd: "/repo/apps" }`
- `buildNitroEffectIndexSource()` contains `import { Console, Effect } from "effect";`,
  `import { defineHandler } from "nitro";`, `Effect.runPromise`, `defineHandler`.
- Update `getScaffoldPrompts` test that asserts the framework choices: include Nitro.

`postCreate` and `entryFile` are exercised indirectly through the action sequence tests; no
need to test them in isolation since their effect is observable end-to-end (and unit-testing
`postCreate` requires filesystem fixtures that are out of proportion to the value).

## Risks

- **`bun create nitro-app@latest` is non-deterministic over time.** The starter could change its
  default handler path or filename. If `server/api/hello.ts` ever moves, the Effect patch silently
  no-ops on a non-existent file. `patchAppEffectInstall` already calls `writeFileSync`, which would
  succeed but write to the wrong place. Acceptable for a scaffold (one-time, the user sees the
  diff). Not worth defensive coding now.
- **`nitro: "latest"` and `vite: "latest"` in the generated `package.json`.** Inherited from the
  starter. Not changed by this design — out of scope.
