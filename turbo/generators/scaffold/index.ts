import { execFileSync, execSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import type { PlopTypes } from "@turbo/gen";

const KEBAB_CASE = /^[a-z0-9]+(-[a-z0-9]+)*$/;

type ProjectType = "library" | "app";
type LibraryKind = "blank" | "database";
type Engine = "postgresql" | "sqlite";
type Framework = "bun" | "tui" | "hono" | "elysia" | "nitro" | "astro";

interface ScaffoldAnswers {
  type: ProjectType;
  libraryKind?: LibraryKind;
  engine?: Engine;
  framework?: Framework;
  useEffect: boolean;
  packageName: string;
  description: string;
  author: string;
}

type ScaffoldShape = Pick<
  ScaffoldAnswers,
  "type" | "libraryKind" | "engine" | "framework" | "useEffect"
>;

const SUBDIR: Record<ProjectType, string> = {
  library: "packages",
  app: "apps",
};

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

const DATABASE_EXTRA_FILES: ReadonlyArray<readonly [string, string]> = [
  ["src-schema.ts.hbs", "src/schema.ts"],
  ["src-client.ts.hbs", "src/client.ts"],
  ["drizzle.config.ts.hbs", "drizzle.config.ts"],
  ["drizzle-gitkeep.hbs", "drizzle/.gitkeep"],
];

const DATABASE_SQLITE_EXTRA: ReadonlyArray<readonly [string, string]> = [
  ["src-queries.ts.hbs", "src/queries.ts"],
];

const LIBRARY_FILES: ReadonlyArray<readonly [string, string]> = [
  ...COMMON_FILES,
  ...LIBRARY_EXTRA_FILES,
];

const DATABASE_COMMON_FILES: ReadonlyArray<readonly [string, string]> = [
  ...COMMON_FILES,
  ...LIBRARY_EXTRA_FILES,
  ...DATABASE_EXTRA_FILES,
];

const DATABASE_SQLITE_FILES: ReadonlyArray<readonly [string, string]> = [
  ...DATABASE_COMMON_FILES,
  ...DATABASE_SQLITE_EXTRA,
];

function templateBase(answers: ScaffoldShape): string {
  const flavor = answers.useEffect ? "effect" : "plain";
  if (answers.type === "app") {
    return `scaffold/templates/app/${answers.framework}/${flavor}`;
  }
  if (answers.libraryKind === "database") {
    return `scaffold/templates/library/database/${answers.engine}/${flavor}`;
  }
  return `scaffold/templates/library/blank/${flavor}`;
}

function fileListFor(
  answers: Pick<ScaffoldShape, "type" | "libraryKind" | "engine">,
): ReadonlyArray<readonly [string, string]> {
  if (answers.type === "app") return COMMON_FILES;
  if (answers.libraryKind === "database") {
    return answers.engine === "sqlite"
      ? DATABASE_SQLITE_FILES
      : DATABASE_COMMON_FILES;
  }
  return LIBRARY_FILES;
}

function validateName(
  input: string,
  workspaceRoot: string,
  type: ProjectType,
): true | string {
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

interface CommandSpec {
  command: string;
  args: string[];
  cwd: string;
}

export function buildCreateHonoCommand(
  workspaceRoot: string,
  packageName: string,
): CommandSpec {
  return {
    command: "bun",
    args: [
      "create",
      "hono@latest",
      packageName,
      "--template",
      "bun",
      "--pm",
      "bun",
    ],
    cwd: path.join(workspaceRoot, SUBDIR.app),
  };
}

export function buildCreateElysiaCommand(
  workspaceRoot: string,
  packageName: string,
): CommandSpec {
  return {
    command: "bun",
    args: ["create", "elysia", packageName],
    cwd: path.join(workspaceRoot, SUBDIR.app),
  };
}

export function buildHonoEffectIndexSource(): string {
  return `import { Console, Effect } from "effect";
import { Hono } from "hono";

const app = new Hono();

app.get("/", (c) =>
  Effect.runPromise(
    Effect.gen(function* () {
      yield* Console.log("GET /");
      return c.text("Hello Hono with Effect!");
    }),
  ),
);

export default app;
`;
}

export function buildElysiaEffectIndexSource(): string {
  return `import { Console, Effect } from "effect";
import { Elysia } from "elysia";

const app = new Elysia()
  .get("/", () =>
    Effect.runPromise(
      Effect.gen(function* () {
        yield* Console.log("GET /");
        return "Hello Elysia with Effect!";
      }),
    ),
  )
  .listen(3000);

console.log(
  \`🦊 Elysia is running at \${app.server?.hostname}:\${app.server?.port}\`,
);
`;
}

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

export function buildCreateAstroCommand(
  workspaceRoot: string,
  packageName: string,
): CommandSpec {
  return {
    command: "bun",
    args: [
      "create",
      "astro@latest",
      packageName,
      "--template",
      "minimal",
      "--no-install",
      "--no-git",
      "--yes",
    ],
    cwd: path.join(workspaceRoot, SUBDIR.app),
  };
}

export function buildAppTsconfig(): string {
  return `${JSON.stringify(
    {
      extends: "@repo/typescript-config/tsconfig.base.json",
      compilerOptions: {
        module: "NodeNext",
        moduleResolution: "NodeNext",
        noEmit: true,
        composite: false,
        declaration: false,
        declarationMap: false,
        rootDir: ".",
      },
      include: ["src/**/*"],
      exclude: ["node_modules"],
    },
    null,
    2,
  )}\n`;
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

export function buildAstroEffectIndexSource(): string {
  return `---
import { Console, Effect } from "effect";

const message = await Effect.runPromise(
  Effect.gen(function* () {
    yield* Console.log("GET /");
    return "Hello Astro with Effect!";
  }),
);
---

<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width" />
    <title>Astro</title>
  </head>
  <body>
    <h1>{message}</h1>
  </body>
</html>
`;
}

type ShellOutFramework = "hono" | "elysia" | "nitro" | "astro";

interface FrameworkConfig {
  label: string;
  entryFile: string;
  buildCommand: (workspaceRoot: string, packageName: string) => CommandSpec;
  buildEffectIndexSource: () => string;
  postCreate?: (workspaceRoot: string, packageName: string) => void;
}

function applyRepoTsconfig(workspaceRoot: string, packageName: string): void {
  const appDir = path.join(workspaceRoot, SUBDIR.app, packageName);
  writeFileSync(path.join(appDir, "tsconfig.json"), buildAppTsconfig());
  updatePackageJson(appDir, (pkg) => {
    pkg.devDependencies = {
      ...pkg.devDependencies,
      "@repo/typescript-config": "workspace:*",
    };
  });
}

const FRAMEWORK_CONFIGS: Record<ShellOutFramework, FrameworkConfig> = {
  hono: {
    label: "Hono",
    entryFile: "src/index.ts",
    buildCommand: buildCreateHonoCommand,
    buildEffectIndexSource: buildHonoEffectIndexSource,
    postCreate: applyRepoTsconfig,
  },
  elysia: {
    label: "Elysia",
    entryFile: "src/index.ts",
    buildCommand: buildCreateElysiaCommand,
    buildEffectIndexSource: buildElysiaEffectIndexSource,
    postCreate: applyRepoTsconfig,
  },
  nitro: {
    label: "Nitro",
    entryFile: "server/api/hello.ts",
    buildCommand: buildCreateNitroCommand,
    buildEffectIndexSource: buildNitroEffectIndexSource,
    postCreate: (workspaceRoot, packageName) => {
      const appDir = path.join(workspaceRoot, SUBDIR.app, packageName);
      updatePackageJson(appDir, (pkg) => {
        pkg.name = packageName;
      });
      rmSync(path.join(appDir, "AGENTS.md"), { force: true });
    },
  },
  astro: {
    label: "Astro",
    entryFile: "src/pages/index.astro",
    buildCommand: buildCreateAstroCommand,
    buildEffectIndexSource: buildAstroEffectIndexSource,
  },
};

function isShellOutFramework(fw?: Framework): fw is ShellOutFramework {
  return fw !== undefined && fw in FRAMEWORK_CONFIGS;
}

export function buildScaffoldActions(
  answers: ScaffoldShape,
): PlopTypes.ActionType[] {
  if (answers.type === "app" && isShellOutFramework(answers.framework)) {
    const { label } = FRAMEWORK_CONFIGS[answers.framework];
    const actions: PlopTypes.ActionType[] = [{ type: `create${label}App` }];
    if (answers.useEffect) actions.push({ type: `patch${label}Effect` });
    actions.push({ type: "symlinkAgentsMd" });
    actions.push({ type: "installWorkspace" });
    return actions;
  }

  const root = `{{ turbo.paths.root }}/${SUBDIR[answers.type]}/{{ packageName }}`;
  const tplBase = templateBase(answers);
  const files = fileListFor(answers);

  return [
    ...files.map(([template, output]) => ({
      type: "add",
      path: `${root}/${output}`,
      templateFile: `${tplBase}/${template}`,
    })),
    { type: "symlinkAgentsMd" },
  ];
}

export function getScaffoldPrompts(
  workspaceRoot: string,
): PlopTypes.PromptQuestion[] {
  return [
    {
      type: "list",
      name: "type",
      message: "What are you scaffolding?",
      choices: [
        { name: "library (packages/<name>)", value: "library" },
        { name: "app (apps/<name>)", value: "app" },
      ],
      default: "library",
    },
    {
      type: "list",
      name: "libraryKind",
      message: "Library kind?",
      choices: [
        { name: "Blank", value: "blank" },
        { name: "Database (Drizzle)", value: "database" },
      ],
      default: "blank",
      when: (answers: Pick<ScaffoldAnswers, "type">) =>
        answers.type === "library",
    },
    {
      type: "list",
      name: "engine",
      message: "Which database engine?",
      choices: [
        { name: "PostgreSQL", value: "postgresql" },
        { name: "SQLite (Bun)", value: "sqlite" },
      ],
      when: (answers: Pick<ScaffoldAnswers, "libraryKind">) =>
        answers.libraryKind === "database",
    },
    {
      type: "list",
      name: "framework",
      message: "Which framework?",
      choices: [
        { name: "Bun (no framework)", value: "bun" },
        { name: "TUI", value: "tui" },
        { name: "Hono", value: "hono" },
        { name: "Elysia", value: "elysia" },
        { name: "Nitro", value: "nitro" },
        { name: "Astro", value: "astro" },
      ],
      default: "bun",
      when: (answers: Pick<ScaffoldAnswers, "type">) => answers.type === "app",
    },
    {
      type: "confirm",
      name: "useEffect",
      message: "Use Effect?",
      default: true,
    },
    {
      type: "input",
      name: "packageName",
      message: (answers: Pick<ScaffoldAnswers, "type">) =>
        `Name (kebab-case, becomes ${SUBDIR[answers.type]}/<name>):`,
      validate: (input: string, answers: Pick<ScaffoldAnswers, "type">) =>
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
  ];
}

type PackageJson = {
  name?: string;
  scripts?: Record<string, string>;
  dependencies?: Record<string, string>;
  devDependencies?: Record<string, string>;
};

type TsconfigJson = {
  $schema?: string;
  compilerOptions?: {
    plugins?: Array<{ name?: string } & Record<string, unknown>>;
  } & Record<string, unknown>;
} & Record<string, unknown>;

function updatePackageJson(
  appDir: string,
  mutate: (pkg: PackageJson) => void,
): void {
  const pkgPath = path.join(appDir, "package.json");
  const pkg = JSON.parse(readFileSync(pkgPath, "utf8")) as PackageJson;
  mutate(pkg);
  writeFileSync(pkgPath, `${JSON.stringify(pkg, null, 2)}\n`);
}

export function buildEffectTsconfig(tsconfig: TsconfigJson): string {
  const plugins = tsconfig.compilerOptions?.plugins ?? [];
  const hasEffectPlugin = plugins.some(
    (plugin) => plugin.name === "@effect/language-service",
  );

  return `${JSON.stringify(
    {
      ...tsconfig,
      $schema: "./node_modules/@effect/language-service/schema.json",
      compilerOptions: {
        ...tsconfig.compilerOptions,
        plugins: hasEffectPlugin
          ? plugins
          : [...plugins, { name: "@effect/language-service" }],
      },
    },
    null,
    2,
  )}\n`;
}

export function buildEffectPackageJson(pkg: PackageJson): string {
  return `${JSON.stringify(
    {
      ...pkg,
      scripts: {
        ...pkg.scripts,
        prepare: pkg.scripts?.prepare ?? "effect-language-service patch",
      },
      dependencies: {
        ...pkg.dependencies,
        effect: pkg.dependencies?.effect ?? "catalog:",
      },
      devDependencies: {
        ...pkg.devDependencies,
        "@effect/language-service":
          pkg.devDependencies?.["@effect/language-service"] ?? "catalog:",
        typescript: pkg.devDependencies?.typescript ?? "catalog:",
      },
    },
    null,
    2,
  )}\n`;
}

function patchEffectTsconfig(appDir: string): void {
  const tsconfigPath = path.join(appDir, "tsconfig.json");
  const tsconfig = JSON.parse(
    readFileSync(tsconfigPath, "utf8"),
  ) as TsconfigJson;
  writeFileSync(tsconfigPath, buildEffectTsconfig(tsconfig));
}

function patchEffectPackageJson(appDir: string): void {
  const pkgPath = path.join(appDir, "package.json");
  const pkg = JSON.parse(readFileSync(pkgPath, "utf8")) as PackageJson;
  writeFileSync(pkgPath, buildEffectPackageJson(pkg));
}

function patchAppEffectInstall(
  workspaceRoot: string,
  packageName: string,
  entryFile: string,
  indexSource: string,
): void {
  const appDir = path.join(workspaceRoot, SUBDIR.app, packageName);
  patchEffectPackageJson(appDir);
  patchEffectTsconfig(appDir);
  writeFileSync(path.join(appDir, entryFile), indexSource);
}

export function registerScaffoldGenerator(
  plop: PlopTypes.NodePlopAPI,
): void {
  const workspaceRoot = plop.getDestBasePath();

  plop.setActionType("symlinkAgentsMd", (rawAnswers) => {
    const answers = rawAnswers as ScaffoldAnswers;
    const dir = path.join(
      workspaceRoot,
      SUBDIR[answers.type],
      answers.packageName,
    );
    symlinkSync("CLAUDE.md", path.join(dir, "AGENTS.md"));
    return `symlinked AGENTS.md -> CLAUDE.md in ${SUBDIR[answers.type]}/${answers.packageName}`;
  });

  plop.setActionType("installWorkspace", () => {
    execFileSync("bun", ["install"], {
      cwd: workspaceRoot,
      stdio: "inherit",
    });
    return "ran bun install at workspace root";
  });

  for (const config of Object.values(FRAMEWORK_CONFIGS)) {
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
  }

  plop.setGenerator("scaffold", {
    description:
      "Scaffold a library, application, or database package (Effect or plain)",
    prompts: getScaffoldPrompts(workspaceRoot),
    actions: (data) => {
      if (!data) return [];
      return buildScaffoldActions(data as ScaffoldShape);
    },
  });
}
