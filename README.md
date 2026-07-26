# TokenStats

A macOS menu-bar app that shows how much of each Coding Agent's **Usage
Window** you have left and when it resets. Claude Code and Codex are both
supported.

Two things are on screen and nothing else:

- **Usage Windows** — per agent, read from that agent's own authoritative usage
  endpoint over its own OAuth session: percent consumed and time to reset, drawn
  as a dial, an arc, or a bar.
- **Tokens Today** — the raw sum of input/output/cache tokens across the agent
  transcript files on this Mac since local midnight. An odometer, not a quota.

See [`apps/TokenStats/CONTEXT.md`](apps/TokenStats/CONTEXT.md) for the domain
glossary and [`apps/TokenStats/docs/adr/`](apps/TokenStats/docs/adr/) for the
design decisions.

## Install

Download the latest codesigned, notarized `.dmg` from the
[releases](https://github.com/zhangchi0104/agent-sessions/releases). Tags are
scoped `tokenstats-v*`; betas are marked pre-release.

## Develop

Requires Xcode 26 (the project is a macOS 26 / Xcode 26 format).

```sh
cd apps/TokenStats
npm test         # xcodebuild test against the shared TokenStats scheme
npm run dev      # build Debug and launch the app
npm run build    # build Release
```

The [`Test TokenStats`](.github/workflows/test-tokenstats.yml) workflow runs the
same `npm test` on every pull request.

## Layout

```txt
.
├── apps/TokenStats/     # the app (Swift/SwiftUI) — its own CONTEXT.md and ADRs
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
