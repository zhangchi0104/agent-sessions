# Codex integration reference

Facts about the Codex **Coding Agent**'s usage surface. These are **unofficial and undocumented** — see ADR-0002. Treat them as a starting point to verify empirically, not a contract.

## Discovery status

**Source-confirmed, live-traffic confirmation pending.** The contract below was read directly from the open-source `openai/codex` repository (`codex-rs`, `main`, read 2026-05-28) — authoritative for the API shape, but not yet verified against the user's own stock Codex CLI traffic. Before Codex ships as a supported **Coding Agent**, confirm against a stock install:

- the stock Codex CLI version observed and capture date
- that `GET https://chatgpt.com/backend-api/wham/usage` returns the documented payload for the user's plan
- the request headers actually required (auth bearer, `ChatGPT-Account-Id`, user agent)
- that the call is read-only and does not consume meaningful Codex usage (source says it is a plain `GET`)
- whether refresh tokens are used or rotated (source: rotated — see OAuth below)

Do not store access tokens, refresh tokens, cookies, auth codes, full prompts, or other sensitive capture material in this repository. The OAuth `client_id` below is a public identifier embedded in the open-source CLI, not a secret.

## Usage source

Codex exposes a standalone, read-only usage endpoint — `backend-client/src/client.rs::get_rate_limits_many()` issues a plain `GET` and parses a `RateLimitStatusPayload`. Because it is a GET that returns current limits (not a chat/turn request), polling it does **not** consume Codex usage. This is the authoritative source to map onto TokenStats **Usage Windows**.

```
GET https://chatgpt.com/backend-api/wham/usage
```

- Path style depends on base URL: chatgpt.com (the `/backend-api` host) uses `/wham/usage`; a non-chatgpt Codex deployment uses `/api/codex/usage`. For TokenStats' ChatGPT-account login, the `/wham/usage` form applies.
- **Request headers:** `Authorization: Bearer <ChatGPT access token>`, a Codex `User-Agent`, and `ChatGPT-Account-Id: <account id>` (the account/org id, taken from the id_token claims). A FedRAMP header exists but is not relevant here.

Response shape (`RateLimitStatusPayload`; values below are **illustrative**, not captured):

```jsonc
{
  "plan_type": "plus",                    // free|go|plus|pro|pro_lite|team|business|enterprise|edu|…
  "rate_limit": {
    "primary_window":   { "used_percent": 42, "limit_window_seconds": 18000,  "reset_at": 1716800000 },  // ~5-hour
    "secondary_window": { "used_percent": 18, "limit_window_seconds": 604800, "reset_at": 1717300000 }   // ~weekly
  },
  "credits": { "has_credits": true, "unlimited": false, "balance": "9.99" },
  "additional_rate_limits": [ { "metered_feature": "codex_other", "limit_name": "…", "rate_limit": { /* same window shape */ } } ],
  "rate_limit_reached_type": { "type": "rate_limit_reached" }  // or workspace_*_credits_depleted / workspace_*_usage_limit_reached
}
```

- `rate_limit.primary_window` → the **5-hour Usage Window** (primary gauge); `rate_limit.secondary_window` → the **weekly Usage Window** (secondary). The window length comes from `limit_window_seconds`.
- This maps cleanly onto the **Usage Window** concept (rolling consumption + reset timing), the same normalized shape used for Claude Code's `five_hour`/`seven_day`.
- **Field encodings differ from Claude Code — the Codex parser cannot reuse Claude's:**
  - `used_percent` is an **integer percent (0–100)**. (Claude's `utilization` is a float percent.)
  - `reset_at` is **Unix epoch seconds (integer)**. (Claude's `resets_at` is an ISO-8601 string. Note: the old, wrong Claude reconstruction assumed epoch seconds; for Codex it genuinely is.)
  - `limit_window_seconds` gives the window length in seconds (≈ `18000` for 5-hour, `604800` for weekly).
- `credits` is a dollar-balance meter (`balance` is a decimal string), conceptually like Claude's `extra_usage` but simpler. Out of scope for the first Codex UI per the PRD.
- `additional_rate_limits` carries extra metered features (e.g. `codex_other`); also out of scope for the first UI.
- Same numbers also ride on response headers of normal API calls (`x-codex-primary-used-percent`, `-primary-window-minutes`, `-primary-reset-at`, and `-secondary-*`), parsed by `codex-api/src/rate_limits.rs`. The standalone GET above is preferred because it is pollable without making a chat request.

## OAuth

Codex authenticates with ChatGPT/OpenAI via OAuth (PKCE, **loopback redirect** — not a paste-the-code flow). TokenStats performs its **own** login with the same public client; it does **not** reuse or refresh Codex's stored credentials in `~/.codex/auth.json`, because refresh **rotates** the token and would break the user's real Codex session (ADR-0002).

| Param | Value |
|-------|-------|
| `client_id` | `app_EMoamEEZ73f0CkXaXp7hrann` (public, from the OSS CLI) |
| Issuer | `https://auth.openai.com` |
| Authorize URL | `https://auth.openai.com/oauth/authorize` |
| Token URL | `https://auth.openai.com/oauth/token` |
| Revoke URL | `https://auth.openai.com/oauth/revoke` |
| Redirect URI | `http://localhost:1455/auth/callback` (loopback listener; the CLI binds the default port 1455 but can use another) |
| Scopes | `openid profile email offline_access api.connectors.read api.connectors.invoke` |
| PKCE | `code_challenge` + `code_verifier`, `code_challenge_method=S256`, `response_type=code` |
| Refresh | `grant_type=refresh_token`; **rotates** the refresh token |

Other authorize params the CLI sends: `id_token_add_organizations=true`, `codex_cli_simplified_flow=true`, `state`, and an `originator`. The `ChatGPT-Account-Id` needed for the usage call comes from the id_token claims, so it is available from TokenStats' own login without touching Codex's files.

Flow: build the authorize URL with PKCE → open in browser → user approves → OpenAI redirects to the loopback callback with the code → exchange code + verifier at the token URL → store tokens in TokenStats' own store → refresh on expiry. Unlike Claude Code's paste-the-code flow, the registered redirect is a localhost callback, so TokenStats can capture the code via a short-lived loopback listener instead of asking the user to paste.
