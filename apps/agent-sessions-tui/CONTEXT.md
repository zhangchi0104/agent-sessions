# Agent Sessions

Tracks the live coding-agent **Sessions** a user has running (Claude Code, Codex) and what each one is currently waiting on, so the user can see at a glance which session needs their attention. A hook-driven CLI records lifecycle events and derives each Session's **Status**; the TUI displays them.

## Language

**Session**:
A single coding-agent conversation/process the user launched, identified by a `sessionId` that the agent provides. Belongs to exactly one **Agent** (Claude Code, Codex, …) and one working directory.
_Avoid_: using "session" for a billing/usage period — that concept belongs to the TokenStats context, not here.

**Session Status**:
What a Session is currently waiting on — the answer to *"who do we wait on?"*. Exactly one of **RUNNING**, **PENDING_APPROVAL**, or **IDLE**. Derived from the stream of **Hook Events**, never set by the user directly.

**RUNNING**:
The agent is actively working; the user is the one waiting.

**PENDING_APPROVAL**:
The agent has paused mid-task and is blocked waiting for the user to approve or answer something (a tool/permission prompt, an elicitation). The work is not finished — it is suspended pending a user decision.
_Avoid_: treating this as "done" — it is an interruption, not a turn boundary.

**IDLE**:
The agent is at rest — it has finished its turn and is waiting for the user's next prompt, **or the session has ended** (Claude `SessionEnd` / Codex equivalent). The user is the one who must act, but nothing is blocked mid-task. IDLE deliberately does not distinguish "between turns" from "ended"; both read as "nothing is happening, your move."
_Avoid_: reading IDLE as "the agent is busy" — IDLE always means the agent is not working.

**Hook Event**:
A single invocation the coding agent makes against the CLI at a lifecycle moment (e.g. a prompt was submitted, a tool is about to run, the turn stopped). Recorded append-only as a Session Event; some Hook Events drive a Session Status transition. The set of event names and their shapes differ per Agent.

**Agent**:
The coding tool that owns a Session — `ClaudeCode`, `Codex`, or `OpenCode`. Each Agent has its own Hook Event vocabulary that the CLI normalizes into the shared Session Status model.
