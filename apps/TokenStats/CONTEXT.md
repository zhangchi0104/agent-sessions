# TokenStats

A native status-area app that shows how much of a Coding Agent's usage allowance has been consumed and when it resets. The original client is a macOS menu-bar app; a native Windows notification-area companion lives under `apps/TokenStats.Windows`.

## Language

**Usage Window**:
A rolling time period over which a Coding Agent meters usage against a quota, with enough authoritative data for TokenStats to show consumption and reset timing. Claude Code has three: a ~5-hour window (the primary gauge), a 7-day weekly window (secondary), and the weekly Fable-scoped window (third gauge). The app's central concept — "how much have I used, and when does it reset." In the Claude Code API the first two are `five_hour` and `seven_day`; the Fable one is the `limits` entry with `kind: "weekly_scoped"` scoped to the Fable model (see `docs/claude-code-integration.md`). Codex data should be called a Usage Window only if discovery confirms the same kind of trusted consumption/reset concept.
_Avoid_: session (in TokenStats a session is a conversation, never a billing period), quota period.

Claude Code can also return an `extra_usage` usage-credit meter. It is not a Usage Window because no reset timestamp is exposed, and TokenStats intentionally does not show it in the popover.

> **Flagged ambiguity — "session limit":** Claude Code's own UI calls the 5-hour Usage Window the "session limit" and the weekly one the "weekly limit." We do **not** adopt "session limit," because a session is a conversation, not a billing period. The 5-hour period is always a **Usage Window**.

**Token Odometer**:
The raw sum of tokens across a Coding Agent's transcript entries over a chosen time range — an informational *odometer*, **not** a quota measure. It carries no Limit and no reset semantics, and must never be presented as a **Usage Window**. Its source is the agent's local files (Claude Code: every transcript under `~/.claude/projects`, spanning all projects; Codex: every rollout under `~/.codex/sessions`), which is only an *estimate* of consumption — per ADR-0001 the authoritative quota figure comes from the usage endpoint, never from file sums. Windows may keep disposable, versioned per-file parse checkpoints under Local AppData (ADR-0007), but they are only an acceleration layer: deleting them rebuilds the same estimate from transcripts, and they never become a source of truth. The Codex figure is knowingly incomplete in a second way: `~/.codex/archived_sessions` is deliberately not scanned, so it omits roughly 1.2% of a 30-day total, and a past day's figure can shrink retroactively as its sessions are archived. The Token Odometer exists alongside the Usage Window as a separate, deliberately-unweighted "how much did I push through" figure, broken down by **Coding Agent**, then **Model**, then **Token Kind**.
_Avoid_: **Tokens Today** (retired — the measure is no longer bound to a single day, and nothing on screen is a single day's total); presenting the odometer or a Token Kind composition percentage as a quota percentage, a limit, or a remaining-quota figure; conflating it with the Usage Window gauge; describing the Windows parse cache as authoritative history.

**Model**:
The model a Coding Agent reported against the tokens it consumed — `claude-opus-5`, `gpt-5.6-sol`, `codex-auto-review`. The Token Odometer's second axis, nested under Coding Agent. A Model is whatever the transcript *names*, not whatever the user *chose*: `codex-auto-review` is spawned by Codex itself and never selected by anyone, and it still earns its own row, because the odometer answers where tokens went rather than what was picked.
_Avoid_: treating a Model as a user setting; folding agent-initiated Models into whatever spawned them (Codex records a parent link on only 43% of those runs, so the fold cannot be done honestly).

**Token Kind**:
One of the four disjoint ways a token is counted against a request: **direct input**, **output**, **cache write**, **cache read**. The Token Odometer's third axis, and the four columns of the Tokens tab; the raw Odometer total is their sum and no token is counted twice. In both native clients, each column heading is also an independent display filter. A disabled kind stays visible as a dimmed raw value, has no composition percentage, and is excluded from the percentage denominator. Cache read dominates almost everywhere but not uniformly — 67% to 97% of a Model's total — which is why the tab draws the proportion as well as printing the figures. Cache write is Claude-only: Codex reports `cached_input_tokens` (a read) and nothing else, so its cache-write figure is *structurally absent*, not zero by chance.
_Avoid_: "input" for the sum of direct input and the two cache kinds — direct input is one kind among four, and that sum has no name; "cache creation" (the API's field name; the glossary's word is cache write).

**Selected total**:
A table projection over the Token Odometer: the sum of the Token Kinds whose column headings are enabled, within the persisted Today, 7-day, or 30-day range. It drives filtered per-Agent and per-Model subtotals, model ordering, and composition percentages in both native clients; it does not drive the objective Billing/API-equivalent summary or Windows tray tooltip. Toggling a heading changes the selected total, not the parsed transcript records or the raw four-kind Token Odometer total. For a Model row, an enabled Token Kind's displayed percentage is its share of that row's selected total; a disabled kind retains only its dimmed raw value. The percentage is composition, never quota consumption. The presentation preference chooses **value**, **percentage**, or **value (percentage)** for enabled kinds, and the selected kinds survive process restarts.
_Avoid_: calling the selected total the Token Odometer total; treating a Token Kind percentage as a Usage Window percentage.

**Presentation settings**:
The preferences that change how existing readings are presented without changing their source data: objective Token summary, Token Kind figure format and selection, range, gauge style, and related status-area behavior. Windows groups these under **Display**; macOS keeps its equivalent choices under **Appearance**. Theme remains a separate concern.
_Avoid_: treating a presentation choice as a change to transcript accounting or Usage Window consumption.

**API-equivalent usage estimate**:
An optional presentation of Token Odometer records as an estimated USD value, derived from the Model recorded in each transcript entry and that Model's standard official API list prices. Direct input, cache write, cache read, and output are each priced in the category the API documents; OpenAI cache reads use the documented cached-input rate. The estimate always uses all recorded Token Kinds and is unaffected by the table's Token Kind display filters. The final aggregate is rounded upward once to the nearest cent and displayed with exactly two decimal places. Missing or unrecognized Models remain unpriced, so a mixed result is marked partial. This is not an actual bill: a transcript cannot reliably reconstruct every pricing modifier, subscription term, discount, or non-token charge.

Both native clients also retain a **Billing tokens** summary for users who prefer a token count over a currency estimate. That summary is objectively `direct input + cache write + output`; cache read remains visible as a Token Kind in the Odometer table but is excluded from this specific summary. Token Kind display filters affect neither summary. Neither presentation changes the four-kind Token Odometer total.

_Avoid_: calling the API-equivalent estimate a Usage Window, presenting it as an invoice, or treating Billing tokens as the Token Odometer's four-kind total.

**Limit**:
The maximum usage allowed within a Usage Window. Consumption is shown as a percentage of this.
_Avoid_: Cap, allowance (when referring to the metered ceiling specifically).

**Coding Agent**:
An AI coding tool whose usage TokenStats tracks. Each Coding Agent exposes one or more **Usage Windows** in a normalized shape (label, percent consumed, and reset time when available), so the UI never depends on a specific agent. It is also the **Token Odometer**'s first axis: the odometer groups by Coding Agent before Model. Claude Code is the first Coding Agent; Codex is being added as another.
_Avoid_: provider, vendor (note: "UsageProvider" is the code seam that adapts one Coding Agent — not a synonym for the agent itself). A Coding Agent is not a **Model**: today each agent happens to use models from one vendor, but the agent is the tool and the Model is what answered the request.

**Codex**:
An OpenAI Coding Agent whose authoritative Usage Windows TokenStats should track only after they are empirically confirmed. Codex is not a generic name for all OpenAI usage or API billing.
_Avoid_: OpenAI usage, API usage, ChatGPT usage (unless specifically referring to the login identity).
