import { sql } from "drizzle-orm";
import * as Effect from "effect/Effect";
import { Database } from "./client.ts";

/**
 * Idempotent DDL that mirrors the Drizzle migrations in `drizzle/`. Kept as an
 * inline string (not a `.sql` import) so it compiles into `dist/` via `tsc` and
 * embeds cleanly into a `bun build --compile` single-file binary, where the
 * on-disk migrations folder is not available. A drift test asserts this stays in
 * sync with the real migrations.
 */
const SCHEMA_STATEMENTS = [
  `CREATE TABLE IF NOT EXISTS sessions (
    id integer PRIMARY KEY AUTOINCREMENT NOT NULL,
    session_id text NOT NULL,
    status text DEFAULT 'IDLE' NOT NULL,
    agent text NOT NULL,
    session_name text NOT NULL,
    working_directory text NOT NULL,
    created_at integer NOT NULL,
    updated_at integer NOT NULL
  )`,
  `CREATE UNIQUE INDEX IF NOT EXISTS sessions_session_id_unique ON sessions (session_id)`,
  `CREATE TABLE IF NOT EXISTS session_events (
    id integer PRIMARY KEY AUTOINCREMENT NOT NULL,
    session_id text,
    event_name text NOT NULL,
    tool_name text,
    cwd text,
    payload text NOT NULL,
    created_at integer NOT NULL
  )`,
  `CREATE INDEX IF NOT EXISTS session_events_session_id_idx ON session_events (session_id)`,
  `CREATE INDEX IF NOT EXISTS session_events_event_name_idx ON session_events (event_name)`,
  `CREATE INDEX IF NOT EXISTS session_events_created_at_idx ON session_events (created_at)`,
] as const;

/**
 * Ensures the schema exists and the connection is tuned for concurrent hook
 * writers (WAL + a busy timeout). Safe to run on every invocation — every
 * statement is idempotent.
 */
export const ensureSchema = Effect.gen(function* () {
  const db = yield* Database;
  yield* Effect.sync(() => {
    db.run(sql.raw("PRAGMA journal_mode = WAL"));
    db.run(sql.raw("PRAGMA busy_timeout = 5000"));
    for (const statement of SCHEMA_STATEMENTS) {
      db.run(sql.raw(statement));
    }
  });
});
