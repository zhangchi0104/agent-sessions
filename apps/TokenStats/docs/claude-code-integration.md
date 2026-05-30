# Claude Code integration reference

Facts discovered by reading the shipped Claude Code binary (v2.1.152, native install). These are **unofficial and undocumented** — see ADR-0001. Treat them as a starting point to verify empirically, not a contract.

## Usage endpoint

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <oauth access token>
```

Response shape — **empirically confirmed against the live endpoint on 2026-05-28**
(this corrects the earlier binary reconstruction, which was wrong on both field
encodings):

```jsonc
{
  "five_hour": { "utilization": 24.0, "resets_at": "2026-05-28T04:09:59.816765+00:00" }, // primary "session limit"
  "seven_day": { "utilization": 18.0, "resets_at": "2026-05-28T06:00:00.816789+00:00" }, // "weekly limit"
  "seven_day_oauth_apps": null,
  "extra_usage": { "is_enabled": true, "monthly_limit": 15500, "used_credits": 5652.0, "utilization": 36.46, "currency": "AUD" }, // credit amounts are in cents: 5652 = $56.52 of $155.00
  // also seen: seven_day_opus, seven_day_sonnet, overage
}
```

- `utilization` is **already a percent (0–100)** — use it directly. (The old
  "fraction 0..1, multiply by 100" reconstruction was wrong: real values like
  `24.0` would be 2400%.)
- `resets_at` is an **ISO-8601 timestamp string** with fractional seconds and an
  explicit UTC offset — NOT Unix epoch seconds. Parse with `ISO8601DateFormatter`
  (`.withFractionalSeconds`); fall back by stripping the fraction for robustness.
- `resets_at` may also be explicit `null` when utilization is `0.0`; keep the
  Usage Window and treat reset time as unavailable rather than dropping it.
- On usage-credit plans, the Usage Window fields may be zero/null placeholders
  while `extra_usage` carries the meaningful quota percentage. TokenStats shows
  all present windows — the 5-hour/weekly rows still render (at 0% with reset
  time unavailable) alongside `extra_usage` as **Usage credits** — so the
  rate-limit windows remain visible once they start carrying data.
- Each block is optional, and unknown keys (`seven_day_oauth_apps`, etc.) appear
  and may be `null` — decode each known block independently and ignore the rest.
- Maps directly onto our normalized **Usage Window**: `five_hour` → primary,
  `seven_day` → secondary; `extra_usage` → usage-credit meter when present.

Alternative source (fallback, not chosen): the same numbers ride on normal API response headers
`anthropic-ratelimit-unified-5h-utilization`, `-7d-utilization`, `-overage-utilization`.

## OAuth (paste-the-code flow)

There are two origins. **Subscription (Pro/Max) usage uses the Claude.ai flow**, not the Console one.

| Param | Value |
|-------|-------|
| `client_id` | `9d1c250a-e61b-44d9-88ed-5944d1962f5e` |
| Authorize URL (claude.ai) | `https://claude.com/cai/oauth/authorize` (Console variant: `https://platform.claude.com/oauth/authorize`) |
| Token URL | `https://platform.claude.com/v1/oauth/token` |
| Redirect URI | `https://platform.claude.com/oauth/code/callback` (displays the code to paste) |
| Scopes | `org:create_api_key user:profile user:inference` |
| Refresh | `grant_type=refresh_token`; PKCE (`code_challenge`/`code_verifier`, S256) on the initial exchange |

Flow: build the authorize URL with PKCE → open in browser → user approves → callback page shows an
auth code → user pastes it into TokenStats → exchange code + verifier at the token URL → store tokens in
TokenStats' own Keychain item → refresh on expiry.

## Naming note

Claude Code's own UI labels `five_hour` as **"session limit"** and `seven_day` as **"weekly limit"**. Our
glossary deliberately avoids "session" for this (it clashes with a conversation Session) and uses **Usage
Window** instead — see `CONTEXT.md`.
