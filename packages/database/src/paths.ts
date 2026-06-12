import { homedir } from "node:os";
import { join } from "node:path";

/** Canonical SQLite path shared by the hook CLI (writer) and the TUI (reader). */
export const DEFAULT_DATABASE_PATH = join(homedir(), ".local", "agent-sessions", "sessions.db");

/** The canonical path, overridable via `AGENT_SESSIONS_DB`. */
export function resolveDatabasePath(): string {
  const override = process.env.AGENT_SESSIONS_DB;
  return override && override.length > 0 ? override : DEFAULT_DATABASE_PATH;
}
