import { Database } from "@repo/database";
import type { DrizzleError } from "@repo/database/errors";
import type { sessionEvents, sessions } from "@repo/database/schema";
import * as Context from "effect/Context";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import { createSession, createSessionEvent, listSessionEvents, listSessions } from "./helpers/session-helpers.ts";

type Session = typeof sessions.$inferSelect;
type CreateSessionPayload = typeof sessions.$inferInsert;
type SessionEvent = typeof sessionEvents.$inferSelect;
type CreateSessionEventPayload = typeof sessionEvents.$inferInsert;
type ListSessionsFilters = Parameters<typeof listSessions>[0];
type ListSessionEventsFilters = Parameters<typeof listSessionEvents>[0];

interface ISessionsRepo {
  listSessions: (filters: ListSessionsFilters) => Effect.Effect<Session[], DrizzleError>;
  createSession: (payload: CreateSessionPayload) => Effect.Effect<Session, DrizzleError>;
  listSessionEvents: (filters: ListSessionEventsFilters) => Effect.Effect<SessionEvent[], DrizzleError>;
  createSessionEvent: (payload: CreateSessionEventPayload) => Effect.Effect<SessionEvent, DrizzleError>;
}

export class SessionsRepo extends Context.Service<SessionsRepo, ISessionsRepo>()("@actions/Sessions") {
  static layerDrizzle = Layer.effect(
    SessionsRepo,
    Effect.gen(function* () {
      const db = yield* Database;
      const provideDb = Effect.provideService(Database, db);

      return SessionsRepo.of({
        listSessions: (filters) => listSessions(filters).pipe(provideDb),
        createSession: (payload) => createSession(payload).pipe(provideDb),
        listSessionEvents: (filters) => listSessionEvents(filters).pipe(provideDb),
        createSessionEvent: (payload) => createSessionEvent(payload).pipe(provideDb),
      });
    }),
  );
}
