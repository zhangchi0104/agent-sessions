import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";

type HookPayload = Record<string, unknown>;

const eventName = process.argv[2] ?? process.env.AGENT_SESSIONS_HOOK_EVENT ?? "unknown";

try {
  const stdin = await Bun.stdin.text();
  const payload = parsePayload(stdin);
  const databasePath = getDatabasePath();

  ensureDatabaseDirectory(databasePath);

  const database = new Database(databasePath, { create: true });
  try {
    createSchema(database);
    insertEvent(database, {
      sessionId: stringField(payload, "session_id", "sessionId"),
      eventName: stringField(payload, "hook_event_name", "hookEventName") ?? eventName,
      toolName: stringField(payload, "tool_name", "toolName"),
      cwd: stringField(payload, "cwd") ?? process.cwd(),
      payload: serializePayload(stdin, payload),
      createdAt: Date.now(),
    });
  } finally {
    database.close();
  }
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`[codex-session-event-writer] failed to write hook event: ${message}`);
}

function createSchema(database: Database) {
  database.exec(`
    create table if not exists session_events (
      id integer primary key autoincrement,
      session_id text,
      event_name text not null,
      tool_name text,
      cwd text,
      payload text not null,
      created_at integer not null
    );

    create index if not exists session_events_session_id_idx on session_events (session_id);
    create index if not exists session_events_event_name_idx on session_events (event_name);
    create index if not exists session_events_created_at_idx on session_events (created_at);
  `);
}

function insertEvent(
  database: Database,
  event: {
    sessionId?: string;
    eventName: string;
    toolName?: string;
    cwd?: string;
    payload: string;
    createdAt: number;
  },
) {
  database
    .query(`
      insert into session_events (
        session_id,
        event_name,
        tool_name,
        cwd,
        payload,
        created_at
      ) values (?, ?, ?, ?, ?, ?)
    `)
    .run(
      event.sessionId ?? null,
      event.eventName,
      event.toolName ?? null,
      event.cwd ?? null,
      event.payload,
      event.createdAt,
    );
}

function parsePayload(stdin: string): HookPayload {
  const trimmed = stdin.trim();
  if (!trimmed) {
    return {};
  }

  try {
    const parsed = JSON.parse(trimmed);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed as HookPayload;
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

function getDatabasePath() {
  if (process.env.DATABASE_PATH) {
    return process.env.DATABASE_PATH;
  }
  if (process.env.AGENT_SESSIONS_DATABASE_PATH) {
    return process.env.AGENT_SESSIONS_DATABASE_PATH;
  }

  const home = process.env.HOME;
  if (!home) {
    throw new Error("DATABASE_PATH or HOME must be set");
  }
  return join(home, ".codex", "agent-sessions", "local.db");
}

function ensureDatabaseDirectory(databasePath: string) {
  if (databasePath === ":memory:") {
    return;
  }
  mkdirSync(dirname(databasePath), { recursive: true });
}
