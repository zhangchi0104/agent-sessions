# Cursor usage comes from TokenStats' own login

TokenStats tracks Cursor's authoritative subscription consumption by calling
the same read-only dashboard RPC used by Cursor's shipped client. TokenStats
performs its own Cursor browser login and stores the resulting token pair in a
separate keychain item. It never reads, writes, or refreshes Cursor's own saved
credentials.

## Context

Cursor's current individual subscription usage is not exposed through its
documented public APIs. The shipped desktop and CLI clients do expose a browser
PKCE flow and a `DashboardService/GetCurrentPeriodUsage` RPC. The RPC returns a
billing-cycle end and the Cursor Models and Other Models percentages shown by
Cursor's official dashboard, which satisfy TokenStats' **Usage Window**
definition.

Sharing Cursor's own token would avoid another login, but it would couple
TokenStats to Cursor's private credential storage and token-rotation behavior.
That creates the same interference risk rejected for Claude Code and Codex in
ADR-0001 and ADR-0002.

## Decision

- Use an independent Cursor PKCE browser login and a TokenStats-owned `cursor`
  keychain item.
- Poll the read-only current-period dashboard RPC with that bearer token.
- Present **Cursor Models** and **Other Models** Usage Windows from
  `autoPercentUsed` and `apiPercentUsed`, with the reported cycle end as the
  reset time for both.
- Do not create a Cursor Token Odometer. Cursor has no compatible local
  transcript source, and subscription spend must not be reverse-engineered into
  token counts.

## Consequences

- The user approves a separate Cursor login inside TokenStats.
- Cursor appears on authoritative Usage surfaces but has no Tokens visibility
  control or Token Odometer rows.
- The integration depends on an unofficial endpoint and public client flow
  recovered from Cursor 3.15.19 / Cursor Agent CLI 2026.04.08. A Cursor update
  can break it, so failures remain disclosed through TokenStats' existing stale
  reading and diagnostics behavior.
- Aggregate spend fields do not substitute for either official model bucket;
  TokenStats follows Cursor's dashboard percentages directly.
