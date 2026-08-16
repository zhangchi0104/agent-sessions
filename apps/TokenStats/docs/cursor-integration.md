# Cursor integration reference

Facts about Cursor's subscription-usage surface. These endpoints are
**unofficial and undocumented**. They were recovered from the locally installed
Cursor desktop app 3.15.19 and Cursor Agent CLI 2026.04.08 on 2026-08-16. Treat
them as a compatibility surface to monitor, not a provider contract.

Do not store access tokens, refresh tokens, cookies, auth responses, prompts, or
other sensitive capture material in this repository. The OAuth `client_id`
below is a public identifier embedded in Cursor's shipped client, not a secret.

## Product mapping

Cursor's dashboard response reports the same two subscription buckets shown in
its official UI. TokenStats maps them to two authoritative Usage Windows that
share the subscription billing-cycle reset:

- **Cursor Models** consumed percentage: `autoPercentUsed`;
- **Other Models** consumed percentage: `apiPercentUsed`; and
- reset for both: `billingCycleEnd`, encoded by Connect JSON as a decimal string
  of Unix epoch milliseconds. The parser also accepts a JSON number for
  compatibility.

Each percentage is clamped to 0...100. `includedSpend / limit`,
`totalPercentUsed`, and the response's generic `displayMessage` are aggregate
spend views and do not represent either official dashboard bucket. TokenStats
therefore does not use them as a gauge or fallback. Integer spend fields are
cents, but TokenStats does not present them as an invoice or balance.

Cursor does not expose a compatible local transcript stream for TokenStats'
Token Odometer. Cursor is therefore supported on the Usage and menu-bar
surfaces only; the Tokens display setting shows no Cursor toggle.

## Usage source

Cursor's desktop dashboard sends a Connect JSON request to:

```http
POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage
Authorization: Bearer <Cursor access token>
Content-Type: application/json
Connect-Protocol-Version: 1

{}
```

The response shape used by TokenStats is:

```jsonc
{
  "billingCycleStart": "1997408000000",
  "billingCycleEnd": "2000000000000",
  "planUsage": {
    "totalSpend": 900,
    "includedSpend": 365,
    "bonusSpend": 150,
    "remaining": 1635,
    "limit": 2000,
    "autoPercentUsed": 1.2166666666666666,
    "apiPercentUsed": 0,
    "totalPercentUsed": 1.0579710144927537
  },
  "enabled": true
}
```

Connect's camel-case names are canonical, and its int64 values are decimal
strings. The parser also accepts numeric int64 values and snake-case names
defensively because older generated clients used those forms.

Cursor's public Admin API reports team-member usage and requires team-admin
credentials; it is not a substitute for an individual's subscription Usage
Window. No public individual usage API was documented at discovery time.

## Independent browser login

TokenStats follows Cursor Agent's PKCE browser login but owns a separate token
pair. It never reads or refreshes Cursor's own credential store.

1. Generate a 32-byte PKCE verifier/challenge and a UUID.
2. Open
   `https://cursor.com/loginDeepControl?challenge=...&uuid=...&mode=login&redirectTarget=cli`.
3. Poll
   `GET https://api2.cursor.sh/auth/poll?uuid=...&verifier=...`; HTTP 404 means
   approval is still pending, and HTTP 200 returns `accessToken` and
   `refreshToken`.
4. Store the pair in TokenStats' own `cursor` keychain item.
5. Refresh at `POST https://api2.cursor.sh/oauth/token` with JSON
   `grant_type=refresh_token`, the refresh token, and public client id
   `KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB`.

Cursor's current client uses the returned `access_token` as the next refresh
credential when the response omits a separate `refresh_token`; TokenStats
matches that rotation behavior.
