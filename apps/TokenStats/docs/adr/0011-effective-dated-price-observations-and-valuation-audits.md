# 11. API-equivalent pricing uses immutable observations and audit snapshots

Date: 2026-08-24

Status: Accepted

Amends [ADR-0003](0003-tokens-today-stays-an-in-process-estimate.md),
[ADR-0006](0006-native-windows-companion.md),
[ADR-0007](0007-local-token-parse-cache.md), and
[ADR-0008](0008-macos-transcript-parse-checkpoints.md). The Token Odometer and
its parse state remain transcript-derived and in-process. This ADR permits a
separate durable audit of derived API-equivalent calculations.

## Context

The pricing catalog previously replaced one Model's rate in place and valued a
whole Today/7-day/30-day range with the current date. Both choices make an old
range change value when a provider changes its price. `lastReviewed` proves only
when TokenStats checked a catalog; it is not a price snapshot and cannot answer
which rate was applied to a past day.

Providers also publish changes with different provenance. Some pages name an
effective date. Others, including the GPT-5.6 Sol page checked on 2026-08-24,
show the current price without saying when it became effective. Inventing a
provider effective date would create false billing history; ignoring dates
would reprice every historical token.

The local transcript record is still insufficient to reconstruct an invoice.
In particular, TokenStats cannot reliably recover per-request long-context
thresholds, cache-write quantities, processing tier, regional processing,
discounts, or non-token charges. The price catalog can preserve those published
terms as evidence without pretending the current three-kind Token Odometer can
apply all of them.

## Decision

1. A catalog change appends an immutable **price observation**. Each observation
   has a stable ID, provider/Coding Agent, Model prefix, exact USD rates,
   `observedAt`, optional interval boundaries, a boundary basis, and the exact
   official source URL. Published but currently uncomputable conditions such as
   cache-write and long-context rates remain observation metadata.
2. A provider-announced effective date is used when available. When it is not,
   the verified `observedAt` day becomes the calculation boundary and is labeled
   `observedAt`, never `providerEffectiveDate`.
3. Transcript aggregation retains local day + Model through the pricing seam.
   The table may still aggregate by Model, but API-equivalent USD is calculated
   from daily Model buckets. Older observations remain resolvable and are not
   edited into the new price.
4. Both clients keep one durable **valuation audit snapshot** for each
   range/agent scope and catalog revision. It contains the exact decimal USD
   result, three token-kind totals, priced/unpriced counts, usage-day bounds,
   calculation time, and applied observation IDs. A growing live total replaces
   only the same scope/revision row. A new revision appends a row, preserving the
   previous method's last result.
5. macOS stores the small versioned history in its app preferences. Windows
   stores versioned JSON at
   `%LocalAppData%\TokenStats\api-valuations-v1.json` with same-directory
   temporary writes and atomic replacement. Test/runtime isolation injects a
   process-only or temporary store. An unreadable, duplicate-key, or unsupported
   schema history fails closed: the clients keep the original payload, skip the
   new snapshot, and continue rendering the live estimate. Windows filesystem
   write failures are likewise best-effort and never escape into UI rendering.
6. Audit snapshots are not read as Token Odometer input and do not restore
   deleted, archived, or newly unreadable transcripts. They do not enter the
   shared SQLite sessions database, IPC, parse checkpoints, or exchange-rate
   cache. The live UI continues to derive canonical USD from current transcript
   truth and then applies ADR-0009's display-only currency conversion.

## Current GPT-5.6 Sol observation

On 2026-08-24, the official OpenAI model and pricing pages showed these Standard
rates per million tokens:

| Context | Input | Cached input | Cache write | Output |
| --- | ---: | ---: | ---: | ---: |
| up to 272K input tokens | $4.00 | $0.40 | $5.00 | $20.00 |
| above 272K input tokens | $8.00 | $0.80 | $10.00 | $30.00 |

OpenAI says the promotion lasts at least through 2026-11-21. The checked pages
did not state the reduction's effective date, so TokenStats uses 2026-08-24 as
an observation boundary. The prior $5.00/$0.50/$30.00 computable three-kind
rate remains available before that boundary. The new cache-write and
long-context terms are recorded but not applied to the displayed estimate until
transcript evidence can select them without guessing.

Sources:

- <https://developers.openai.com/api/docs/models/gpt-5.6-sol>
- <https://developers.openai.com/api/docs/pricing>

## Consequences

- Historical day buckets keep the price version that was applicable under the
  recorded boundary, and previous catalog-revision calculations remain
  inspectable in durable app-local history.
- A newly discovered official effective date can be appended as a corrected
  observation in a later catalog revision without deleting the audit result
  produced by this observed-date fallback.
- The feature remains an API-equivalent estimate. Recording complete official
  terms improves provenance but does not turn transcript aggregation into an
  invoice reconstruction.
