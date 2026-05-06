import { Database } from "@repo/database";
import type { DrizzleError } from "@repo/database/errors";
import type { sessions } from "@repo/database/schema";
import type { AppDatabase } from "@repo/database/types";
import * as Console from "effect/Console";
import * as Context from "effect/Context";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";

interface ISessionsRepo {
  listSessions: () => Effect.Effect<(typeof sessions.$inferSelect)[], DrizzleError>;
  // createSession: (
  //   payload: typeof sessions.$inferInsert,
  // ) => Effect.Effect<typeof sessions.$inferSelect, DrizzleError>;
}
export class SessionsRepo extends Context.Service<SessionsRepo, ISessionsRepo>()("@actions/Sessions") {
  static layerDrizzle = Effect.gen(function* () {
    yield* Console.log("foo");

    return SessionsRepo.of({
      listSessions: Effect.gen(function* () {}),
    });
  }).pipe(Layer.effect(SessionsRepo));
}
