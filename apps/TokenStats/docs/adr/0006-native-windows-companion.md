# 6. A native Windows companion

Date: 2026-07-27

Status: Accepted

Amends [ADR-0005 — TokenStats tracks usage only](0005-tokenstats-tracks-usage-only.md).

## Context

TokenStats currently ships as a native macOS menu-bar application. Windows
users need the same two surfaces: authoritative Coding Agent **Usage Windows**
and the local **Token Odometer**.

The usage-only simplification in ADR-0005 removed a separate cross-language
Sessions product: hooks, plugins, a bundled JavaScript CLI, SQLite, and its
release-time coupling to the macOS app. Its final wording also said that the
repository would contain no language but Swift. That language restriction made
sense while there was one supported platform, but SwiftUI and AppKit cannot
provide a native Windows notification-area application.

A web-shell rewrite of the existing macOS app would enlarge both products and
discard the platform-native implementation that already works. Sharing source
code between Swift and Windows would also force an abstraction layer across UI,
credential, file-watch, wake, and OAuth-listener APIs that are inherently
platform-specific.

## Decision

Add a separate native Windows application under `apps/TokenStats.Windows`:

- C# and WPF provide the notification-area icon, flyout, Settings, and
  onboarding windows.
- `TokenStats.Core` contains a semantic port of the small pure domain:
  normalized Usage Windows, reducers, formatting, refresh policy, OAuth
  helpers, tolerant response parsers, and transcript accounting.
- Windows-specific code owns Credential Manager storage, the loopback listener,
  file watching, sleep/resume events, and tray lifecycle.
- The Windows app uses the same independent OAuth identities and never reads or
  refreshes either Coding Agent's own credentials.
- The Windows Tokens tab implements the shared Token Odometer over Today,
  7 days, or 30 days, grouped by Coding Agent, Model, and the four disjoint
  Token Kinds.
- Windows retains two summary presentations inside that tab. Billing tokens
  count direct input, cache writes, and output while excluding cache reads;
  API equivalent derives a list-price estimate from transcript model
  attribution, includes priced cache reads, and marks unknown models as
  partial. Neither summary changes the four-kind Odometer total.
- Windows normalizes Codex Usage Windows using the returned duration and
  renders the windows actually present. A missing short-term window does not
  produce a fixed 5-hour placeholder.
- Windows follows the system app theme at startup and at runtime. Its WPF
  surfaces, native title bars, controls, and notification-area menu share
  light, dark, and High Contrast-aware theme resources.
- The existing Swift/macOS project remains native and independent. The two apps
  share target behavior specifications, endpoint documentation, terminology,
  and visual assets—not a runtime or build graph.

Windows notification-area icons cannot reserve adjacent dynamic text as a
macOS menu-bar item can. The compact reading (`76%` or
`C: 76% X: 88%`) therefore lives in the tray tooltip, with full readings in the
flyout.

Opening the Windows flyout intentionally triggers a Usage Window refresh. The
macOS refresh policy already names a `popoverOpen` trigger but does not
currently connect it; this is treated as a Windows behavior correction, not a
claim of exact implementation parity.

Windows also implements the switchable Billing tokens/API equivalent summary
and duration-driven Codex window rendering described above. The pricing summary
is an intentional Windows extension; it is neither an invoice nor a Usage
Window.

The scope decision from ADR-0005 is unchanged: TokenStats still contains no
Sessions tab, hooks, plugins, SQLite store, waiting-state tracker, or transcript
daemon. C# is introduced only for the Windows client.

## Consequences

- **Positive:** Windows receives a lightweight native tray experience without
  an embedded browser or JavaScript runtime.
- **Positive:** platform-specific security and lifecycle APIs remain explicit,
  while pure behavior stays testable away from WPF.
- **Positive:** neither platform's release artifact depends on building the
  other platform first.
- **Negative:** equivalent behavior is implemented independently in Swift and
  C#, so parser fixtures and acceptance tests must guard against drift. The
  Windows-only pricing summary must remain clearly separated from the shared
  raw Token Odometer semantics.
- **Negative:** Windows packaging, Authenticode signing, SmartScreen reputation,
  and release assets require their own pipeline and credentials.
- **Risk:** the Claude and Codex endpoints are unofficial. Codex login and usage
  still require live end-to-end confirmation before a production release.
