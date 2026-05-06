import { type AgentNames, Database, type SessionStatus } from "@repo/database";
import { and, desc, eq, gte, lte } from "@repo/database/drizzle";
import { DrizzleError } from "@repo/database/errors";
import { sessions } from "@repo/database/schema";
import { Effect } from "effect";

type CreateSessionPayload = typeof sessions.$inferInsert;
export const createSession = Effect.fn("actions.createSesssion")(function* (payload: CreateSessionPayload) {
  const db = yield* Database;
  const result = yield* Effect.try({
    try: () => db.insert(sessions).values(payload).returning().get(),
    catch: DrizzleError.fromUnknown,
  });
  return result;
});

type ListSessionsPayload = {
  agent?: AgentNames;
  workingDirectory?: string;
  status?: SessionStatus;
  fromTimestamp?: Date;
  toTimestamp?: Date;
};

export const listSessions = Effect.fn("actions.listSessions")(function* (filters: ListSessionsPayload) {
  const db = yield* Database;
  const result = yield* Effect.try({
    try: () => db.select().from(sessions).where(buildSessionsFilters(filters)).orderBy(desc(sessions.createdAt)).all(),
    catch: DrizzleError.fromUnknown,
  });
  return result;
});

function buildSessionsFilters(payload: ListSessionsPayload) {
  const filters = [];
  if (payload.agent) {
    filters.push(eq(sessions.agent, payload.agent));
  }
  if (payload.workingDirectory) {
    filters.push(eq(sessions.workingDirectory, payload.workingDirectory));
  }
  if (payload.status) {
    filters.push(eq(sessions.status, payload.status));
  }
  if (payload.fromTimestamp) {
    filters.push(gte(sessions.createdAt, payload.fromTimestamp));
  }
  if (payload.toTimestamp) {
    filters.push(lte(sessions.createdAt, payload.toTimestamp));
  }
  return and(...filters);
}
