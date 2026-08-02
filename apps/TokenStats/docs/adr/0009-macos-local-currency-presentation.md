# 9. macOS may present the canonical USD estimate in a local currency

Date: 2026-08-01

Status: Accepted

Amends the macOS API-equivalent presentation described by
[ADR-0006](0006-native-windows-companion.md). Windows remains USD-only in this
first release.

## Context

TokenStats derives its API-equivalent usage estimate from model-attributed
transcript tokens and official USD list prices. USD is therefore part of the
estimate's domain contract, while the currency a person wants to read is a
presentation preference. Treating a converted amount as source data would make
the same transcript history change meaning as rates move and would invite
double rounding.

The macOS client also needs a low-maintenance reference-rate source. Frankfurter
publishes a complete USD-based table without an API key and remains the default,
but some users need to select a different public endpoint for availability or
policy reasons. Every supported service remains an external network dependency
with no role in usage collection.

## Decision

- `ApiCostEstimate.costUSD` and every price in the catalog remain exact USD.
- macOS stores either **System Region** or an explicit ISO 4217 currency code.
  A missing or damaged preference resolves to fixed USD. An explicitly saved
  System Region preference continues to resolve dynamically from the Mac locale.
  The pre-release v1 implicit System Region default migrates to fixed USD;
  explicit fixed-currency choices survive that migration.
- The rate source is one known response adapter plus one HTTPS endpoint.
  Frankfurter v2 JSON is the default. ExchangeRate-API Open v6 JSON and the
  European Central Bank's SDMX CSV endpoint are also supported. The ECB adapter
  derives USD cross-rates once from its latest EUR reference-rate table.
- Settings prefill each adapter's public, keyless default endpoint and retain a
  successfully verified per-adapter override. Endpoints must be absolute HTTPS
  URLs without fragments and must continue to speak the selected adapter's
  schema. TokenStats exposes no credential field or secret storage here. It
  rejects URL user-info, known credential parameter names, and the known keyed
  ExchangeRate-API host, and warns that arbitrary path/query text is user-entered
  and must never contain a secret.
- Changing the source performs one validation fetch and parse before atomically
  activating the candidate, its complete table, its successful attempt, and its
  24-hour gate. A validation failure leaves the previous source, table, and gate
  untouched. TokenStats never fails over to a different service automatically.
- The cached table and every attempt are stamped with their exact source. State
  whose source does not match the active preference is not presented as active
  rate data. The complete valid table and preferences remain in UserDefaults.
- Network requests reject redirects. The configured HTTPS endpoint is therefore
  the exact service contacted, rather than an entry point that may silently
  forward request metadata to another host or downgrade the connection.
- Automatic attempts for the active source are limited to one per rolling 24
  hours. Launch, wake, activation, timers, and Refresh All coalesce behind that
  limit. A failure does not start a retry loop or exponential backoff. Settings
  may offer an explicit retry after a failure; each retry is one additional
  user-initiated request and restarts the automatic 24-hour window.
- Each adapter requires HTTP 200 and strictly validates its native contract
  before normalization. Frankfurter and ExchangeRate-API require direct USD
  tables and an exact USD identity rate. ECB requires daily EUR-denominated
  reference rows plus a USD anchor on the same latest observation date, then
  derives each USD cross-rate once. All three normalize into one complete USD
  table of unique, well-formed currency codes and positive rates. They validate
  but omit known provider or newer ISO codes the host macOS cannot localize or
  format; every other unknown code rejects the response. Bad responses never
  replace the last-known-good table. Quote dates are preserved per currency;
  cache age uses the local fetch and attempt timestamps.
- Conversion happens once: exact aggregate USD multiplied by the chosen rate,
  followed by one upward rounding operation at the target currency's standard
  minor unit. The app never converts the already rounded USD display value.
- A stale last-known-good rate remains usable with an explicit warning. If no
  selected quote exists, the UI labels and displays a USD fallback; it never
  invents a 1:1 conversion.
- A currency change is a unit change. It settles via a short crossfade rather
  than a cross-currency numeric roll, and Reduce Motion removes the transition.
- Settings show the active provider, complete endpoint, provider-specific
  attribution, and documentation. ExchangeRate-API uses its required
  `Rates By Exchange Rate API` attribution link; the ECB presentation explains
  that TokenStats derives USD cross-rates from EUR reference rates.
- The onboarding disclosure identifies Frankfurter as the default and explains
  that only the user's selected HTTPS service is contacted. TokenStats adds no
  account, token, usage, transcript, calculated-cost, or region data. The selected
  host receives the configured URL path and query plus ordinary network metadata,
  so credentials and API keys are prohibited in the URL.

## Consequences

- Users can read the estimate in a familiar currency while the testable USD
  pricing domain stays stable.
- A full-table cache makes currency changes work offline and avoids one request
  per selection.
- Source verification prevents an invalid override from discarding a working
  cache, while source stamping prevents rates from being misattributed after a
  provider change.
- Stale and fallback states are visible, so availability problems cannot be
  mistaken for current market data or an exact bill.
- macOS and Windows temporarily differ at the presentation boundary. A future
  Windows implementation must reuse the same exact-USD-then-convert and target
  minor-unit behavior, but remains a separate native implementation under
  ADR-0006.
