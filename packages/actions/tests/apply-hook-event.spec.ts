import { Database as BunDatabase } from "bun:sqlite";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "@effect/vitest";
import { type Database, layer as databaseLayer } from "@repo/database/client";
import * as schema from "@repo/database/schema";
import { drizzle } from "drizzle-orm/bun-sqlite";
import { migrate } from "drizzle-orm/bun-sqlite/migrator";
import { Effect } from "effect";
import { type ApplyHookEventInput, applyHookEvent } from "../src/helpers/apply-hook-event.ts";
import { listSessionEvents, listSessions } from "../src/helpers/session-helpers.ts";

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

const NOW = new Date("2026-06-10T12:00:00.000Z");
const LATER = new Date("2026-06-10T12:05:00.000Z");

function input(overrides: Partial<ApplyHookEventInput> = {}): ApplyHookEventInput {
  return {
    agent: "ClaudeCode",
    eventName: "UserPromptSubmit",
    rawPayload: JSON.stringify({ session_id: "sess-1", cwd: "/repo/agent-sessions" }),
    fallbackCwd: "/fallback",
    now: NOW,
    ...overrides,
  };
}

describe("applyHookEvent", () => {
  it.effect("creates the session on first sight, named after the cwd basename", () =>
    Effect.gen(function* () {
      const databasePath = yield* Effect.sync(createTestDatabase);

      yield* runWithDatabase(applyHookEvent(input()), databasePath);

      const [session] = yield* runWithDatabase(listSessions({}), databasePath);
      expect(session).toMatchObject({
        sessionId: "sess-1",
        sessionName: "agent-sessions",
        status: "RUNNING",
        agent: "ClaudeCode",
        workingDirectory: "/repo/agent-sessions",
      });
      const events = yield* runWithDatabase(listSessionEvents({ sessionId: "sess-1" }), databasePath);
      expect(events).toHaveLength(1);
      expect(events[0]?.eventName).toBe("UserPromptSubmit");
    }),
  );

  it.effect("PermissionRequest then PostToolUse moves PENDING_APPROVAL back to RUNNING", () =>
    Effect.gen(function* () {
      const databasePath = yield* Effect.sync(createTestDatabase);

      yield* runWithDatabase(applyHookEvent(input()), databasePath);
      yield* runWithDatabase(applyHookEvent(input({ eventName: "PermissionRequest", now: LATER })), databasePath);
      const pending = yield* runWithDatabase(listSessions({}), databasePath);
      expect(pending[0]?.status).toBe("PENDING_APPROVAL");
      expect(pending[0]?.updatedAt).toEqual(LATER);

      yield* runWithDatabase(applyHookEvent(input({ eventName: "PostToolUse", now: LATER })), databasePath);
      const running = yield* runWithDatabase(listSessions({}), databasePath);
      expect(running[0]?.status).toBe("RUNNING");
    }),
  );

  it.effect("a log-only event preserves status but bumps updatedAt", () =>
    Effect.gen(function* () {
      const databasePath = yield* Effect.sync(createTestDatabase);

      yield* runWithDatabase(applyHookEvent(input({ eventName: "Stop" })), databasePath);
      yield* runWithDatabase(applyHookEvent(input({ eventName: "SubagentStop", now: LATER })), databasePath);

      const [session] = yield* runWithDatabase(listSessions({}), databasePath);
      expect(session?.status).toBe("IDLE");
      expect(session?.updatedAt).toEqual(LATER);
    }),
  );

  it.effect("Codex Notification sets PENDING_APPROVAL", () =>
    Effect.gen(function* () {
      const databasePath = yield* Effect.sync(createTestDatabase);

      yield* runWithDatabase(
        applyHookEvent(
          input({ agent: "Codex", eventName: "Notification", rawPayload: JSON.stringify({ session_id: "cx-1" }) }),
        ),
        databasePath,
      );

      const [session] = yield* runWithDatabase(listSessions({}), databasePath);
      expect(session).toMatchObject({ sessionId: "cx-1", status: "PENDING_APPROVAL", agent: "Codex" });
    }),
  );

  it.effect("an event without a session_id is logged without a session row", () =>
    Effect.gen(function* () {
      const databasePath = yield* Effect.sync(createTestDatabase);

      yield* runWithDatabase(
        applyHookEvent(input({ eventName: "Notification", rawPayload: JSON.stringify({ message: "hi" }) })),
        databasePath,
      );

      const sessions = yield* runWithDatabase(listSessions({}), databasePath);
      const events = yield* runWithDatabase(listSessionEvents({}), databasePath);
      expect(sessions).toHaveLength(0);
      expect(events).toHaveLength(1);
      expect(events[0]?.sessionId).toBeNull();
    }),
  );

  it.effect("falls back to fallbackCwd and stores empty payloads as {}", () =>
    Effect.gen(function* () {
      const databasePath = yield* Effect.sync(createTestDatabase);

      yield* runWithDatabase(
        applyHookEvent(input({ eventName: "SessionStart", rawPayload: "", fallbackCwd: "/cwd-fallback" })),
        databasePath,
      );

      const [session] = yield* runWithDatabase(listSessions({}), databasePath);
      // no session_id in payload -> no session row
      expect(session).toBeUndefined();
      const [event] = yield* runWithDatabase(listSessionEvents({}), databasePath);
      expect(event?.cwd).toBe("/cwd-fallback");
      expect(event?.payload).toBe("{}");
    }),
  );
});

function runWithDatabase<A, E>(effect: Effect.Effect<A, E, Database>, databasePath: string) {
  return effect.pipe(Effect.provide(databaseLayer({ filename: databasePath })));
}

function createTestDatabase() {
  const databasePath = join(tmpdir(), `actions-apply-hook-event-${crypto.randomUUID()}.db`);
  const client = new BunDatabase(databasePath);
  const database = drizzle({ client, schema });
  migrate(database, { migrationsFolder });
  client.close();
  databasePaths.add(databasePath);
  return databasePath;
}
