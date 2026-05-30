# TokenStats

A macOS status bar app that shows how much of a Coding Agent's usage allowance has been consumed and when it resets. Claude Code is supported first; Codex support is being shaped behind the same trust bar.

## Language

**Usage Window**:
A rolling time period over which a Coding Agent meters usage against a quota, with enough authoritative data for TokenStats to show consumption and reset timing. Claude Code has two: a ~5-hour window (the primary gauge) and a 7-day weekly window (secondary). The app's central concept — "how much have I used, and when does it reset." In the Claude Code API these are `five_hour` and `seven_day` (see `docs/claude-code-integration.md`). Codex data should be called a Usage Window only if discovery confirms the same kind of trusted consumption/reset concept.
_Avoid_: Session (means a conversation, not a billing period), quota period.

Claude Code can also return an `extra_usage` usage-credit meter. It is not a Usage Window because no reset timestamp is exposed, but TokenStats may display it in the same list when the 5-hour and weekly windows are zero/null placeholders and credits are the only meaningful quota value.

> **Flagged ambiguity — "session limit":** Claude Code's own UI calls the 5-hour Usage Window the "session limit" and the weekly one the "weekly limit." We do **not** adopt "session limit," because **Session** here means a conversation. The 5-hour period is always a **Usage Window**.

**Limit**:
The maximum usage allowed within a Usage Window. Consumption is shown as a percentage of this.
_Avoid_: Cap, allowance (when referring to the metered ceiling specifically).

**Session**:
A single Claude Code conversation/process the user launched. NOT a billing period — that's a Usage Window.
_Avoid_: using "session" to mean the 5-hour reset period.

**Coding Agent**:
An AI coding tool whose usage TokenStats tracks. Each Coding Agent exposes one or more **Usage Windows** in a normalized shape (label, percent consumed, and reset time when available), so the UI never depends on a specific agent. Claude Code is the first Coding Agent; Codex is being added as another.
_Avoid_: provider, vendor (note: "UsageProvider" is the code seam that adapts one Coding Agent — not a synonym for the agent itself).

**Codex**:
An OpenAI Coding Agent whose authoritative Usage Windows TokenStats should track only after they are empirically confirmed. Codex is not a generic name for all OpenAI usage or API billing.
_Avoid_: OpenAI usage, API usage, ChatGPT usage (unless specifically referring to the login identity).
