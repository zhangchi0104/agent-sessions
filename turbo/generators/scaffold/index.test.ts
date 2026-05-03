import { describe, expect, it } from "bun:test";
import {
  buildAppTsconfig,
  buildAstroEffectIndexSource,
  buildCreateAstroCommand,
  buildCreateElysiaCommand,
  buildCreateHonoCommand,
  buildCreateNitroCommand,
  buildElysiaEffectIndexSource,
  buildEffectPackageJson,
  buildEffectTsconfig,
  buildHonoEffectIndexSource,
  buildNitroEffectIndexSource,
  buildScaffoldActions,
  getScaffoldPrompts,
} from "./index.ts";

type ActionLike = { type: string; templateFile?: string };

const actionTypes = (actions: readonly unknown[]): string[] =>
  (actions as readonly ActionLike[]).map((action) => action.type);

const templateFiles = (actions: readonly unknown[]): string[] =>
  (actions as readonly ActionLike[])
    .filter(
      (action): action is ActionLike & { templateFile: string } =>
        action.type === "add" && typeof action.templateFile === "string",
    )
    .map((action) => action.templateFile);

const expectAllStartWith = (paths: string[], prefix: string): void => {
  expect(paths.length).toBeGreaterThan(0);
  for (const p of paths) {
    expect(p).toStartWith(prefix);
  }
};

describe("scaffold generator", () => {
  it("prompts for type, libraryKind (library only), engine (db only), framework (app only), useEffect, and metadata", () => {
    const prompts = getScaffoldPrompts("/repo");

    expect(prompts.map((prompt) => prompt.name)).toEqual([
      "type",
      "libraryKind",
      "engine",
      "framework",
      "useEffect",
      "packageName",
      "description",
      "author",
    ]);

    const useEffect = prompts.find((p) => p.name === "useEffect");
    expect(useEffect).toMatchObject({
      type: "confirm",
      message: "Use Effect?",
      default: true,
    });

    const libraryKind = prompts.find((p) => p.name === "libraryKind") as {
      when?: (answers: { type: string }) => boolean;
    };
    expect(libraryKind.when?.({ type: "library" })).toBe(true);
    expect(libraryKind.when?.({ type: "app" })).toBe(false);

    const engine = prompts.find((p) => p.name === "engine") as {
      when?: (answers: { libraryKind?: string }) => boolean;
    };
    expect(engine.when?.({ libraryKind: "blank" })).toBe(false);
    expect(engine.when?.({ libraryKind: "database" })).toBe(true);
    expect(engine.when?.({})).toBe(false);

    const framework = prompts.find((p) => p.name === "framework") as {
      when?: (answers: { type: string }) => boolean;
    };
    expect(framework.when?.({ type: "library" })).toBe(false);
    expect(framework.when?.({ type: "app" })).toBe(true);
  });

  it("offers Nitro as a framework choice", () => {
    const prompts = getScaffoldPrompts("/repo");
    const framework = prompts.find((p) => p.name === "framework") as {
      choices?: ReadonlyArray<{ name: string; value: string }>;
    };
    expect(framework.choices).toContainEqual({ name: "Nitro", value: "nitro" });
  });

  it("offers Astro as a framework choice", () => {
    const prompts = getScaffoldPrompts("/repo");
    const framework = prompts.find((p) => p.name === "framework") as {
      choices?: ReadonlyArray<{ name: string; value: string }>;
    };
    expect(framework.choices).toContainEqual({ name: "Astro", value: "astro" });
  });

  it("offers TUI as a framework choice", () => {
    const prompts = getScaffoldPrompts("/repo");
    const framework = prompts.find((p) => p.name === "framework") as {
      choices?: ReadonlyArray<{ name: string; value: string }>;
    };
    expect(framework.choices).toContainEqual({ name: "TUI", value: "tui" });
  });

  it("scaffolds a blank effect library from the blank/effect templates", () => {
    const actions = buildScaffoldActions({
      type: "library",
      libraryKind: "blank",
      useEffect: true,
    });
    expect(actionTypes(actions)).toEqual([
      "add",
      "add",
      "add",
      "add",
      "add",
      "add",
      "add",
      "symlinkAgentsMd",
    ]);
    expectAllStartWith(
      templateFiles(actions),
      "scaffold/templates/library/blank/effect/",
    );
  });

  it("scaffolds a blank plain library from the blank/plain templates", () => {
    const actions = buildScaffoldActions({
      type: "library",
      libraryKind: "blank",
      useEffect: false,
    });
    expectAllStartWith(
      templateFiles(actions),
      "scaffold/templates/library/blank/plain/",
    );
  });

  it("treats library with no libraryKind as blank", () => {
    const actions = buildScaffoldActions({
      type: "library",
      useEffect: true,
    });
    expectAllStartWith(
      templateFiles(actions),
      "scaffold/templates/library/blank/effect/",
    );
  });

  it("scaffolds a plain bun app from app/bun/plain templates", () => {
    const actions = buildScaffoldActions({
      type: "app",
      framework: "bun",
      useEffect: false,
    });
    expectAllStartWith(
      templateFiles(actions),
      "scaffold/templates/app/bun/plain/",
    );
  });

  it("scaffolds an effect bun app from app/bun/effect templates", () => {
    const actions = buildScaffoldActions({
      type: "app",
      framework: "bun",
      useEffect: true,
    });
    expectAllStartWith(
      templateFiles(actions),
      "scaffold/templates/app/bun/effect/",
    );
  });

  it("scaffolds a plain tui app from app/tui/plain templates", () => {
    const actions = buildScaffoldActions({
      type: "app",
      framework: "tui",
      useEffect: false,
    });
    expectAllStartWith(
      templateFiles(actions),
      "scaffold/templates/app/tui/plain/",
    );
  });

  it("scaffolds an effect tui app from app/tui/effect templates", () => {
    const actions = buildScaffoldActions({
      type: "app",
      framework: "tui",
      useEffect: true,
    });
    expectAllStartWith(
      templateFiles(actions),
      "scaffold/templates/app/tui/effect/",
    );
  });

  it("scaffolds a hono app via shell-out, no effect patch when disabled", () => {
    const actions = buildScaffoldActions({
      type: "app",
      framework: "hono",
      useEffect: false,
    });
    expect(actionTypes(actions)).toEqual([
      "createHonoApp",
      "symlinkAgentsMd",
      "installWorkspace",
    ]);
  });

  it("scaffolds a hono app with effect patch when enabled", () => {
    const actions = buildScaffoldActions({
      type: "app",
      framework: "hono",
      useEffect: true,
    });
    expect(actionTypes(actions)).toEqual([
      "createHonoApp",
      "patchHonoEffect",
      "symlinkAgentsMd",
      "installWorkspace",
    ]);
  });

  it("scaffolds an elysia app via shell-out, no effect patch when disabled", () => {
    const actions = buildScaffoldActions({
      type: "app",
      framework: "elysia",
      useEffect: false,
    });
    expect(actionTypes(actions)).toEqual([
      "createElysiaApp",
      "symlinkAgentsMd",
      "installWorkspace",
    ]);
  });

  it("scaffolds an elysia app with effect patch when enabled", () => {
    const actions = buildScaffoldActions({
      type: "app",
      framework: "elysia",
      useEffect: true,
    });
    expect(actionTypes(actions)).toEqual([
      "createElysiaApp",
      "patchElysiaEffect",
      "symlinkAgentsMd",
      "installWorkspace",
    ]);
  });

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

  it("scaffolds an astro app via shell-out, no effect patch when disabled", () => {
    const actions = buildScaffoldActions({
      type: "app",
      framework: "astro",
      useEffect: false,
    });
    expect(actionTypes(actions)).toEqual([
      "createAstroApp",
      "symlinkAgentsMd",
      "installWorkspace",
    ]);
  });

  it("scaffolds an astro app with effect patch when enabled", () => {
    const actions = buildScaffoldActions({
      type: "app",
      framework: "astro",
      useEffect: true,
    });
    expect(actionTypes(actions)).toEqual([
      "createAstroApp",
      "patchAstroEffect",
      "symlinkAgentsMd",
      "installWorkspace",
    ]);
  });

  it("scaffolds a postgresql database library with the right flavor templates", () => {
    const effect = buildScaffoldActions({
      type: "library",
      libraryKind: "database",
      engine: "postgresql",
      useEffect: true,
    });
    expectAllStartWith(
      templateFiles(effect),
      "scaffold/templates/library/database/postgresql/effect/",
    );

    const plain = buildScaffoldActions({
      type: "library",
      libraryKind: "database",
      engine: "postgresql",
      useEffect: false,
    });
    expectAllStartWith(
      templateFiles(plain),
      "scaffold/templates/library/database/postgresql/plain/",
    );
  });

  it("includes the queries template for sqlite database libraries only", () => {
    const sqliteEffect = buildScaffoldActions({
      type: "library",
      libraryKind: "database",
      engine: "sqlite",
      useEffect: true,
    });
    expect(templateFiles(sqliteEffect)).toContain(
      "scaffold/templates/library/database/sqlite/effect/src-queries.ts.hbs",
    );

    const pgEffect = buildScaffoldActions({
      type: "library",
      libraryKind: "database",
      engine: "postgresql",
      useEffect: true,
    });
    expect(templateFiles(pgEffect)).not.toContain(
      "scaffold/templates/library/database/postgresql/effect/src-queries.ts.hbs",
    );
  });

  it("creates hono apps with create-hono's Bun template (no --install; workspace install runs separately)", () => {
    expect(buildCreateHonoCommand("/repo", "api")).toEqual({
      command: "bun",
      args: [
        "create",
        "hono@latest",
        "api",
        "--template",
        "bun",
        "--pm",
        "bun",
      ],
      cwd: "/repo/apps",
    });
  });

  it("creates elysia apps via `bun create elysia <name>` (cwd=apps/)", () => {
    expect(buildCreateElysiaCommand("/repo", "api")).toEqual({
      command: "bun",
      args: ["create", "elysia", "api"],
      cwd: "/repo/apps",
    });
  });

  it("creates nitro apps via `bun create nitro-app@latest <name> --no-install` (cwd=apps/)", () => {
    expect(buildCreateNitroCommand("/repo", "api")).toEqual({
      command: "bun",
      args: ["create", "nitro-app@latest", "api", "--no-install"],
      cwd: "/repo/apps",
    });
  });

  it("creates astro apps from the official minimal template without installing locally", () => {
    expect(buildCreateAstroCommand("/repo", "site")).toEqual({
      command: "bun",
      args: [
        "create",
        "astro@latest",
        "site",
        "--template",
        "minimal",
        "--no-install",
        "--no-git",
        "--yes",
      ],
      cwd: "/repo/apps",
    });
  });

  it("generates a Hono handler backed by Effect", () => {
    const source = buildHonoEffectIndexSource();
    expect(source).toContain('import { Console, Effect } from "effect";');
    expect(source).toContain('import { Hono } from "hono";');
    expect(source).toContain("Effect.runPromise");
    expect(source).toContain("export default app;");
  });

  it("generates an Elysia handler backed by Effect", () => {
    const source = buildElysiaEffectIndexSource();
    expect(source).toContain('import { Console, Effect } from "effect";');
    expect(source).toContain('import { Elysia } from "elysia";');
    expect(source).toContain("Effect.runPromise");
    expect(source).toContain(".listen(3000)");
  });

  it("generates a Nitro handler backed by Effect", () => {
    const source = buildNitroEffectIndexSource();
    expect(source).toContain('import { Console, Effect } from "effect";');
    expect(source).toContain('import { defineHandler } from "nitro";');
    expect(source).toContain("Effect.runPromise");
    expect(source).toContain("defineHandler");
  });

  it("generates an Astro page backed by Effect", () => {
    const source = buildAstroEffectIndexSource();
    expect(source).toContain('import { Console, Effect } from "effect";');
    expect(source).toContain("Effect.runPromise");
    expect(source).toContain("<h1>{message}</h1>");
  });

  it("emits an app tsconfig that extends the @repo/typescript-config base", () => {
    const tsconfig = JSON.parse(buildAppTsconfig()) as {
      extends: string;
      compilerOptions: Record<string, unknown>;
      include: string[];
    };
    expect(tsconfig.extends).toBe(
      "@repo/typescript-config/tsconfig.base.json",
    );
    expect(tsconfig.compilerOptions).toMatchObject({
      module: "NodeNext",
      moduleResolution: "NodeNext",
      noEmit: true,
      composite: false,
      rootDir: ".",
    });
    expect(tsconfig.include).toEqual(["src/**/*"]);
  });

  it("patches app tsconfig with Effect language service config", () => {
    const tsconfig = JSON.parse(
      buildEffectTsconfig({
        extends: "astro/tsconfigs/base",
        compilerOptions: {
          jsx: "preserve",
        },
        include: [".astro/types.d.ts", "src/**/*"],
      }),
    ) as {
      $schema: string;
      extends: string;
      compilerOptions: {
        jsx: string;
        plugins: Array<{ name: string }>;
      };
      include: string[];
    };

    expect(tsconfig.$schema).toBe(
      "./node_modules/@effect/language-service/schema.json",
    );
    expect(tsconfig.extends).toBe("astro/tsconfigs/base");
    expect(tsconfig.compilerOptions.jsx).toBe("preserve");
    expect(tsconfig.compilerOptions.plugins).toContainEqual({
      name: "@effect/language-service",
    });
    expect(tsconfig.include).toEqual([".astro/types.d.ts", "src/**/*"]);
  });

  it("patches app package.json with Effect runtime and language service setup", () => {
    const pkg = JSON.parse(
      buildEffectPackageJson({
        name: "site",
        scripts: {
          dev: "astro dev",
        },
        dependencies: {
          astro: "^5.0.0",
        },
        devDependencies: {},
      }),
    ) as {
      scripts: Record<string, string>;
      dependencies: Record<string, string>;
      devDependencies: Record<string, string>;
    };

    expect(pkg.scripts.dev).toBe("astro dev");
    expect(pkg.scripts.prepare).toBe("effect-language-service patch");
    expect(pkg.dependencies.effect).toBe("catalog:");
    expect(pkg.devDependencies["@effect/language-service"]).toBe("catalog:");
    expect(pkg.devDependencies.typescript).toBe("catalog:");
  });
});
