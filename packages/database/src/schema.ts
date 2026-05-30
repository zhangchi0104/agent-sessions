import { index, integer, sqliteTable, text } from "drizzle-orm/sqlite-core";

export const sessions = sqliteTable("sessions", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  sessionId: text("session_id").notNull().unique(),
  status: text("status", { enum: ["IDLE", "RUNNING", "PENDING_APPROVAL"] })
    .notNull()
    .default("IDLE"),

  agent: text("agent", { enum: ["ClaudeCode", "Codex", "OpenCode"] }).notNull(),
  sessionName: text("session_name").notNull(),
  workingDirectory: text("working_directory").notNull(),
  createdAt: integer("created_at", { mode: "timestamp" }).notNull(),
  updatedAt: integer("updated_at", { mode: "timestamp" }).notNull(),
});

export const sessionEvents = sqliteTable(
  "session_events",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    sessionId: text("session_id"),
    eventName: text("event_name").notNull(),
    toolName: text("tool_name"),
    cwd: text("cwd"),
    payload: text("payload").notNull(),
    createdAt: integer("created_at", { mode: "timestamp" }).notNull(),
  },
  (table) => [
    index("session_events_session_id_idx").on(table.sessionId),
    index("session_events_event_name_idx").on(table.eventName),
    index("session_events_created_at_idx").on(table.createdAt),
  ],
);
