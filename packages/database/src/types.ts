import type { SQLiteBunDatabase } from "drizzle-orm/bun-sqlite";
import type * as schema from "./schema.js";
export type AppDatabase = SQLiteBunDatabase<typeof schema>;
export type AgentNames = (typeof schema.sessions.agent.enumValues)[number];
export type SessionStatus = (typeof schema.sessions.status.enumValues)[number];
