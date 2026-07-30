# TokenStats for Windows

A native Windows notification-area app for TokenStats' two-tab flyout:

- **Usage** shows the authoritative Usage Windows for Claude Code and Codex,
  fetched directly from each Coding Agent over TokenStats' independent OAuth
  session.
- **Tokens** shows a local Token Odometer derived from native Windows transcript
  directories for Today, 7 days, or 30 days. It groups four disjoint Token
  Kinds by Coding Agent and Model. Each Token Kind heading is also a filter;
  the enabled headings form a Windows-only **selected total** for table
  composition without changing the underlying four-kind Odometer. Disabled
  kinds remain visible as dimmed raw values.

The tray tooltip carries a compact objective status summary for the persisted
Token Odometer range: either Billing tokens or API equivalent. Token Kind
display filters do not change that reading. Click the tray gauge for the full
flyout; right-click it for Refresh, Settings, and Quit. **Refresh all** updates
both subscription Usage Windows and local transcript tokens.

## Tokens and API-equivalent estimates

The Tokens tab retains a Windows-specific summary mode over the selected time
range:

- **Billing tokens** is `direct input + cache writes + output`. Cache reads
  remain visible in the Odometer table but are deliberately excluded from this
  summary. Display filters do not change the count.
- **API equivalent** is an estimated USD value. Each transcript entry is
  attributed to its recorded model and valued using that model's standard
  official API list prices. Unlike Billing tokens, this estimate includes
  cache reads at the applicable cached-input price. It always uses all four
  recorded Token Kinds, regardless of display filters. Entries whose model is
  missing or absent from the pricing catalog remain unpriced and make the
  displayed estimate explicitly partial. The final sum is rounded upward once
  to the nearest cent and always displayed with two decimal places.

API equivalent is not a Usage Window, an invoice, a reconstruction of a Claude
or ChatGPT subscription, or a promise that the same amount was actually billed.
Local transcripts do not reliably identify every pricing modifier, including
long-context surcharges, Priority/Flex/Batch processing, data residency or
partner routing, private discounts, and separate tool charges. The estimate
therefore applies standard API list prices only.

The Odometer table itself always uses the cross-platform raw definition:
`direct input + output + cache write + cache read`. The four columns are
`IN`, `OUT`, `C·W`, and `C·R`; no category is counted twice.

On Windows, the four column headings can be toggled independently. The
**selected total** is the sum of the enabled Token Kinds over the selected
range; it drives table subtotals, model ordering, and composition percentages.
It does not change the Billing tokens/API-equivalent summary, rewrite transcript
records, or redefine the raw four-kind Token Odometer total.

The **Display** Settings page controls whether each enabled Token Kind is shown
as a numeric value, its percentage of that row's selected total, or both as
`value (percentage)`. A disabled kind remains as a dimmed raw numeric value,
has no percentage, and is excluded from the percentage denominator. These
percentages describe token composition only. They are not quota consumption, a
Limit, or a Usage Window percentage.

Pricing sources, last checked **2026-07-27**:

- [OpenAI API model catalog and pricing](https://developers.openai.com/api/docs/models)
- [Anthropic Claude API pricing](https://platform.claude.com/docs/en/about-claude/pricing)

## Requirements

- Windows 10 version 1809 or newer, or Windows 11
- .NET 8 SDK for development
- No third-party runtime or NuGet package dependencies

Published builds are self-contained single-file executables, so end users do
not need to install .NET or copy companion WPF DLLs.

## Develop

From this directory:

```powershell
.\scripts\build.ps1
dotnet run --project src\TokenStats.App\TokenStats.App.csproj
```

`build.ps1` restores, builds, runs the zero-dependency core test harness, and
loads every WPF window through the safe fake-service UI smoke harness. Either
process exits non-zero on failure, so the script works in CI without a
test-framework package. `global.json` pins the .NET 8 SDK line and the projects
pin C# 12 for reproducible builds.

Create portable x64 or ARM64 builds:

```powershell
.\scripts\publish.ps1
.\scripts\publish.ps1 -Runtime win-arm64
```

The outputs are written under `artifacts\win-x64` and
`artifacts\win-arm64`. Production distribution still needs Authenticode signing
and an installer/MSIX pipeline; an unsigned portable build may trigger
SmartScreen.

## Windows behavior

- Only one instance runs. A second launch activates the first.
- OAuth tokens are separate per Coding Agent in Windows Credential Manager.
- The app never reads Claude Code's or Codex's own stored login credentials.
- Claude login asks the user to paste the browser's `code#state`.
- Codex login listens only on loopback, trying the registered ports 1455 then
  1457 and timing out after five minutes.
- Codex Usage Windows are named and classified from the returned window
  duration and rendered dynamically. If the response has no short-term
  window, the flyout does not invent a fixed 5-hour placeholder.
- **Appearance** can follow Windows or force a light or dark theme. It also
  supports palette overrides, an installed interface font, a background image
  with Fill/Fit/Center/Tile sizing, nine-point positioning, and opacity,
  flyout opacity and width, and proportional text/UI scaling. Changes apply
  live to the flyout, Settings, onboarding, native title bars, and theme-aware
  controls. Windows
  High Contrast always takes precedence over custom colors, imagery, and
  transparency.
- Data-presentation preferences remain under **Display** so primary-agent order,
  gauge style, Token Kind formatting, and pinning stay independent from visual
  customization.
- Opening the flyout refreshes Usage Windows. At startup the Windows transcript
  reader fully reconciles the persisted Token Odometer range against the
  transcript roots, then keeps debounced `FileSystemWatcher` subscriptions
  active for the lifetime of the resident tray process. JSONL events reconcile
  affected files; directory changes, watcher errors, and **Refresh all**
  trigger another full reconciliation. This keeps the tray's objective Token
  summary current without polling and without a daemon, database, or IPC
  surface. If a transcript root does not exist yet, a lightweight
  parent-directory watch adopts it when the Coding Agent creates it.
- Unchanged transcript prefixes can hydrate from disposable per-file
  checkpoints under
  `%LocalAppData%\TokenStats\Cache\token-reader-v1`. Checkpoint filenames are
  hashed, payloads carry an integrity checksum, writes are atomic, and schema
  or local-time-zone changes, replacement, truncation, deletion, rename, or
  corruption cause conservative re-parsing.
  The cache stores no transcript text, incomplete-line bytes, or credentials;
  deleting the directory is safe and rebuilds it from the transcript roots.
- The Today/7-day/30-day range is restored across app restarts. Range changes
  keep the last completed table dimmed until the new scan lands atomically.
- Billing tokens and API equivalent use per-digit vertical rolling transitions
  when their value or displayed range changes. Switching between the two
  summary modes settles immediately without animation. Value and range
  transitions follow the Windows client-area animation accessibility
  preference.
- Token Kind filters update the table's selected total while the raw four-kind
  Odometer and objective Billing/API-equivalent summaries remain unchanged.
  Enabled cells can show value, percentage, or value-and-percentage according to
  the Display preference; disabled cells retain a dimmed raw value and no
  percentage.
- The flyout can be pinned so it remains visible and always on top. The pin
  choice is restored across app restarts; Escape and explicit tray actions
  still dismiss it.
- The flyout grows with its content up to the notification area's current
  monitor work area and uses vertical scrolling only when the content truly
  cannot fit. Every layout-affecting change—including a range, filter, display
  mode, tab, scan result, or expanded diagnostic—repositions it inside that work
  area.
- Codex `token_count` events are cumulative, so Windows counts only advances in
  `total_token_usage`, adopts a new baseline after a counter reset, and uses
  `last_token_usage` only to exclude an inherited rollout head. Model
  attribution follows both `turn_context` and `thread_settings_applied`.
- `%USERPROFILE%\.codex\archived_sessions` is intentionally not scanned, matching
  the macOS Token Odometer. A historical Codex total can therefore shrink when
  an active rollout is archived.
- Healthy usage refreshes every 30 minutes. Failures back off independently per
  agent up to six hours, while the last known reading remains visibly stale.
- “Start with Windows” is off by default and uses the current-user Run key for
  portable builds.

Native Windows transcript roots are:

```text
%USERPROFILE%\.claude\projects
%USERPROFILE%\.codex\sessions
```

WSL transcript roots are not scanned in this first version.

## Layout

```text
src/TokenStats.Core/       Pure domain, parsers, OAuth helpers, transcript reader
src/TokenStats.App/        WPF UI and Windows infrastructure
tests/TokenStats.Core.Tests/
tests/TokenStats.UiSmoke/   Fake-service WPF layout and lifecycle smoke checks
scripts/
```

See [ADR-0006](../TokenStats/docs/adr/0006-native-windows-companion.md) for the
native companion decision and the deliberate tray differences from macOS, and
[ADR-0007](../TokenStats/docs/adr/0007-local-token-parse-cache.md) for the
disposable Windows parse-checkpoint cache.
