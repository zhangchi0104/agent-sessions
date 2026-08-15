# TokenStats

A native status-area app that shows how much of a Coding Agent's usage allowance has been consumed and when it resets. The original client is a macOS menu-bar app; a native Windows notification-area companion lives under `apps/TokenStats.Windows`.

## Localization contract (macOS)

English is the source language for TokenStats-owned copy. Simplified Chinese (`zh-Hans`), German (`de`), French (`fr`), Japanese (`ja`), and Russian (`ru`) are fully supported translations. Product copy uses stable semantic String Catalog keys, `LocalizedStringResource`, and Xcode-generated symbols; visible sentences must not be assembled from translated fragments.

The following terms are canonical. Review new copy against this table before adding a key:

| English source term | 简体中文 | Deutsch | Français | 日本語 | Русский | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Usage Window | 用量周期 | Nutzungszeitraum | fenêtre d’utilisation | 使用期間 | период использования | A quota period with authoritative consumption/reset semantics. |
| Token Odometer | Token 计量 | Token-Zähler | compteur de tokens | トークン積算計 | счётчик токенов | The transcript-derived token total; never a quota. |
| Token Kind | Token 类型 | Token-Typ | type de token | トークン種別 | тип токенов | One of direct input, output, or cache read. |
| Selected total | 已选合计 | Ausgewählte Summe | total sélectionné | 選択合計 | итог по выбранным типам | The projection over enabled Token Kinds. |
| Billing tokens | 计费 Token | Abrechnungs-Token | tokens facturables | 課金対象トークン | расчётные токены | The direct-input + output summary; cache reads remain informational. |
| API equivalent | API 等值费用 | API-Äquivalent | équivalent API | API 換算額 | эквивалент API | An estimate, not an invoice. |
| Coding Agent | Coding Agent | Coding Agent | Coding Agent | Coding Agent | Coding Agent | Keep the English technical term. |
| Model | 模型 | Modell | modèle | モデル | модель | The model reported by the transcript. |

Do not translate the TokenStats, Claude Code, Codex, or Fable names; model identifiers; URLs; filesystem paths; protocol/JSON field names; or raw diagnostic payloads. Localize the user-facing summary around a diagnostic, but preserve the raw diagnostic itself in the expandable detail.

An in-app language choice changes TokenStats-owned copy only. The chosen language is applied after restart. Language-bearing compact-number units follow that effective UI language (for example English K/M/B, German Mio./Mrd., French M/Md, Russian млн/млрд, and Chinese/Japanese 万/亿 forms), while the full Locale still lets the user's system region refine decimal symbols, numbering, dates, times, currency formatting, and regional variants. System-owned macOS UI, such as file pickers and standard menus, continues to follow macOS. Language selection never selects a display currency.

API-equivalent estimates remain canonically priced and aggregated in USD. Fixed USD is the default display choice. On macOS, a user may instead select an ISO 4217 display currency or System Region; TokenStats converts the exact USD aggregate once and then rounds upward at the target currency's standard minor unit. Windows remains USD-only. Localization must never infer a currency from the selected UI language.

## Language

**Usage Window**:
A rolling time period over which a Coding Agent meters usage against a quota, with enough authoritative data for TokenStats to show consumption and reset timing. Claude Code has three: a ~5-hour window (the primary gauge), a 7-day weekly window (secondary), and the weekly Fable-scoped window (third gauge). The app's central concept — "how much have I used, and when does it reset." In the Claude Code API the first two are `five_hour` and `seven_day`; the Fable one is the `limits` entry with `kind: "weekly_scoped"` scoped to the Fable model (see `docs/claude-code-integration.md`). Codex data should be called a Usage Window only if discovery confirms the same kind of trusted consumption/reset concept.
_Avoid_: session (in TokenStats a session is a conversation, never a billing period), quota period.

Claude Code can also return an `extra_usage` usage-credit meter. It is not a Usage Window because no reset timestamp is exposed, and TokenStats intentionally does not show it in the popover.

On macOS, the Usage tab renders sections only for connected Coding Agents that are enabled for that surface. A disconnected account has no placeholder section; reconnecting it restores its saved visibility and order.

> **Flagged ambiguity — "session limit":** Claude Code's own UI calls the 5-hour Usage Window the "session limit" and the weekly one the "weekly limit." We do **not** adopt "session limit," because a session is a conversation, not a billing period. The 5-hour period is always a **Usage Window**.

**Token Odometer**:
The raw sum of tokens across a Coding Agent's transcript entries over a chosen time range — an informational *odometer*, **not** a quota measure. It carries no Limit and no reset semantics, and must never be presented as a **Usage Window**. Its source is the agent's local files (Claude Code: every transcript under `~/.claude/projects`, spanning all projects; Codex: every rollout under `~/.codex/sessions`), which is only an *estimate* of consumption — per ADR-0001 the authoritative quota figure comes from the usage endpoint, never from file sums. TokenStats clients may keep disposable, versioned per-file parse checkpoints in their platform-local cache, but they are only an acceleration layer: deleting them rebuilds the same estimate from transcripts, and they never become a source of truth. The Codex figure is knowingly incomplete in a second way: `~/.codex/archived_sessions` is deliberately not scanned, so it omits roughly 1.2% of a 30-day total, and a past day's figure can shrink retroactively as its sessions are archived. The Token Odometer exists alongside the Usage Window as a separate, deliberately-unweighted "how much did I push through" figure, broken down by **Coding Agent**, then **Model**, then **Token Kind**.
_Avoid_: **Tokens Today** (retired — the measure is no longer bound to a single day, and nothing on screen is a single day's total); presenting the odometer or a Token Kind composition percentage as a quota percentage, a limit, or a remaining-quota figure; conflating it with the Usage Window gauge; describing a parse cache as authoritative history.

**Model**:
The model a Coding Agent reported against the tokens it consumed — `claude-opus-5`, `gpt-5.6-sol`, `codex-auto-review`. The Token Odometer's second axis, nested under Coding Agent. A Model is whatever the transcript *names*, not whatever the user *chose*: `codex-auto-review` is spawned by Codex itself and never selected by anyone, and it still earns its own row, because the odometer answers where tokens went rather than what was picked.
_Avoid_: treating a Model as a user setting; folding agent-initiated Models into whatever spawned them (Codex records a parent link on only 43% of those runs, so the fold cannot be done honestly).

**Token Kind**:
One of the three disjoint ways a token is counted against a request: **direct input**, **output**, or **cache read**. The Token Odometer's third axis, and the three visible columns of the Tokens tab; the raw Odometer total is their sum and no token is counted twice. In both native clients, each column heading is also an independent display filter. A disabled kind stays visible as a dimmed raw value, has no composition percentage, and is excluded from the percentage denominator. Cache read remains visible as an informational provider-reported input category. Cache-write fields are intentionally ignored because their reliable read path is not worth the feature's cost.
_Avoid_: "input" for the sum of direct input and cache read — direct input is one kind among three, and that sum has no name; treating a provider cache-creation field as a supported Token Kind.

**Selected total**:
A table projection over the Token Odometer: the sum of the Token Kinds whose column headings are enabled, within the persisted Today, 7-day, or 30-day range. It drives filtered per-Agent and per-Model subtotals, model ordering, and composition percentages in both native clients; it does not drive the objective Billing/API-equivalent summary or Windows tray tooltip. Toggling a heading changes the selected total, not the parsed transcript records or the raw three-kind Token Odometer total. For a Model row, an enabled Token Kind's displayed percentage is its share of that row's selected total; a disabled kind retains only its dimmed raw value. The percentage is composition, never quota consumption. The presentation preference chooses **value**, **percentage**, or **value (percentage)** for enabled kinds, and the selected kinds survive process restarts.
_Avoid_: calling the selected total the Token Odometer total; treating a Token Kind percentage as a Usage Window percentage.

**Presentation settings**:
The preferences that change how existing readings are presented without changing their source data: Token Kind figure format and selection, range, display currency, gauge style, and related status-area behavior. The macOS Tokens tab itself uses a fixed hierarchy—Billing tokens as the leading primary reading and Estimated API value as the smaller trailing reading in the same summary row—rather than a summary preference. Windows groups its presentation choices under **Display**. macOS places Coding Agent and Usage Window presentation under **Display**, and Token Odometer presentation under **Tokens**. Theme remains a separate concern.
_Avoid_: treating a presentation choice as a change to transcript accounting or Usage Window consumption.

**Display currency**:
The presentation currency used for the API-equivalent usage estimate. USD remains the canonical pricing and aggregation value and fixed USD is the default display choice. The macOS client may show that exact USD aggregate in a user-selected ISO 4217 currency by applying one cached USD reference rate and rounding upward once at the target currency's standard minor unit. **System Region** remains a live presentation choice, not a persisted currency code: changing the Mac's region resolves the choice again without changing transcript data or fetching a new table. Windows currently remains USD-only.
_Avoid_: country code (countries and currencies are not one-to-one), converting each transcript row separately, storing a converted value as source data, or silently treating a missing rate as 1:1.

**Exchange-rate source**:
The macOS presentation setting that pairs one known response adapter with one user-visible HTTPS API endpoint. Frankfurter is the default; ExchangeRate-API Open and European Central Bank reference data are also supported. A custom endpoint must remain compatible with the chosen adapter, be a public keyless service, and pass a full-table validation request before it becomes active. TokenStats provides no credential field or secret storage for this setting; it rejects URL user-info, known credential parameters and the known keyed ExchangeRate-API host, while the arbitrary remainder of a user-entered path or query remains the user's responsibility. Source changes are atomic: a failure preserves the current source, cached table, and refresh schedule. TokenStats rejects redirects, contacts only the active endpoint, stamps that source into its cache and request history, and never fails over automatically. The user-facing setting may call the adapter the **Rate provider**.
_Avoid_: treating the source as a Coding Agent provider, silently switching services after an error, accepting HTTP or credential-bearing URLs, or combining rates from multiple services.

**Display (Windows)**:
The Windows Settings pane for data-presentation choices: primary Coding Agent and order, gauge style, Token Kind figure format, and related status-area display behavior. These choices do not alter the app theme.
_Avoid_: calling this pane Appearance; Appearance is the separate visual-customization surface.

**Appearance (Windows)**:
The Windows Settings pane for visual customization: follow Windows/light/dark theme mode, palette and font overrides, background imagery, flyout opacity and width, and proportional text/UI scaling. Windows High Contrast takes precedence over custom colors, imagery, and transparency. Appearance is independent of Display and evolves as a Windows-native feature set.
_Avoid_: putting Coding Agent order, Usage Window gauge style, or Token Odometer formatting here; those remain Display preferences.

**API-equivalent usage estimate**:
An optional presentation of Token Odometer records as an estimated canonical USD value, derived from the Model recorded in each transcript entry and that Model's standard official API list prices. Direct input, cache read, and output are each priced in the category the API documents; OpenAI cache reads use the documented cached-input rate. The estimate always uses all recorded Token Kinds and is unaffected by the table's Token Kind display filters. When USD is displayed, the final aggregate is rounded upward once to the nearest cent and shown with exactly two decimal places. The macOS display may instead convert the exact aggregate once and round upward at the selected currency's standard minor unit; the USD source value itself never changes. Missing or unrecognized Models remain unpriced, so a mixed result is marked partial. This is not an actual bill: a transcript cannot reliably reconstruct every pricing modifier, subscription term, discount, or non-token charge.

Both native clients also retain a **Billing tokens** summary for users who prefer a token count over a currency estimate. That summary is objectively `direct input + output`; cache read remains visible as a Token Kind in the Odometer table but is excluded from this specific summary. Token Kind display filters affect neither summary. Neither presentation changes the three-kind Token Odometer total.

_Avoid_: calling the API-equivalent estimate a Usage Window, presenting it as an invoice, or treating Billing tokens as the Token Odometer's three-kind total.

**Limit**:
The maximum usage allowed within a Usage Window. Consumption is shown as a percentage of this.
_Avoid_: Cap, allowance (when referring to the metered ceiling specifically).

**Coding Agent**:
An AI coding tool whose usage TokenStats tracks. Each Coding Agent exposes one or more **Usage Windows** in a normalized shape (label, percent consumed, and reset time when available), so the UI never depends on a specific agent. It is also the **Token Odometer**'s first axis: the odometer groups by Coding Agent before Model. Claude Code is the first Coding Agent; Codex is being added as another.
_Avoid_: provider, vendor (note: "UsageProvider" is the code seam that adapts one Coding Agent — not a synonym for the agent itself). A Coding Agent is not a **Model**: today each agent happens to use models from one vendor, but the agent is the tool and the Model is what answered the request.

**Codex**:
An OpenAI Coding Agent whose authoritative Usage Windows TokenStats should track only after they are empirically confirmed. Codex is not a generic name for all OpenAI usage or API billing.
_Avoid_: OpenAI usage, API usage, ChatGPT usage (unless specifically referring to the login identity).
