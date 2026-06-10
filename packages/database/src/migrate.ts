import { fileURLToPath } from "node:url";
import { migrate as drizzleMigrate } from "drizzle-orm/bun-sqlite/migrator";
import * as Effect from "effect/Effect";
import { Database } from "./client.ts";

const migrationsFolder = fileURLToPath(new URL("../drizzle", import.meta.url));

export const migrate = Effect.gen(function* () {
  const db = yield* Database;
  yield* Effect.sync(() => drizzleMigrate(db, { migrationsFolder }));
});
