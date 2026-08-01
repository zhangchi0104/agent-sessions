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
publishes a complete USD-based table without an API key. Its daily cadence is
appropriate for a non-billing estimate, but it is still an external network
dependency with no role in usage collection.

## Decision

- `ApiCostEstimate.costUSD` and every price in the catalog remain exact USD.
- macOS stores either **System Region** or an explicit ISO 4217 currency code.
  A missing or damaged preference resolves to System Region for both new and
  existing installations.
- macOS requests only
  `GET https://api.frankfurter.dev/v2/rates?base=USD`, caches the complete valid
  table in UserDefaults, and records the attempt before sending it.
- Automatic attempts are limited to one per rolling 24 hours. Launch, wake,
  activation, timers, and Refresh All coalesce behind that limit. A failure
  does not start a retry loop or exponential backoff. Settings may offer an
  explicit retry after a failure; each retry is one additional user-initiated
  request and restarts the automatic 24-hour window.
- A response is accepted only when it is HTTP 200, every base is USD, every
  quote is a unique well-formed currency code, and every rate is positive. The
  provider validates and omits USD's identity row. It also validates but omits
  known provider or newer ISO codes the host macOS cannot localize or format,
  retaining the complete usable table instead of poisoning it with
  platform-unsupported rows. Every other unknown code rejects the response.
  Bad responses never replace the last-known-good table. Quote dates are
  preserved per currency; cache age uses the local fetch and attempt timestamps.
- Conversion happens once: exact aggregate USD multiplied by the chosen rate,
  followed by one upward rounding operation at the target currency's standard
  minor unit. The app never converts the already rounded USD display value.
- A stale last-known-good rate remains usable with an explicit warning. If no
  selected quote exists, the UI labels and displays a USD fallback; it never
  invents a 1:1 conversion.
- A currency change is a unit change. It settles via a short crossfade rather
  than a cross-currency numeric roll, and Reduce Motion removes the transition.
- The onboarding disclosure names Frankfurter. The fixed request contains no
  account credentials, tokens, usage, transcripts, calculated costs, or region
  selection, although ordinary network metadata such as an IP address reaches
  the service.

## Consequences

- Users can read the estimate in a familiar currency while the testable USD
  pricing domain stays stable.
- A full-table cache makes currency changes work offline and avoids one request
  per selection.
- Stale and fallback states are visible, so availability problems cannot be
  mistaken for current market data or an exact bill.
- macOS and Windows temporarily differ at the presentation boundary. A future
  Windows implementation must reuse the same exact-USD-then-convert and target
  minor-unit behavior, but remains a separate native implementation under
  ADR-0006.
