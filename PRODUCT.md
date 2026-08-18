# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

TokenStats is for individual developers who use Claude Code, Codex, or Cursor frequently and need a quick, dependable view of their current usage allowance and, where compatible local transcripts exist, the volume of tokens their coding-agent work has consumed.

They use it as an ambient desktop utility rather than a destination application: it lives in the macOS menu bar or Windows notification area and should answer the user's immediate usage question at a glance.

## Product Purpose

TokenStats helps developers understand two separate facts about their coding-agent activity:

- how much of each authoritative Usage Window has been consumed and when it resets; and
- how many tokens have passed through local agent transcripts over a selected recent range.

Success means a user can inspect either measure quickly, understand where the number came from, and avoid mistaking an estimate for a quota or invoice.

## Positioning

TokenStats combines agent-authoritative Usage Windows with a local, model-attributed Token Odometer in one native status-area utility. It obtains each Usage Window through an independent OAuth session with the Coding Agent and derives token detail directly from local transcripts, while keeping the two measures visibly and semantically distinct.

## Operating Context

- TokenStats is a native desktop product with a SwiftUI macOS menu-bar app and a WPF Windows notification-area companion.
- The product supports Claude Code, Codex, and Cursor as distinct Coding Agents. Cursor currently supplies Usage Windows only, not Token Odometer data.
- Users open a compact two-tab flyout from the system status area. **Usage** presents authoritative Usage Windows; **Tokens** presents the local Token Odometer.
- The Token Odometer supports Today, 7-day, and 30-day ranges and groups results by Coding Agent, then Model, then Token Kind.
- TokenStats runs alongside the user's existing coding-agent workflows. It does not require users to change how they start or conduct those workflows.
- The macOS and Windows clients share product concepts but follow their respective platform conventions rather than forcing identical interaction details.

## Capabilities and Constraints

- A Usage Window is a quota-backed consumption period obtained from a Coding Agent's own authoritative usage endpoint. It includes a consumed percentage and reset timing when the agent exposes them.
- The Token Odometer is an informational estimate computed from local transcript files. It is not a Usage Window, quota, or source of authoritative billing data.
- The Token Odometer's raw total is the sum of four disjoint Token Kinds: direct input, output, cache write, and cache read. It must not double-count tokens.
- Models are reported from transcript data, including agent-initiated models the user did not select. They are not product settings.
- Codex archived sessions are intentionally excluded from transcript scanning, so historical Codex totals may shrink when active sessions are archived.
- Cursor has no compatible Token Odometer transcript source; its authoritative Cursor Models and Other Models billing-cycle Usage Windows remain separate from token estimates.
- Windows may show Billing tokens and a standard-list-price API-equivalent estimate. Neither is an invoice, and missing or unrecognized Models can make the estimate partial.
- OAuth credentials are stored separately for each Coding Agent. TokenStats does not read the agents' own stored login credentials.
- TokenStats tracks usage only. Session lifecycle tracking, agent-attention status, and workflow orchestration are outside the product's scope.
- The macOS app requires the macOS 26 / Xcode 26 project format. The Windows companion targets Windows 10 version 1809 or newer and Windows 11.
- Windows installer publication and Authenticode signing remain release-engineering work; published macOS releases are codesigned and notarized DMGs.

## Brand Commitments

- The product name is **TokenStats**.
- Product language is precise, restrained, and factual. It names the source and limitations of estimates instead of implying certainty.
- Preserve the established domain terms **Usage Window**, **Token Odometer**, **Coding Agent**, **Model**, **Token Kind**, **selected total**, **Billing tokens**, and **API-equivalent usage estimate** as defined in `apps/TokenStats/CONTEXT.md`.
- Do not call the Token Odometer a quota, limit, remaining allowance, invoice, or authoritative bill. Do not use “session limit” for a Usage Window.

## Evidence on Hand

- Product scope, installation, development, and release behavior: `README.md`.
- Canonical domain language and measurement semantics: `apps/TokenStats/CONTEXT.md`.
- Accepted scope boundary that TokenStats tracks usage only: `apps/TokenStats/docs/adr/0005-tokenstats-tracks-usage-only.md`.
- Native cross-platform decision: `apps/TokenStats/docs/adr/0006-native-windows-companion.md`.
- Current macOS implementation: `apps/TokenStats/TokenStats/`.
- Current Windows implementation: `apps/TokenStats.Windows/`.
- A current Windows Tokens flyout screenshot was supplied with this initialization request.
- No testimonials, customer logos, adoption metrics, independent benchmarks, press coverage, or billing guarantees are established in the repository. Future work must not fabricate them.

## Product Principles

1. **Keep unlike measures distinct.** Usage Windows, Token Odometer totals, selected totals, Billing tokens, and API-equivalent estimates must never collapse into one ambiguous number.
2. **Answer at a glance.** The status-area surface should make the user's immediate usage question easy to scan without turning the utility into a full analytics dashboard.
3. **State provenance and uncertainty.** Authoritative endpoint data, local estimates, structurally absent values, partial pricing, and stale readings must remain honestly distinguishable.
4. **Stay native to each desktop.** Preserve shared product meaning while adapting controls, window behavior, system integration, and accessibility to macOS and Windows conventions.
5. **Remain narrowly useful.** TokenStats observes coding-agent usage; it does not become a session tracker, workflow manager, or billing system.

## Accessibility & Inclusion

- Preserve native keyboard navigation, accessibility labels, reduced-motion preferences, and platform control behavior.
- On Windows, High Contrast system colors take precedence over the light and dark palettes.
- Information carried by color also needs textual labels, values, or accessible descriptions; Token Kind and connection state must not rely on color alone.
