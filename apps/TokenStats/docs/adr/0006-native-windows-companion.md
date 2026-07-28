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
- Each Windows Token Kind heading is an independent filter. Enabled headings
  produce a **selected total** for the flyout and tray tooltip while the raw
  four-kind Token Odometer remains unchanged. Token cells can show value,
  percentage composition, or `value (percentage)` according to the
  **Display** preference.
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
- Windows persists the Token Odometer range and the flyout pin choice across
  restarts. A pinned flyout remains visible and always on top; an unpinned
  flyout keeps notification-area auto-dismiss behavior.
- Any operation that changes flyout layout repositions and constrains it to the
  notification area's monitor work area. This includes range and Token Kind
  changes, Display preference changes, tab changes, scan results, and expanded
  diagnostics.
- Because the tray tooltip consumes the selected total while the flyout is
  closed, Windows seeds the persisted range at startup and keeps debounced
  `FileSystemWatcher` subscriptions active for the resident app's lifetime.
  The watcher remains in-process and event-driven; it is not a daemon, database
  cache, IPC service, or polling loop.
- The existing Swift/macOS project remains native and independent. The two apps
  share target behavior specifications, endpoint documentation, terminology,
  and visual assets—not a runtime or build graph.

Windows notification-area icons cannot reserve adjacent dynamic text as a
macOS menu-bar item can. The compact status-area reading therefore lives in the
tray tooltip, including the persisted Token Odometer range's selected total,
with full per-Agent, per-Model, and per-Kind readings in the flyout.

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
- **Negative:** Windows keeps two recursive file-system subscriptions armed
  while the tray process is resident and performs a background seed scan at
  every launch. Persisting 30 days can make that initial scan materially more
  expensive than Today, although idle operation performs no polling.
- **Negative:** Windows packaging, Authenticode signing, SmartScreen reputation,
  and release assets require their own pipeline and credentials.
- **Risk:** the Claude and Codex endpoints are unofficial. Codex login and usage
  still require live end-to-end confirmation before a production release.

## Amendment — 2026-07-29

Windows' status-area surface now includes the Token Odometer selected total, so
three implementation details become durable product behavior:

1. Token Kind filters and their value/percentage presentation belong to
   **Display**, while selected total remains explicitly distinct from the raw
   four-kind Odometer.
2. The chosen Token Odometer range and flyout pin preference survive process
   restarts, and every size-changing operation repositions the flyout inside
   the current work area.
3. The Windows watcher is application-resident rather than Tokens-tab-visible.
   This revises only the watcher lifetime from ADR-0003; the no-daemon,
   no-database, and no-IPC architecture remains accepted.
