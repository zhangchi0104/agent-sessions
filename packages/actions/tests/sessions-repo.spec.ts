import { Database as BunDatabase } from "bun:sqlite";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "@effect/vitest";
import { layer as databaseLayer } from "@repo/database/client";
import * as schema from "@repo/database/schema";
import { drizzle } from "drizzle-orm/bun-sqlite";
import { migrate } from "drizzle-orm/bun-sqlite/migrator";
import { Effect, Layer } from "effect";
import { SessionsRepo } from "../src/sessions-repo.ts";

const databasePaths = new Set<string>();
const migrationsFolder = fileURLToPath(new URL("../../database/drizzle", import.meta.url));

afterEach(() => {
  for (const path of databasePaths) {
    Bun.file(path)
      .delete()
      .catch(() => undefined);
  }
  databasePaths.clear();
});

describe("SessionsRepo", () => {
  it.effect("createSession inserts and listSessions returns it", () =>
    Effect.gen(function* () {
      const databasePath = yield* Effect.sync(createTestDatabase);
      const layer = SessionsRepo.layerDrizzle.pipe(Layer.provide(databaseLayer({ filename: databasePath })));

      yield* Effect.gen(function* () {
        const repo = yield* SessionsRepo;
        const timestamp = new Date("2026-05-01T00:00:00.000Z");
        const created = yield* repo.createSession({
          sessionId: "repo-session-1",
          agent: "Codex",
          sessionName: "Repo test session",
          workingDirectory: "/repo/agent-sessions",
          createdAt: timestamp,
          updatedAt: timestamp,
        });

        expect(created).toMatchObject({
          id: 1,
          sessionId: "repo-session-1",
          status: "IDLE",
          agent: "Codex",
        });

        const sessions = yield* repo.listSessions({});
        expect(sessions.map((s) => s.sessionId)).toEqual(["repo-session-1"]);
      }).pipe(Effect.provide(layer));
    }),
  );

  it.effect("listSessions forwards filters", () =>
    Effect.gen(function* () {
      const databasePath = yield* Effect.sync(createTestDatabase);
      const layer = SessionsRepo.layerDrizzle.pipe(Layer.provide(databaseLayer({ filename: databasePath })));

      yield* Effect.gen(function* () {
        const repo = yield* SessionsRepo;
        const ts = (iso: string) => new Date(iso);

        yield* repo.createSession({
          sessionId: "match",
          status: "RUNNING",
          agent: "ClaudeCode",
          sessionName: "Match",
          workingDirectory: "/repo/match",
          createdAt: ts("2026-05-03T10:00:00.000Z"),
          updatedAt: ts("2026-05-03T10:00:00.000Z"),
        });
        yield* repo.createSession({
          sessionId: "wrong-agent",
          status: "RUNNING",
          agent: "Codex",
          sessionName: "Wrong agent",
          workingDirectory: "/repo/match",
          createdAt: ts("2026-05-03T10:00:00.000Z"),
          updatedAt: ts("2026-05-03T10:00:00.000Z"),
        });

        const result = yield* repo.listSessions({
          agent: "ClaudeCode",
          status: "RUNNING",
          workingDirectory: "/repo/match",
        });
        expect(result.map((s) => s.sessionId)).toEqual(["match"]);
      }).pipe(Effect.provide(layer));
    }),
  );
});

function createTestDatabase() {
  const databasePath = join(tmpdir(), `actions-sessions-repo-${crypto.randomUUID()}.db`);
  const client = new BunDatabase(databasePath);
  const database = drizzle({ client, schema });
  migrate(database, { migrationsFolder });
  client.close();
  databasePaths.add(databasePath);
  return databasePath;
}
