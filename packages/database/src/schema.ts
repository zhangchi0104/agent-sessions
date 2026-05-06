import { integer, sqliteTable, text } from "drizzle-orm/sqlite-core";

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
