import { basename } from "node:path";
import { Database } from "@repo/database";
import { eq } from "@repo/database/drizzle";
import { DrizzleError } from "@repo/database/errors";
import { sessionEvents, sessions } from "@repo/database/schema";
import { Effect } from "effect";
import { deriveStatus, type HookAgent } from "./derive-status.ts";

export interface HookFields {
  readonly sessionId?: string | undefined;
  readonly cwd?: string | undefined;
  readonly toolName?: string | undefined;
  readonly notificationType?: string | undefined;
  readonly eventName?: string | undefined;
}

function parseRecord(rawPayload: string): Record<string, unknown> {
  const trimmed = rawPayload.trim();
  if (!trimmed) return {};
  try {
    const parsed: unknown = JSON.parse(trimmed);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? (parsed as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

function stringField(record: Record<string, unknown>, ...keys: string[]): string | undefined {
  for (const key of keys) {
    const value = record[key];
    if (typeof value === "string" && value.length > 0) return value;
  }
  return undefined;
}

/** Best-effort extraction of the fields the status model cares about from a raw hook payload. */
export function extractHookFields(rawPayload: string): HookFields {
  const record = parseRecord(rawPayload);
  return {
    sessionId: stringField(record, "session_id", "sessionId"),
    cwd: stringField(record, "cwd"),
    toolName: stringField(record, "tool_name", "toolName"),
    notificationType: stringField(record, "notification_type", "notificationType"),
    eventName: stringField(record, "hook_event_name", "hookEventName"),
  };
}

export interface ApplyHookEventInput {
  /** Which agent fired the hook — implied by the CLI subcommand. */
  readonly agent: HookAgent;
  /** Event name from the CLI argv/env; falls back to the payload's own field. */
  readonly eventName: string;
  /** Raw hook JSON from stdin, stored verbatim on the event row. */
  readonly rawPayload: string;
  /** Working directory to record when the payload omits `cwd` (typically the hook's cwd). */
  readonly fallbackCwd: string;
  /** Timestamp for the event and session rows (injected for testability). */
  readonly now: Date;
}

/**
 * Records a hook event and reconciles the session it belongs to, in one
 * transaction: appends to `session_events`, then upserts the `sessions` row,
 * deriving the new status from the event. Status is only changed when the event
 * carries status meaning (last-write-wins); every event bumps `updatedAt`.
 */
export const applyHookEvent = Effect.fn("actions.applyHookEvent")(function* (input: ApplyHookEventInput) {
  const db = yield* Database;
  const fields = extractHookFields(input.rawPayload);
  const eventName = input.eventName || fields.eventName || "unknown";
  const cwd = fields.cwd ?? input.fallbackCwd;
  const sessionId = fields.sessionId;
  const payload = input.rawPayload.trim() ? input.rawPayload : "{}";
  const status = deriveStatus(input.agent, eventName, { notificationType: fields.notificationType });

  yield* Effect.try({
    try: () =>
      db.transaction((tx) => {
        tx.insert(sessionEvents)
          .values({
            sessionId: sessionId ?? null,
            eventName,
            toolName: fields.toolName ?? null,
            cwd,
            payload,
            createdAt: input.now,
          })
          .run();

        if (!sessionId) return;

        const existing = tx.select().from(sessions).where(eq(sessions.sessionId, sessionId)).get();
        if (existing) {
          tx.update(sessions)
            .set({
              ...(status ? { status } : {}),
              workingDirectory: cwd,
              updatedAt: input.now,
            })
            .where(eq(sessions.sessionId, sessionId))
            .run();
        } else {
          // Name the session after its directory — hooks carry no title, and
          // a recognisable name beats echoing the opaque session id (readers
          // still fall back per-row when this yields nothing).
          const directoryName = basename(cwd);
          tx.insert(sessions)
            .values({
              sessionId,
              status: status ?? "IDLE",
              agent: input.agent,
              sessionName: directoryName.length > 0 ? directoryName : sessionId,
              workingDirectory: cwd,
              createdAt: input.now,
              updatedAt: input.now,
            })
            .run();
        }
      }),
    catch: DrizzleError.fromUnknown,
  });
});
