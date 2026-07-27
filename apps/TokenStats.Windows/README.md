# TokenStats for Windows

A native Windows notification-area app for TokenStats' two core surfaces:

- **Usage Windows** for Claude Code and Codex, fetched directly from each
  Coding Agent over TokenStats' independent OAuth session.
- A local **Today counter**, derived from native Windows transcript directories
  and switchable between Token and Usage views.

The tray tooltip carries the compact reading (`76%` or
`C: 76% X: 88%`). Click the tray gauge for the full flyout; right-click it for
Refresh, Settings, and Quit.

## Today counter

The Appearance settings let the user switch the Today counter between two
views over the same local transcript data:

- **Token** is `raw input + cache writes + output`. Cache reads remain visible
  in the breakdown but are deliberately excluded from this total.
- **Usage** is an estimated USD API-equivalent value. Each transcript entry is
  attributed to its recorded model and valued using that model's standard
  official API list prices. Unlike the Token total, this estimate includes
  cache reads at the applicable cache-read price. Entries whose model is
  missing or absent from the pricing catalog remain unpriced and make the
  displayed estimate explicitly partial.

Usage is not an invoice, a reconstruction of a Claude or ChatGPT subscription,
or a promise that the same amount was actually billed. Local transcripts do
not reliably identify every pricing modifier, including long-context
surcharges, Priority/Flex/Batch processing, data residency or partner routing,
private discounts, and separate tool charges. The estimate therefore applies
standard API list prices only.

Pricing sources, last checked **2026-07-27**:

- [OpenAI API model catalog and pricing](https://developers.openai.com/api/docs/models)
- [Anthropic Claude API pricing](https://platform.claude.com/docs/en/about-claude/pricing)

## Requirements

- Windows 10 version 1809 or newer, or Windows 11
- .NET 8 SDK for development
- No third-party runtime or NuGet package dependencies

Published builds are self-contained, so end users do not need to install .NET.

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
- The flyout, Settings, onboarding, native title bars, controls, and tray menu
  follow the Windows app theme at startup and while the app is running. Windows
  High Contrast colors take precedence over the light and dark palettes.
- Opening the flyout refreshes Usage Windows and starts a recursive transcript
  watcher. Hiding it disposes the watcher.
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
native companion decision and the deliberate tray differences from macOS.
