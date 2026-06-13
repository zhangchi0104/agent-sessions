import { Database as BunDatabase } from "bun:sqlite";
import { afterAll, expect, test } from "bun:test";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { drizzle } from "drizzle-orm/bun-sqlite";
import { migrate as drizzleMigrate } from "drizzle-orm/bun-sqlite/migrator";
import { Effect } from "effect";
import { layer as databaseLayer } from "../src/client.ts";
import { ensureSchema } from "../src/ensure-schema.ts";

const migrationsFolder = fileURLToPath(new URL("../drizzle", import.meta.url));
const tempPaths = new Set<string>();

afterAll(() => {
  for (const path of tempPaths) {
    for (const suffix of ["", "-wal", "-shm"]) {
      Bun.file(`${path}${suffix}`)
        .delete()
        .catch(() => undefined);
    }
  }
});

function tempPath(label: string) {
  const path = join(tmpdir(), `database-ensure-schema-${label}-${crypto.randomUUID()}.db`);
  tempPaths.add(path);
  return path;
}

type ColumnInfo = { name: string; type: string; notnull: number; pk: number; dflt_value: unknown };

function tableInfo(database: BunDatabase, table: string) {
  return (database.query(`PRAGMA table_info(${table})`).all() as ColumnInfo[]).map((column) => ({
    name: column.name,
    type: column.type,
    notnull: column.notnull,
    pk: column.pk,
    dflt: column.dflt_value,
  }));
}

function indexNames(database: BunDatabase, table: string) {
  return (database.query(`PRAGMA index_list(${table})`).all() as { name: string }[])
    .map((index) => index.name)
    .filter((name) => !name.startsWith("sqlite_autoindex_"))
    .sort();
}

function snapshot(path: string) {
  const database = new BunDatabase(path);
  try {
    return {
      sessions: tableInfo(database, "sessions"),
      sessionEvents: tableInfo(database, "session_events"),
      sessionIndexes: indexNames(database, "sessions"),
      sessionEventIndexes: indexNames(database, "session_events"),
    };
  } finally {
    database.close();
  }
}

test("ensureSchema produces the same schema as the Drizzle migrations", async () => {
  const migratedPath = tempPath("migrated");
  const migratedClient = new BunDatabase(migratedPath);
  drizzleMigrate(drizzle({ client: migratedClient }), { migrationsFolder });
  migratedClient.close();

  const ensuredPath = tempPath("ensured");
  await Effect.runPromise(Effect.scoped(ensureSchema.pipe(Effect.provide(databaseLayer({ filename: ensuredPath })))));

  expect(snapshot(ensuredPath)).toEqual(snapshot(migratedPath));
});

test("ensureSchema is idempotent", async () => {
  const path = tempPath("idempotent");
  const run = Effect.scoped(ensureSchema.pipe(Effect.provide(databaseLayer({ filename: path }))));
  await Effect.runPromise(run);
  await expect(Effect.runPromise(run)).resolves.toBeUndefined();
});
