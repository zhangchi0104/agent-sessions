import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { drizzle } from "drizzle-orm/bun-sqlite";
import { migrate } from "drizzle-orm/bun-sqlite/migrator";
import * as schema from "../src/schema.ts";

const eventName = process.argv[2] ?? process.env.AGENT_SESSIONS_HOOK_EVENT ?? "unknown";
const migrationsFolder = fileURLToPath(new URL("../drizzle", import.meta.url));

type HookPayload = Record<string, unknown>;

try {
  const stdin = await Bun.stdin.text();
  const payload = parsePayload(stdin);
  const databasePath = process.env.DATABASE_PATH ?? "./local.db";

  ensureDatabaseDirectory(databasePath);

  const database = new Database(databasePath, { create: true });
  try {
    const db = drizzle({ client: database, schema });
    migrate(db, { migrationsFolder });
    db.insert(schema.sessionEvents)
      .values({
        sessionId: stringField(payload, "session_id", "sessionId"),
        eventName: stringField(payload, "hook_event_name", "hookEventName") ?? eventName,
        toolName: stringField(payload, "tool_name", "toolName"),
        cwd: stringField(payload, "cwd") ?? process.cwd(),
        payload: serializePayload(stdin, payload),
        createdAt: new Date(),
      })
      .run();
  } finally {
    database.close();
  }
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`[codex-session-event-writer] failed to write hook event: ${message}`);
}

function parsePayload(stdin: string): HookPayload {
  const trimmed = stdin.trim();
  if (!trimmed) {
    return {};
  }

  try {
    const parsed = JSON.parse(trimmed);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
    return { value: parsed };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return { raw: stdin, parseError: message };
  }
}

function serializePayload(stdin: string, payload: HookPayload) {
  const trimmed = stdin.trim();
  if (trimmed) {
    return trimmed;
  }
  return JSON.stringify(payload);
}

function stringField(payload: HookPayload, ...keys: string[]) {
  for (const key of keys) {
    const value = payload[key];
    if (typeof value === "string" && value.length > 0) {
      return value;
    }
  }
  return undefined;
}

function ensureDatabaseDirectory(databasePath: string) {
  if (databasePath === ":memory:") {
    return;
  }
  mkdirSync(dirname(databasePath), { recursive: true });
}
