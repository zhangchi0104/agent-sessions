import { Database as BunDatabase } from "bun:sqlite";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "@effect/vitest";
import { Database, layer as databaseLayer } from "@repo/database/client";
import { DrizzleError } from "@repo/database/errors";
import * as schema from "@repo/database/schema";
import { drizzle } from "drizzle-orm/bun-sqlite";
import { migrate } from "drizzle-orm/bun-sqlite/migrator";
import { Effect, Layer } from "effect";
import { createSession, listSessions } from "../src/helpers/session-helpers.ts";

type SessionPayload = Parameters<typeof createSession>[0];

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

describe("session helpers", () => {
  it.effect("createSession inserts and returns a session", () =>
    Effect.gen(function* () {
      const databasePath = yield* Effect.sync(createTestDatabase);
      const payload = sessionPayload({
        sessionId: "session-create",
        sessionName: "Create session",
      });

      const result = yield* runWithDatabase(createSession(payload), databasePath);

      expect(result).toMatchObject({
        id: 1,
        sessionId: "session-create",
        status: "IDLE",
        agent: "Codex",
        sessionName: "Create session",
        workingDirectory: "/repo/agent-sessions",
      });
      expect(result.createdAt).toEqual(payload.createdAt);
      expect(result.updatedAt).toEqual(payload.updatedAt);
    }),
  );

  it.effect("listSessions returns sessions newest first", () =>
    Effect.gen(function* () {
      const databasePath = yield* Effect.sync(createTestDatabase);
      yield* runWithDatabase(
        Effect.all([
          createSession(
            sessionPayload({
              sessionId: "old-session",
              sessionName: "Old session",
              createdAt: new Date("2026-05-01T10:00:00.000Z"),
              updatedAt: new Date("2026-05-01T10:00:00.000Z"),
            }),
          ),
          createSession(
            sessionPayload({
              sessionId: "new-session",
              sessionName: "New session",
              createdAt: new Date("2026-05-02T10:00:00.000Z"),
              updatedAt: new Date("2026-05-02T10:00:00.000Z"),
            }),
          ),
        ]),
        databasePath,
      );

      const result = yield* runWithDatabase(listSessions({}), databasePath);

      expect(result.map((session) => session.sessionId)).toEqual(["new-session", "old-session"]);
    }),
  );

  it.effect("listSessions applies all filters", () =>
    Effect.gen(function* () {
      const databasePath = yield* Effect.sync(createTestDatabase);
      yield* runWithDatabase(
        Effect.all([
          createSession(
            sessionPayload({
              sessionId: "matching-session",
              status: "RUNNING",
              agent: "ClaudeCode",
              workingDirectory: "/repo/matching",
              createdAt: new Date("2026-05-03T10:00:00.000Z"),
            }),
          ),
          createSession(
            sessionPayload({
              sessionId: "wrong-agent",
              status: "RUNNING",
              agent: "Codex",
              workingDirectory: "/repo/matching",
              createdAt: new Date("2026-05-03T10:00:00.000Z"),
            }),
          ),
          createSession(
            sessionPayload({
              sessionId: "too-old",
              status: "RUNNING",
              agent: "ClaudeCode",
              workingDirectory: "/repo/matching",
              createdAt: new Date("2026-05-01T10:00:00.000Z"),
            }),
          ),
          createSession(
            sessionPayload({
              sessionId: "wrong-directory",
              status: "RUNNING",
              agent: "ClaudeCode",
              workingDirectory: "/repo/other",
              createdAt: new Date("2026-05-03T10:00:00.000Z"),
            }),
          ),
        ]),
        databasePath,
      );

      const result = yield* runWithDatabase(
        listSessions({
          agent: "ClaudeCode",
          workingDirectory: "/repo/matching",
          status: "RUNNING",
          fromTimestamp: new Date("2026-05-02T00:00:00.000Z"),
          toTimestamp: new Date("2026-05-04T00:00:00.000Z"),
        }),
        databasePath,
      );

      expect(result.map((session) => session.sessionId)).toEqual(["matching-session"]);
    }),
  );

  it.effect("createSession maps database failures to DrizzleError", () =>
    Effect.gen(function* () {
      const failingDatabase = Layer.succeed(Database, {
        insert: () => {
          throw new Error("insert failed");
        },
      } as never);

      const error = yield* createSession(
        sessionPayload({
          sessionId: "failing-session",
        }),
      ).pipe(Effect.provide(failingDatabase), Effect.flip);

      expect(error).toBeInstanceOf(DrizzleError);
      expect(error.message).toBe("insert failed");
    }),
  );
});

function runWithDatabase<A, E>(effect: Effect.Effect<A, E, Database>, databasePath: string) {
  return effect.pipe(Effect.provide(databaseLayer({ filename: databasePath })));
}

function createTestDatabase() {
  const databasePath = join(tmpdir(), `actions-session-helpers-${crypto.randomUUID()}.db`);
  const client = new BunDatabase(databasePath);
  const database = drizzle({ client, schema });
  migrate(database, { migrationsFolder });
  client.close();
  databasePaths.add(databasePath);
  return databasePath;
}

function sessionPayload(overrides: Partial<SessionPayload> = {}): SessionPayload {
  const timestamp = new Date("2026-05-01T00:00:00.000Z");
  return {
    sessionId: "session-1",
    status: "IDLE",
    agent: "Codex",
    sessionName: "Test session",
    workingDirectory: "/repo/agent-sessions",
    createdAt: timestamp,
    updatedAt: timestamp,
    ...overrides,
  };
}
