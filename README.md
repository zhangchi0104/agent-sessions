# TokenStats

Native macOS menu-bar and Windows notification-area apps that show how much of
each Coding Agent's **Usage Window** you have left and when it resets. Claude
Code and Codex are both supported.

The popover carries two tabs:

- **Usage** — one **Usage Window** set per agent, read from that agent's own
  authoritative usage endpoint over its own OAuth session: percent consumed and
  time to reset, drawn as a dial, an arc, or a bar.
- **Tokens** — the **Token Odometer**: the raw sum of tokens across the agent
  transcript files on this computer over a chosen range of up to 30 days,
  broken down by Coding Agent, then Model, then Token Kind. An odometer, not a
  quota. The Windows client can also present the same records as estimated
  standard API-equivalent usage.

See [`apps/TokenStats/CONTEXT.md`](apps/TokenStats/CONTEXT.md) for the domain
glossary and [`apps/TokenStats/docs/adr/`](apps/TokenStats/docs/adr/) for the
design decisions.

## Install

For macOS, download the latest codesigned, notarized `.dmg` from the
[releases](https://github.com/zhangchi0104/agent-sessions/releases). Tags are
scoped `tokenstats-v*`; betas are marked pre-release.

The Windows app currently builds from source under
[`apps/TokenStats.Windows`](apps/TokenStats.Windows/README.md). Authenticode
signing and installer publication are the remaining release-engineering step.

## Develop on macOS

Requires Xcode 26 (the project is a macOS 26 / Xcode 26 format).

```sh
cd apps/TokenStats
npm test         # static checks, compile-only app build, then unhosted unit tests
npm run test:ui  # opt-in UI automation; use an isolated macOS session
npm run dev      # build Debug and launch the app
npm run build    # build Release
```

The UI suite controls the foreground desktop and is deliberately excluded from
`npm test`. Run `npm run test:ui` only in a disposable macOS user session, VM,
or dedicated CI runner where it cannot interfere with other applications.
The compile-only step verifies the real app entry point without launching it;
the unit bundle runs under Xcode's `xctest` process, not inside TokenStats.app.

Debug and local Release builds use ad-hoc signing by default, so a fresh
checkout needs no Apple Developer account. To use your own stable Apple
Development identity, copy the example and edit the local file by hand:

```sh
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
```

Set `DEVELOPMENT_TEAM` in `Config/Signing.local.xcconfig` to your Team ID. The
local file is ignored by Git, so pulls and commits neither overwrite nor share
it. Do not persist your team with Xcode's **Signing & Capabilities → Team**
picker: that writes the personal value into the tracked Xcode project. The
checked-in defaults remain ad-hoc, and `npm test` explicitly uses ad-hoc
signing regardless of the local file. Like any ignored file, the local config
can be removed by destructive cleanup such as `git clean -fdx`.

The [`Test TokenStats`](.github/workflows/test-tokenstats.yml) workflow runs the
same non-UI `npm test` for TokenStats-affecting pull requests and pushes, then
separately opts into `npm run test:ui` on its dedicated macOS CI desktop.

## Develop on Windows

Requires Windows 10/11 and the .NET 8 SDK.

```powershell
cd apps\TokenStats.Windows
.\scripts\build.ps1
dotnet run --project src\TokenStats.App\TokenStats.App.csproj
```

The Windows project is a native WPF tray app with no third-party runtime
packages. See its [README](apps/TokenStats.Windows/README.md) for build,
security, and platform behavior details.

## Layout

```txt
.
├── apps/TokenStats/             # macOS app (Swift/SwiftUI)
├── apps/TokenStats.Windows/     # Windows app (C#/WPF)
└── docs/
    ├── adr/             # superseded decisions from the removed session-tracking tools
    └── specs/           # working specs
```

The app keeps its `apps/TokenStats/` path rather than moving to the repository
root, so its history stays continuous.

## Release

Releases are automated. The
[`Release TokenStats`](.github/workflows/release-tokenstats.yml) workflow runs
semantic-release on pushes touching `apps/TokenStats/**`: `dev` ships a beta
`.dmg`, `main` a stable one, each codesigned, notarized, and attached to a
`tokenstats-v*` GitHub Release. See
[`apps/TokenStats/docs/release.md`](apps/TokenStats/docs/release.md).
