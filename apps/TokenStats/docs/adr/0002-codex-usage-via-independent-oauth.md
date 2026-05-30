# Codex usage comes from TokenStats' own ChatGPT OAuth login, not Codex's stored credentials

TokenStats adds Codex as a second **Coding Agent**. To read Codex's authoritative rate-limit/usage figures (the primary 5-hour Usage Window and any secondary window, plus reset times), it calls the ChatGPT backend endpoint Codex itself uses, which requires a ChatGPT OAuth token for the user's account. As with Claude Code (ADR-0001), TokenStats performs its **own** OAuth login rather than reusing Codex's stored credentials.

This is ADR-0001 applied to Codex; the reasoning is identical, only the provider differs.

## Discovery update (2026-05-28)

The Codex usage contract was read from the open-source `openai/codex` repo (`codex-rs`, `main`); see `docs/codex-integration.md`. This resolves the two largest open questions in the original consequences below:

- **A cheap standalone, read-only usage source exists.** `backend-client/src/client.rs::get_rate_limits_many()` issues a plain `GET https://chatgpt.com/backend-api/wham/usage` returning a `RateLimitStatusPayload` (primary/secondary windows with `used_percent` + epoch `reset_at`). Polling it consumes no Codex usage, so the feasibility risk that previously threatened this whole feature is retired. The "rate limits ride on API response headers" observation still holds as a fallback, but a dedicated pollable endpoint is the preferred source.
- **Login is a loopback-redirect PKCE flow, not paste-the-code.** Codex uses public client `app_EMoamEEZ73f0CkXaXp7hrann` against `https://auth.openai.com` with redirect `http://localhost:1455/auth/callback`. TokenStats can run its own short-lived loopback listener rather than asking the user to paste a code.

Both findings are authoritative for the API shape but still want one live-traffic confirmation against a stock Codex CLI. The core decision (independent OAuth, never touch `~/.codex/auth.json`) is unchanged — refresh **rotates** the token, which is exactly the failure this ADR exists to prevent. The two consequences below are superseded on these points.

## Considered Options

- **Reuse `~/.codex/auth.json` read-only** (never refresh): no second login, and no Keychain prompt (Codex stores its token in a plaintext file, not the Keychain). But ChatGPT access tokens are short-lived (~hours); without refreshing, TokenStats would show Codex as stale or signed-out most of the time — unreliable data that guts the app's value. Rejected.
- **Reuse `~/.codex/auth.json` and refresh it**: keeps data fresh, but refreshing *rotates* the shared OAuth token, which can silently break the user's real Codex session — the exact failure ADR-0001 exists to prevent. Rejected.
- **Independent OAuth login** (chosen): TokenStats does its own ChatGPT login, stores its own token in its own store, and never touches Codex's `auth.json`. Costs a second login, but never interferes and keeps the data fresh. Keeps the two Coding Agents architecturally symmetric (each is an isolated login behind its own `UsageProvider`).

## Consequences

- The user signs in twice — once per Coding Agent. Accepted; credential isolation is the point.
- Depends on an unofficial, undocumented ChatGPT/Codex usage surface and OpenAI's OAuth client — may break when OpenAI changes it. Accepted fragility for the MVP, mirroring ADR-0001.
- ~~**The exact endpoint, response shape, and OAuth client parameters for Codex are not yet confirmed.** Unlike Claude Code's dedicated `GET /api/oauth/usage`, the official Codex CLI appears to surface rate limits alongside its API responses rather than via a standalone pollable endpoint. If no cheap standalone usage call exists, the polling design (and possibly this whole feature's feasibility) must be revisited.~~ **Superseded by the discovery update above:** a standalone `GET .../wham/usage` endpoint exists and the OAuth params are known. One live-traffic confirmation against a stock CLI is still wanted before implementation.
- TokenStats must not create meaningful Codex usage just to measure Codex usage. A synthetic request is acceptable only if discovery proves it is read-only/no-op and does not consume meaningful quota or mutate conversation state; otherwise Codex support remains unsupported rather than estimated.
- Until discovery confirms an authoritative Codex usage source, Codex should not appear in the normal usage UI as a supported Coding Agent. Showing a Codex row with no trusted data would imply support that TokenStats cannot yet provide.
- Once Codex becomes implementable, sign-in and freshness state should be tracked per **Coding Agent**, not as one global app sign-in state. Claude Code can be signed in while Codex is signed out, stale, unsupported, or fresh; this keeps credential isolation visible in the product model instead of hidden behind a single `signedOut` branch.
- ~~Login will likely use the **paste-the-code flow** again, mirroring ADR-0001.~~ **Superseded by the discovery update above:** Codex's OAuth client registers a **loopback redirect** (`http://localhost:1455/auth/callback`), so TokenStats captures the code via a short-lived local listener instead of paste-the-code. This diverges from Claude Code's flow.
