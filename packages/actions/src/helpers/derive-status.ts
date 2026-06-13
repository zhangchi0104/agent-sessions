import type { AgentNames, SessionStatus } from "@repo/database";

/** Agents whose hooks feed the session-status model. */
export type HookAgent = Extract<AgentNames, "ClaudeCode" | "Codex">;

export interface DeriveStatusContext {
  /** Claude `Notification` discriminator (`permission_prompt`, `idle_prompt`, …). */
  readonly notificationType?: string | undefined;
}

const CLAUDE_RUNNING_EVENTS = new Set([
  "UserPromptSubmit",
  "PreToolUse",
  "PostToolUse",
  "PostToolBatch",
  "SubagentStart",
]);
const CODEX_RUNNING_EVENTS = new Set(["UserPromptSubmit", "PreToolUse", "PostToolUse"]);
const IDLE_EVENTS = new Set(["Stop", "SessionEnd"]);

/**
 * Maps a hook event to the session status it should transition to, following the
 * "who are we waiting on?" model. Returns `null` when the event carries no status
 * meaning (log-only) and the current status should be preserved.
 *
 * The mapping differs per agent: Codex has no `PermissionRequest` hook, so any
 * Codex `Notification` is treated as "agent needs the user" (PENDING_APPROVAL),
 * whereas Claude discriminates on `notification_type`.
 */
export function deriveStatus(
  agent: HookAgent,
  eventName: string,
  context: DeriveStatusContext = {},
): SessionStatus | null {
  if (agent === "ClaudeCode") {
    if (eventName === "PermissionRequest") return "PENDING_APPROVAL";
    if (eventName === "Notification") {
      if (context.notificationType === "permission_prompt") return "PENDING_APPROVAL";
      if (context.notificationType === "idle_prompt") return "IDLE";
      return null;
    }
    if (CLAUDE_RUNNING_EVENTS.has(eventName)) return "RUNNING";
    if (IDLE_EVENTS.has(eventName)) return "IDLE";
    return null;
  }

  // Codex
  if (eventName === "Notification") return "PENDING_APPROVAL";
  if (CODEX_RUNNING_EVENTS.has(eventName)) return "RUNNING";
  if (IDLE_EVENTS.has(eventName)) return "IDLE";
  return null;
}
