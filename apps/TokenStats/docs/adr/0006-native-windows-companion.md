# 6. A native Windows companion

Date: 2026-07-27

Status: Accepted

Amends [ADR-0005 — TokenStats tracks usage only](0005-tokenstats-tracks-usage-only.md).
The local parse-persistence boundary is amended by
[ADR-0007 — Windows keeps a disposable local token parse cache](0007-local-token-parse-cache.md).

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
  produce a **selected total** for table subtotals, ordering, and percentage
  composition while the raw four-kind Token Odometer remains unchanged.
  Enabled Token cells can show value, percentage composition, or
  `value (percentage)` according to the **Display** preference. Disabled cells
  retain a dimmed raw value with no percentage.
- Windows retains two summary presentations inside that tab. Billing tokens
  count direct input, cache writes, and output while excluding cache reads;
  API equivalent derives a list-price estimate from transcript model
  attribution, includes priced cache reads, and marks unknown models as
  partial. Both are objective over the full recorded usage for the selected
  time range and ignore Token Kind display filters. Neither summary changes the
  four-kind Odometer total. API equivalent rounds the final aggregate upward
  once to the nearest cent and displays exactly two decimal places. Both summary
  values use per-digit vertical rolling transitions for value and range changes
  when Windows client-area animations are enabled. Switching between Billing
  tokens and API equivalent settles immediately without animation.
- Windows normalizes Codex Usage Windows using the returned duration and
  renders the windows actually present. A missing short-term window does not
  produce a fixed 5-hour placeholder.
- Windows follows the system app theme at startup and at runtime. Its WPF
  surfaces, native title bars, controls, and notification-area menu share
  light, dark, and High Contrast-aware theme resources.
- Windows persists the Token Odometer range and the flyout pin choice across
  restarts. A pinned flyout remains visible and always on top; an unpinned
  flyout keeps notification-area auto-dismiss behavior.
- The flyout grows with content up to the notification area's monitor work area
  and uses vertical scrolling only when content cannot fit. Any operation that
  changes flyout layout repositions it inside that work area. This includes
  range and Token Kind changes, Display preference changes, tab changes, scan
  results, and expanded diagnostics.
- Because the tray tooltip consumes the objective Token summary while the
  flyout is closed, Windows fully reconciles the persisted range at startup and
  keeps debounced `FileSystemWatcher` subscriptions active for the resident
  app's lifetime. The watcher remains in-process and event-driven; it is not a
  daemon, database, IPC service, or polling loop. ADR-0007 permits only a
  disposable local per-file parse-checkpoint cache to accelerate that
  reconciliation.
- The existing Swift/macOS project remains native and independent. The two apps
  share target behavior specifications, endpoint documentation, terminology,
  and visual assets—not a runtime or build graph.

Windows notification-area icons cannot reserve adjacent dynamic text as a
macOS menu-bar item can. The compact status-area reading therefore lives in the
tray tooltip, including the persisted Token Odometer range's objective Billing
tokens or API-equivalent summary,
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
- **Negative:** Windows keeps recursive file and directory subscriptions for
  both transcript roots armed while the tray process is resident and performs
  a background full reconciliation at every launch. A cold or invalidated
  30-day cache can make that initial reconciliation materially more expensive
  than Today, although valid checkpoints avoid re-parsing unchanged files and
  idle operation performs no transcript polling.
- **Negative:** Windows packaging, Authenticode signing, SmartScreen reputation,
  and release assets require their own pipeline and credentials.
- **Risk:** the Claude and Codex endpoints are unofficial. Codex login and usage
  still require live end-to-end confirmation before a production release.

## Amendment — 2026-07-29

Windows' status-area surface now includes an objective Token summary over the
persisted range, so three implementation details become durable product
behavior:

1. Token Kind filters and their value/percentage presentation belong to
   **Display**. Their selected total remains explicitly distinct from the raw
   four-kind Odometer and from the Billing/API-equivalent summary; disabled
   kinds retain a dimmed raw value but no percentage.
2. The chosen Token Odometer range and flyout pin preference survive process
   restarts. The flyout grows to the current work-area limit before scrolling,
   and every size-changing operation repositions it inside that work area.
3. The Windows watcher is application-resident rather than Tokens-tab-visible.
   This revises the watcher lifetime from ADR-0003. ADR-0007 later revises the
   strictly in-memory parse-state boundary, while the no-daemon, no-database,
   and no-IPC architecture remains accepted.
