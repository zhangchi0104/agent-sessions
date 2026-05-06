import * as Schema from "effect/Schema";

export const hookEventNames = [
  "SessionStart",
  "Setup",
  "InstructionsLoaded",
  "UserPromptSubmit",
  "UserPromptExpansion",
  "PreToolUse",
  "PermissionRequest",
  "PostToolUse",
  "PostToolUseFailure",
  "PostToolBatch",
  "PermissionDenied",
  "Notification",
  "SubagentStart",
  "SubagentStop",
  "TaskCreated",
  "TaskCompleted",
  "Stop",
  "StopFailure",
  "TeammateIdle",
  "ConfigChange",
  "CwdChanged",
  "FileChanged",
  "WorktreeCreate",
  "WorktreeRemove",
  "PreCompact",
  "PostCompact",
  "SessionEnd",
  "Elicitation",
  "ElicitationResult",
] as const;

export const HookEventNameSchema = Schema.Literals(hookEventNames);
export type HookEventName = Schema.Schema.Type<typeof HookEventNameSchema>;

export const HookPermissionModeSchema = Schema.Literals([
  "default",
  "plan",
  "acceptEdits",
  "auto",
  "dontAsk",
  "bypassPermissions",
] as const);
export type HookPermissionMode = Schema.Schema.Type<
  typeof HookPermissionModeSchema
>;

const hookEventBaseFields = {
  session_id: Schema.String,
  transcript_path: Schema.String,
  cwd: Schema.String,
  permission_mode: Schema.optionalKey(HookPermissionModeSchema),
};

export const HookToolInputSchema = Schema.Record(Schema.String, Schema.Unknown);
export type HookToolInput = Schema.Schema.Type<typeof HookToolInputSchema>;

export const HookToolCallSchema = Schema.Struct({
  tool_name: Schema.String,
  tool_input: HookToolInputSchema,
  tool_use_id: Schema.String,
  tool_response: Schema.optionalKey(Schema.Unknown),
});
export type HookToolCall = Schema.Schema.Type<typeof HookToolCallSchema>;

export const HookPermissionDestinationSchema = Schema.Literals([
  "session",
  "userSettings",
  "projectSettings",
  "localSettings",
] as const);

export const HookPermissionRuleSchema = Schema.Struct({
  toolName: Schema.String,
  ruleContent: Schema.optionalKey(Schema.String),
});

export const HookPermissionUpdateSchema = Schema.Union([
  Schema.Struct({
    type: Schema.Literals(["addRules", "replaceRules", "removeRules"] as const),
    rules: Schema.Array(HookPermissionRuleSchema),
    behavior: Schema.Literals(["allow", "deny", "ask"] as const),
    destination: Schema.optionalKey(HookPermissionDestinationSchema),
  }),
  Schema.Struct({
    type: Schema.Literal("setMode"),
    mode: Schema.Literals([
      "default",
      "plan",
      "acceptEdits",
      "dontAsk",
      "bypassPermissions",
    ] as const),
    destination: Schema.optionalKey(HookPermissionDestinationSchema),
  }),
  Schema.Struct({
    type: Schema.Literals(["addDirectories", "removeDirectories"] as const),
    directories: Schema.Array(Schema.String),
    destination: Schema.optionalKey(HookPermissionDestinationSchema),
  }),
]);
export type HookPermissionUpdate = Schema.Schema.Type<
  typeof HookPermissionUpdateSchema
>;

export const SessionStartHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("SessionStart"),
  source: Schema.Literals(["startup", "resume", "clear", "compact"] as const),
  model: Schema.String,
  agent_type: Schema.optionalKey(Schema.String),
});
export type SessionStartHookEvent = Schema.Schema.Type<
  typeof SessionStartHookEventSchema
>;

export const SetupHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("Setup"),
  trigger: Schema.Literals(["init", "maintenance"] as const),
});
export type SetupHookEvent = Schema.Schema.Type<typeof SetupHookEventSchema>;

export const InstructionsLoadedHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("InstructionsLoaded"),
  file_path: Schema.String,
  memory_type: Schema.Literals([
    "User",
    "Project",
    "Local",
    "Managed",
  ] as const),
  load_reason: Schema.Literals([
    "session_start",
    "nested_traversal",
    "path_glob_match",
    "include",
    "compact",
  ] as const),
  globs: Schema.optionalKey(Schema.Array(Schema.String)),
  trigger_file_path: Schema.optionalKey(Schema.String),
  parent_file_path: Schema.optionalKey(Schema.String),
});
export type InstructionsLoadedHookEvent = Schema.Schema.Type<
  typeof InstructionsLoadedHookEventSchema
>;

export const UserPromptSubmitHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("UserPromptSubmit"),
  prompt: Schema.String,
});
export type UserPromptSubmitHookEvent = Schema.Schema.Type<
  typeof UserPromptSubmitHookEventSchema
>;

export const UserPromptExpansionHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("UserPromptExpansion"),
  expansion_type: Schema.Literals(["slash_command", "mcp_prompt"] as const),
  command_name: Schema.String,
  command_args: Schema.String,
  command_source: Schema.String,
  prompt: Schema.String,
});
export type UserPromptExpansionHookEvent = Schema.Schema.Type<
  typeof UserPromptExpansionHookEventSchema
>;

export const PreToolUseHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("PreToolUse"),
  tool_name: Schema.String,
  tool_input: HookToolInputSchema,
  tool_use_id: Schema.String,
});
export type PreToolUseHookEvent = Schema.Schema.Type<
  typeof PreToolUseHookEventSchema
>;

export const PermissionRequestHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("PermissionRequest"),
  tool_name: Schema.String,
  tool_input: HookToolInputSchema,
  permission_suggestions: Schema.optionalKey(
    Schema.Array(HookPermissionUpdateSchema),
  ),
});
export type PermissionRequestHookEvent = Schema.Schema.Type<
  typeof PermissionRequestHookEventSchema
>;

export const PostToolUseHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("PostToolUse"),
  tool_name: Schema.String,
  tool_input: HookToolInputSchema,
  tool_response: Schema.Unknown,
  tool_use_id: Schema.String,
  duration_ms: Schema.optionalKey(Schema.Number),
});
export type PostToolUseHookEvent = Schema.Schema.Type<
  typeof PostToolUseHookEventSchema
>;

export const PostToolUseFailureHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("PostToolUseFailure"),
  tool_name: Schema.String,
  tool_input: HookToolInputSchema,
  tool_use_id: Schema.String,
  error: Schema.String,
  is_interrupt: Schema.optionalKey(Schema.Boolean),
  duration_ms: Schema.optionalKey(Schema.Number),
});
export type PostToolUseFailureHookEvent = Schema.Schema.Type<
  typeof PostToolUseFailureHookEventSchema
>;

export const PostToolBatchHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("PostToolBatch"),
  tool_calls: Schema.Array(HookToolCallSchema),
});
export type PostToolBatchHookEvent = Schema.Schema.Type<
  typeof PostToolBatchHookEventSchema
>;

export const PermissionDeniedHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("PermissionDenied"),
  tool_name: Schema.String,
  tool_input: HookToolInputSchema,
  tool_use_id: Schema.String,
  reason: Schema.String,
});
export type PermissionDeniedHookEvent = Schema.Schema.Type<
  typeof PermissionDeniedHookEventSchema
>;

export const NotificationHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("Notification"),
  message: Schema.String,
  title: Schema.optionalKey(Schema.String),
  notification_type: Schema.Literals([
    "permission_prompt",
    "idle_prompt",
    "auth_success",
    "elicitation_dialog",
    "elicitation_complete",
    "elicitation_response",
  ] as const),
});
export type NotificationHookEvent = Schema.Schema.Type<
  typeof NotificationHookEventSchema
>;

export const SubagentStartHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("SubagentStart"),
  agent_id: Schema.String,
  agent_type: Schema.String,
});
export type SubagentStartHookEvent = Schema.Schema.Type<
  typeof SubagentStartHookEventSchema
>;

export const SubagentStopHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("SubagentStop"),
  stop_hook_active: Schema.Boolean,
  agent_id: Schema.String,
  agent_type: Schema.String,
  agent_transcript_path: Schema.String,
  last_assistant_message: Schema.String,
});
export type SubagentStopHookEvent = Schema.Schema.Type<
  typeof SubagentStopHookEventSchema
>;

const taskHookEventFields = {
  task_id: Schema.String,
  task_subject: Schema.String,
  task_description: Schema.optionalKey(Schema.String),
  teammate_name: Schema.optionalKey(Schema.String),
  team_name: Schema.optionalKey(Schema.String),
};

export const TaskCreatedHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("TaskCreated"),
  ...taskHookEventFields,
});
export type TaskCreatedHookEvent = Schema.Schema.Type<
  typeof TaskCreatedHookEventSchema
>;

export const TaskCompletedHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("TaskCompleted"),
  ...taskHookEventFields,
});
export type TaskCompletedHookEvent = Schema.Schema.Type<
  typeof TaskCompletedHookEventSchema
>;

export const StopHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("Stop"),
  stop_hook_active: Schema.Boolean,
  last_assistant_message: Schema.String,
});
export type StopHookEvent = Schema.Schema.Type<typeof StopHookEventSchema>;

export const StopFailureHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("StopFailure"),
  error: Schema.Literals([
    "rate_limit",
    "authentication_failed",
    "oauth_org_not_allowed",
    "billing_error",
    "invalid_request",
    "server_error",
    "max_output_tokens",
    "unknown",
  ] as const),
  error_details: Schema.optionalKey(Schema.String),
  last_assistant_message: Schema.optionalKey(Schema.String),
});
export type StopFailureHookEvent = Schema.Schema.Type<
  typeof StopFailureHookEventSchema
>;

export const TeammateIdleHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("TeammateIdle"),
  teammate_name: Schema.String,
  team_name: Schema.String,
});
export type TeammateIdleHookEvent = Schema.Schema.Type<
  typeof TeammateIdleHookEventSchema
>;

export const ConfigChangeHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("ConfigChange"),
  source: Schema.Literals([
    "user_settings",
    "project_settings",
    "local_settings",
    "policy_settings",
    "skills",
  ] as const),
  file_path: Schema.optionalKey(Schema.String),
});
export type ConfigChangeHookEvent = Schema.Schema.Type<
  typeof ConfigChangeHookEventSchema
>;

export const CwdChangedHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("CwdChanged"),
  old_cwd: Schema.String,
  new_cwd: Schema.String,
});
export type CwdChangedHookEvent = Schema.Schema.Type<
  typeof CwdChangedHookEventSchema
>;

export const FileChangedHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("FileChanged"),
  file_path: Schema.String,
  event: Schema.Literals(["change", "add", "unlink"] as const),
});
export type FileChangedHookEvent = Schema.Schema.Type<
  typeof FileChangedHookEventSchema
>;

export const WorktreeCreateHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("WorktreeCreate"),
  name: Schema.String,
  source_path: Schema.optionalKey(Schema.String),
});
export type WorktreeCreateHookEvent = Schema.Schema.Type<
  typeof WorktreeCreateHookEventSchema
>;

export const WorktreeRemoveHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("WorktreeRemove"),
  worktree_path: Schema.String,
});
export type WorktreeRemoveHookEvent = Schema.Schema.Type<
  typeof WorktreeRemoveHookEventSchema
>;

export const PreCompactHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("PreCompact"),
  trigger: Schema.Literals(["manual", "auto"] as const),
  custom_instructions: Schema.String,
});
export type PreCompactHookEvent = Schema.Schema.Type<
  typeof PreCompactHookEventSchema
>;

export const PostCompactHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("PostCompact"),
  trigger: Schema.Literals(["manual", "auto"] as const),
  compact_summary: Schema.String,
});
export type PostCompactHookEvent = Schema.Schema.Type<
  typeof PostCompactHookEventSchema
>;

export const SessionEndHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("SessionEnd"),
  reason: Schema.Literals([
    "clear",
    "resume",
    "logout",
    "prompt_input_exit",
    "bypass_permissions_disabled",
    "other",
  ] as const),
});
export type SessionEndHookEvent = Schema.Schema.Type<
  typeof SessionEndHookEventSchema
>;

export const ElicitationHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("Elicitation"),
  mcp_server_name: Schema.String,
  message: Schema.String,
  mode: Schema.optionalKey(Schema.Literals(["form", "url"] as const)),
  url: Schema.optionalKey(Schema.String),
  elicitation_id: Schema.optionalKey(Schema.String),
  requested_schema: Schema.optionalKey(Schema.Unknown),
});
export type ElicitationHookEvent = Schema.Schema.Type<
  typeof ElicitationHookEventSchema
>;

export const ElicitationResultHookEventSchema = Schema.Struct({
  ...hookEventBaseFields,
  hook_event_name: Schema.Literal("ElicitationResult"),
  mcp_server_name: Schema.String,
  action: Schema.Literals(["accept", "decline", "cancel"] as const),
  mode: Schema.optionalKey(Schema.Literals(["form", "url"] as const)),
  elicitation_id: Schema.optionalKey(Schema.String),
  content: Schema.optionalKey(Schema.Record(Schema.String, Schema.Unknown)),
});
export type ElicitationResultHookEvent = Schema.Schema.Type<
  typeof ElicitationResultHookEventSchema
>;

export const HookEventSchema = Schema.Union([
  SessionStartHookEventSchema,
  SetupHookEventSchema,
  InstructionsLoadedHookEventSchema,
  UserPromptSubmitHookEventSchema,
  UserPromptExpansionHookEventSchema,
  PreToolUseHookEventSchema,
  PermissionRequestHookEventSchema,
  PostToolUseHookEventSchema,
  PostToolUseFailureHookEventSchema,
  PostToolBatchHookEventSchema,
  PermissionDeniedHookEventSchema,
  NotificationHookEventSchema,
  SubagentStartHookEventSchema,
  SubagentStopHookEventSchema,
  TaskCreatedHookEventSchema,
  TaskCompletedHookEventSchema,
  StopHookEventSchema,
  StopFailureHookEventSchema,
  TeammateIdleHookEventSchema,
  ConfigChangeHookEventSchema,
  CwdChangedHookEventSchema,
  FileChangedHookEventSchema,
  WorktreeCreateHookEventSchema,
  WorktreeRemoveHookEventSchema,
  PreCompactHookEventSchema,
  PostCompactHookEventSchema,
  SessionEndHookEventSchema,
  ElicitationHookEventSchema,
  ElicitationResultHookEventSchema,
]);
export type HookEvent = Schema.Schema.Type<typeof HookEventSchema>;

export const HookSpecificOutputSchema = Schema.Union([
  Schema.Struct({
    hookEventName: Schema.Literals([
      "SessionStart",
      "Setup",
      "UserPromptSubmit",
      "UserPromptExpansion",
      "PostToolUse",
      "PostToolUseFailure",
      "PostToolBatch",
      "SubagentStart",
    ] as const),
    additionalContext: Schema.optionalKey(Schema.String),
    sessionTitle: Schema.optionalKey(Schema.String),
    updatedToolOutput: Schema.optionalKey(Schema.Unknown),
    updatedMCPToolOutput: Schema.optionalKey(Schema.Unknown),
  }),
  Schema.Struct({
    hookEventName: Schema.Literal("PreToolUse"),
    permissionDecision: Schema.optionalKey(
      Schema.Literals(["allow", "deny", "ask", "defer"] as const),
    ),
    permissionDecisionReason: Schema.optionalKey(Schema.String),
    updatedInput: Schema.optionalKey(HookToolInputSchema),
    additionalContext: Schema.optionalKey(Schema.String),
  }),
  Schema.Struct({
    hookEventName: Schema.Literal("PermissionRequest"),
    decision: Schema.optionalKey(
      Schema.Struct({
        behavior: Schema.Literals(["allow", "deny"] as const),
        updatedInput: Schema.optionalKey(HookToolInputSchema),
        updatedPermissions: Schema.optionalKey(
          Schema.Array(HookPermissionUpdateSchema),
        ),
        message: Schema.optionalKey(Schema.String),
        interrupt: Schema.optionalKey(Schema.Boolean),
      }),
    ),
  }),
  Schema.Struct({
    hookEventName: Schema.Literal("PermissionDenied"),
    retry: Schema.optionalKey(Schema.Boolean),
  }),
  Schema.Struct({
    hookEventName: Schema.Literal("WorktreeCreate"),
    worktreePath: Schema.String,
  }),
  Schema.Struct({
    hookEventName: Schema.Literals([
      "Elicitation",
      "ElicitationResult",
    ] as const),
    action: Schema.Literals(["accept", "decline", "cancel"] as const),
    content: Schema.optionalKey(Schema.Record(Schema.String, Schema.Unknown)),
  }),
]);
export type HookSpecificOutput = Schema.Schema.Type<
  typeof HookSpecificOutputSchema
>;

export const HookEventOutputSchema = Schema.Struct({
  continue: Schema.optionalKey(Schema.Boolean),
  stopReason: Schema.optionalKey(Schema.String),
  decision: Schema.optionalKey(Schema.Literal("block")),
  reason: Schema.optionalKey(Schema.String),
  suppressOutput: Schema.optionalKey(Schema.Boolean),
  systemMessage: Schema.optionalKey(Schema.String),
  hookSpecificOutput: Schema.optionalKey(HookSpecificOutputSchema),
  watchPaths: Schema.optionalKey(Schema.Array(Schema.String)),
});
export type HookEventOutput = Schema.Schema.Type<typeof HookEventOutputSchema>;
