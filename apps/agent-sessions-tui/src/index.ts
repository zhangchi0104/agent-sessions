import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { parseArgs } from "node:util";
import { createCliRenderer } from "@opentui/core";
import { SessionsRepo } from "@repo/actions";
import { layer as databaseLayer, migrate, resolveDatabasePath } from "@repo/database";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import { mountUi } from "./tui.ts";

const { values } = parseArgs({
  args: process.argv.slice(2),
  options: {
    db: { type: "string" },
  },
  strict: true,
});
const db = values.db ?? resolveDatabasePath();
mkdirSync(dirname(db), { recursive: true });

const appLayer = SessionsRepo.layerDrizzle.pipe(Layer.provideMerge(databaseLayer({ filename: db })));

const loadSessions = Effect.gen(function* () {
  yield* migrate;
  const repo = yield* SessionsRepo;
  return yield* repo.listSessions({});
}).pipe(Effect.provide(appLayer));

const list = await Effect.runPromise(loadSessions).catch((error: unknown) => {
  process.stdout.write(`\nError loading sessions: ${String(error)}\n`);
  process.exit(1);
});

const renderer = await createCliRenderer({ exitOnCtrlC: true });
mountUi(renderer, list);
renderer.start();

renderer.keyInput.on("keypress", (key) => {
  if (key.name === "q") {
    renderer.destroy();
    process.exit(0);
  }
});
