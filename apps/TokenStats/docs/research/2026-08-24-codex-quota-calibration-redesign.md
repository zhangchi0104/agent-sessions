# Codex quota calibration redesign plan

**Date:** 2026-08-24

**Status:** Draft research plan. The reviewed prototype is not part of `main`.

**Decision:** TokenStats must not present a Codex quota-capacity estimate until the relationship
between the remote Usage Window and locally captured transcript usage has been demonstrated with
controlled live evidence. The next iteration starts as a research instrument, not a product
feature.

This plan preserves the boundaries in [CONTEXT](../../CONTEXT.md),
[ADR-0002](../adr/0002-codex-usage-via-independent-oauth.md),
[ADR-0003](../adr/0003-tokens-today-stays-an-in-process-estimate.md), and
[ADR-0008](../adr/0008-macos-transcript-parse-checkpoints.md). It does not amend those decisions.
If research supports a user-facing feature, the product decision requires a new ADR after the
evidence review.

---

## 1. Why the current design was discarded

The prototype was internally testable, but internal consistency is not measurement validity. It
implemented a complete settings surface, persistent samples, stability labels, two-window
coordination, and a cross-platform contract before producing controlled live samples that showed
the estimate tracked Codex quota consumption.

### 1.1 The estimator assumes a relationship that has not been established

The prototype extrapolated a full window from one observation:

```text
estimated capacity = locally observed usage × 100 / remote percentage-point delta
```

That calculation assumes the remote quota meter is approximately linear in the chosen local token
or API-equivalent measure. No repository-controlled live evidence currently establishes that
assumption. Model, reasoning mode, context reuse, cache behavior, tools, images, voice, execution
location, plan, credits, or service-side policy may affect the remote meter differently. These are
hypotheses to test, not inputs that can be assigned weights locally.

The Codex endpoint reports `used_percent` as an integer. Its rounding, update cadence, lag, and
metering semantics have not been live-validated for this use. A range derived only from integer
quantization is therefore not a confidence interval and must not be labeled as accuracy.

API-equivalent cost is also a price projection over locally observed tokens. It is not evidence of
how a ChatGPT subscription quota is metered.

### 1.2 The capture boundary can pair observations from different intervals

The prototype's fresh-usage path could join an already-running usage request. That request may
have started before the transcript baseline used for the same sample. A response obtained later is
not enough to make it temporally fresh: the remote observation and local transcript delta can cover
different intervals.

A valid calibration capture must prove request ordering. It must never reuse a request that started
before the local boundary, even when request coalescing is otherwise useful for the normal Usage
Window UI.

### 1.3 The two sources do not have proven matching coverage

The remote Usage Window is scoped to the selected ChatGPT account or workspace. The local Token
Odometer reads visible local transcripts and remains an in-process estimate by design. Local capture
cannot automatically account for work performed on another device, in a cloud environment, by a
shared account, or in a transcript root TokenStats does not scan. Deleted, moved, archived,
truncated, or replaced files can also break continuity.

It is additionally unknown whether all remotely metered activity has an equivalent local transcript
token representation. Until coverage is demonstrated, source agreement must be treated as an
experimental result rather than an invariant.

### 1.4 Product scope expanded before the core claim was proven

The discarded design introduced several layers that cannot improve a biased measurement:

- five-hour and weekly calibration were started and blocked as one global lifecycle;
- persistent account-scoped history and a multi-reset "stable" label risked implying validated
  accuracy;
- a second Codex sign-in surface duplicated the existing Subscriptions workflow;
- a platform-neutral JSON contract had no second implementation or consumer;
- detailed model/token-kind tables repeated Token Odometer concepts inside quota calibration;
- release-visible settings UI existed before controlled five-hour or weekly validation and UI
  automation.

These layers are out of scope until the source relationship is proven. Passing unit and static
checks only shows that the implementation follows its own assumptions.

---

## 2. Established facts and unresolved hypotheses

### Established from current source and repository decisions

- The independently authenticated Codex usage endpoint is the intended remote source for TokenStats
  Usage Windows. Its contract is source-confirmed, while live-traffic confirmation is still pending;
  see [the Codex integration reference](../codex-integration.md).
- Codex source describes the standalone usage request as a read-only GET. Whether bounded live
  control requests have any effect below the integer endpoint's resolution remains unknown.
- A Usage Window represents remote consumption and reset timing. It is not a token counter.
- The local Token Odometer is an incomplete local estimate and must not be presented as an official
  bill, quota, or server-side usage total.
- In the production macOS app, transcript discovery remains gated by a visible Tokens tab.
  TokenStats must not add hidden launch-time or background scans for calibration. A research
  recorder must therefore be an independent development/test harness, or run only from an explicit
  action while the Tokens tab is visible. Running it elsewhere requires a separate ADR decision.
- Transcript parse checkpoints are disposable performance metadata, not accounting authority.
- `used_percent` is integer-valued in the currently documented Codex payload shape.

### Hypotheses that require live evidence

- Remote percentage consumption is sufficiently linear in some locally observable metric.
- Reporting lag is bounded tightly enough to bracket a sample without attributing unrelated work.
- A local transcript source covers enough account activity for a useful estimate.
- The relationship is usable across the recorded models, modes, tools, reset epochs, plans, and
  service versions, and drift can be detected when those conditions change.
- Five-hour behavior can be generalized to the weekly window.

None of these hypotheses should appear as a product promise or an ADR premise before the experiment
described below.

---

## 3. Redesign principles

1. **Research before estimation.** The first build records paired observations and uncertainty; it
   does not output a "total quota" or "tokens remaining" value.
2. **One window at a time.** Start with the five-hour window. Each window has an independent
   lifecycle; weekly work begins only after the five-hour protocol is sound.
3. **Strict temporal bracketing.** A calibration usage request must start after its local transcript
   boundary. It must not join or overlap a request created by the normal refresh path. An exclusive
   study lease covers the baseline, controlled workload, stabilization reads, and final observation.
4. **Fail closed on contamination.** Reject a sample on account, plan, reset epoch, duration,
   transcript continuity, concurrent activity, or request-order mismatch. Do not repair or silently
   reinterpret it.
5. **Process memory first.** No persistent history, account fingerprinting, stability badges, or
   cleanup relay in the research version.
6. **No hidden work.** In the production macOS app, calibration transcript access is explicitly
   user-triggered and runs only while the Tokens tab is visible. Existing Token Odometer scans remain
   visibility-gated and event-driven. Otherwise the recorder is an independent development/test
   harness. Calibration must not turn the Token Odometer into a startup or background scanner.
7. **Minimal data retention.** Calibration research never persists raw transcript content,
   transcript paths, account IDs, credentials, authorization material, or raw endpoint responses.
   Application state is process-only by default. An export requires an explicit manual action and
   contains only normalized aggregate counters, window metadata, timestamps, build/version context,
   and quality flags whose provenance is `source-derived`, `instrumented`, `operator-attested`, or
   `unknown`. TokenStats' existing isolated OAuth Keychain storage remains governed by ADR-0002 and
   is outside the research dataset.
8. **Separate measurements.** Usage Window percentage, Token Odometer tokens, and API-equivalent cost
   remain distinct quantities even if an experiment compares them.
9. **No release exposure by default.** Research instrumentation must be development-only or guarded
   by an explicit feature flag until all release gates are met.

---

## 4. Proposed capture protocol

The protocol must be implemented separately from normal refresh coalescing and covered by ordering
tests.

### Measurement isolation and local range

- Acquire an exclusive usage-study lease before the first `L0-before` snapshot. Wait for or reject
  every existing normal refresh; then prevent timer, wake, manual, or other normal usage requests
  until the full study completes or is cancelled. Release the lease only after the last bounded
  stabilization bracket. Count every measurement request against one study-wide request budget.
- Every measurement request must be network-fresh. It cannot use a stale or last-known fallback and
  must not update the normal Usage Window's last-known value, timer, backoff, or refresh UI state.
- The same auth generation and selected account/workspace must remain active for the full baseline,
  work interval, and final observation.
- Use a monotonic clock to prove in-process ordering. Also record wall-clock time for the report, a
  measurement generation and request ID, and any server-provided observation time as supporting
  evidence. Local response-end time must not be presented as the server's sampling time.
- The research delta is range-independent. It is the cumulative change in the visible
  `~/.codex/sessions` corpus, not the selected Today/7-day/30-day Token Odometer range.
  `~/.codex/archived_sessions` remains outside the scan and is a known coverage gap.
- Missing, moved, replaced, or truncated baseline files invalidate the sample. A newly created file
  may contribute from zero when its creation is observed inside the interval. An app or harness
  restart invalidates the process-only research baseline even if parse checkpoints survive.
- Quiet brackets require no other local Codex request in flight and no change to transcript corpus
  membership, file identity, length, modification time, validation fingerprint, safe cursor, or
  partial-line state. Any relevant append or FSEvent rejects the bracket even when aggregate tokens
  did not move. During the controlled work interval, expected appends/new files are allowed, while
  missing, moved, replaced, or truncated baseline files still reject the study.
- Keep direct-input, cache-read, and output Token Kinds, response count, and transcript-reported
  Model aggregates. Record the researcher's intended workload model/mode separately; a mismatch
  with transcript-reported Models is contamination, not a relabeling opportunity.

### Baseline

1. Require an authenticated account and one explicitly selected remote window.
2. Require transcript visibility, instrumented local quiet, and an operator attestation that no
   known second device, cloud task, or shared user is active. Off-device quiet cannot be proven by
   TokenStats and remains operator-attested or unknown.
3. Acquire the study lease and capture local snapshot `L0-before`.
4. Start a new, non-coalesced usage request `U0` and record monotonic request-start and response-end
   times.
5. Capture `L0-after` after the response while retaining the study lease.
6. Accept the baseline only when transcript continuity and all quiet-bracket invariants hold between
   `L0-before` and `L0-after`.

### Work interval

The user performs one controlled workload. The research build records the intended workload
model/mode, transcript-reported Models, app version, OS version, Codex version, account plan
category, selected window duration/reset epoch, and whether any known contaminating source was
active. It must not record prompts or responses.

### Final observation

1. Return the local source to a quiet state under the existing study lease and capture `L1-before`.
2. Start a new, non-coalesced usage request `U1` after `L1-before` and record its monotonic
   timestamps.
3. Capture `L1-after` after the response. Release the study lease only after the final bounded
   stabilization bracket or cancellation cleanup.
4. Reject the sample if any quiet-bracket invariant changed during the final request or if account,
   plan, credits state, window duration, reset epoch, or source continuity differs from the baseline.
5. Keep the normalized paired aggregates (`U0`, `U1`, local delta, timestamps, quality flags) in
   process for analysis. Do not convert them into a product capacity claim.

Server-side reporting lag may still invalidate a perfectly ordered local bracket. Phase 1 must
measure that lag with a predeclared, bounded stabilization sequence before and after the workload.
Every read in the sequence gets its own transcript bracket; the report retains the complete sequence
and does not select the point that best matches the local delta. Maximum requests, elapsed time, and
interval are fixed before the run. The implementation must not hide lag with unbounded polling or
present an invented delay as evidence.

### Sanitized research export

The app must not write samples to UserDefaults, a history database, or an account-derived stable
identifier. A researcher may explicitly export normalized observations to a user-selected or
test-only directory after reviewing the fields. A random study/run ID can connect approved exports
across reset epochs. The research protocol must define access and deletion dates for those files.
Rejected samples may appear only in this explicit export, with their rejection reason and without
sensitive source material.

---

## 5. Research phases

### Authorization and stop rules for live work

This document authorizes design and local static testing only. Before any live usage request or
controlled Codex workload, the experiment owner must approve the exact account/workspace,
environment, time window, maximum usage requests, maximum workload, maximum allowed Usage Window
movement, and credits budget. The default credits budget is zero. Use only a designated account
whose activity can be controlled; do not experiment on an uncoordinated shared or production
workspace.

Quota/account approval does not authorize other side effects. Use synthetic inputs and a temporary,
disposable local workspace by default. Phase 1 disables project hooks, MCP integrations, tools, and
external writes; the only expected mutations are the designated account's approved Codex usage and
Codex's own local research transcript/state. Never infer permission to deploy, send messages, push,
delete, or mutate another service. Phase 2 may add only predeclared, recoverable local-fixture side
effects unless the owner separately authorizes an exact external action and target.

Keep automatic recharge or extra-usage charging disabled for a zero-credit experiment. If that
cannot be confirmed, do not run the live workload. Any paid-credits experiment requires a new,
explicit non-zero monetary cap and stop rule from the account owner.

Stop immediately on an unexpected account/plan/window, reset rollover, credits activation or
balance change, rate-limit response, payload-shape change, concurrent unapproved activity,
transcript discontinuity, or any pre-approved request/time/workload ceiling. A delta below endpoint
resolution is an inconclusive sample, not permission to increase the workload.

### Phase 0 — confirm the sources and instrumentation

- Confirm the endpoint, required header names, payload shape, plan metadata, window durations, reset
  behavior, and source-indicated read-only GET behavior against a recorded stock Codex version and
  TokenStats' independently authenticated test session. Never read, copy, refresh, or proxy
  `~/.codex/auth.json`; never record a bearer token, cookie, auth code, ID-token claim,
  `ChatGPT-Account-Id`, or raw response body.
- The research harness may decode a field whitelist containing plan, credits, transient
  account/workspace continuity, and duration into an experiment-only DTO, process state, and
  sanitized exports. This does not add those fields to the product's public Usage Window model or
  persistence contract. Missing continuity metadata rejects the sample.
- Demonstrate with timestamps that calibration never reuses a usage request created before the local
  boundary.
- Run a predeclared, bounded series of no-work controls. Report whether the usage GET creates local
  transcript activity or any measurable Usage Window/credits change at endpoint resolution; effects
  below that resolution remain unknown and must not be reported as zero consumption.
- Exercise transcript truncation, replacement, rename, and root loss only through temporary roots,
  synthetic transcripts, and fake providers. Never delete, truncate, rename, move, or replace a
  real file under `~/.codex`. Exercise reset rollover, sign-out, cancellation, and
  concurrent-refresh rejection without producing a valid sample.

Exit result: a development-only paired-observation recorder. No estimator and no settings product
surface.

### Phase 1 — controlled five-hour experiments

- Use one account, one machine, one Codex version, one model/mode, standard service speed, and no
  cloud, shared-account, voice, image, tool, hook, MCP, network-write, or second-device activity.
- Pre-register the candidate metrics and selection rule: each Token Kind, response count,
  transcript-reported Model combinations, and API-equivalent USD. For API-equivalent analysis,
  retain the underlying token components and record the pricing-catalog revision and review date.
- Make prediction or explanation of `delta used_percent` the first target. Do not derive a 100%
  capacity during metric selection.
- Use only pre-authorized bounded workloads. If they do not produce an observable change, report an
  inconclusive run instead of silently increasing traffic.
- Repeat observations at different points within a window across at least three independent reset
  epochs for protocol and metric development. Freeze the metric, quality rules, and error threshold
  before at least one additional held-out reset epoch.
- Measure reporting lag, percentage quantization, monotonicity, variance, and held-out residual
  error. Retain rejected samples and their rejection reasons only in the approved sanitized research
  export, not in product history.

Exit result: an evidence report that either rejects the relationship or identifies a bounded
candidate metric. It still does not justify a stable product label by itself.

### Phase 2 — coverage and adversarial experiments

Vary one factor at a time under a new approved budget: model, reasoning mode, context/cache behavior,
local read-only/no-op tools, long-running tasks, service speed, credits state, and reset rollover.
Any tool side effect must be predeclared and confined to a recoverable temporary fixture; an external
state change requires separate authorization for that exact action and target. Separately labeled
contamination experiments for another controlled device or cloud work also require explicit
authorization. Archived/moved transcript behavior uses synthetic temporary fixtures only. Do not
recruit third-party activity or use a normal shared workspace to manufacture contamination.

Weekly-window experiments begin only if Phase 1 establishes a repeatable five-hour protocol. Weekly
observations must remain independent; an incomplete weekly sample must never block a new five-hour
sample.

Exit result: evidence about where the relationship holds, where it fails, and which conditions can
be detected reliably by the app.

### Phase 3 — product decision

Choose one outcome explicitly:

1. **Discard quota calibration.** Keep Usage Windows, Token Odometer totals, and API-equivalent cost
   as separate surfaces with their existing caveats.
2. **Ship a narrowly bounded observation.** Display only what the experiments support, potentially
   as a per-sample range or workload-specific relationship rather than a full quota capacity.
3. **Continue research.** Do not ship while error, coverage, or service-side semantics remain
   unresolved.

Only outcome 2 proceeds to a new ADR, product copy, persistence design, accessibility review, UI
automation, localization, and any cross-platform contract.

---

## 6. Gates before user-facing implementation

All gates are mandatory:

- **Source gate:** live endpoint identity and observable semantics are confirmed at the endpoint's
  resolution, residual unknowns are stated, and version/date evidence is recorded without secrets.
- **Ordering gate:** tests and instrumented traces prove both usage requests start after their local
  boundaries and cannot join older flights.
- **Continuity gate:** every accepted sample has an intact, quiet local source and a single account,
  plan, duration, and reset epoch.
- **Coverage gate:** controlled results include at least three independent exploratory five-hour
  reset epochs plus one held-out reset epoch; known unobservable account activity is documented.
- **Accuracy gate:** candidate selection, quality rules, and an acceptable error/variance threshold
  are frozen before held-out validation. The threshold is intentionally not invented in this plan.
- **Semantics gate:** copy states exactly what was measured and never equates local tokens or
  API-equivalent price with an official subscription quota.
- **Privacy gate:** no calibration research export, history, or derived product data stores raw or
  account-derived stable identifiers. TokenStats' existing isolated OAuth Keychain storage remains
  outside this research dataset.
- **Release gate:** the feature is isolated from stable release until focused domain tests, UI
  automation, cancellation/sign-out coverage, localization, and a manual live protocol pass.

Stop the work and choose Phase 3 outcome 1 if the dominant remote consumption cannot be observed
locally, if the relationship is not repeatable across reset epochs, if reporting lag cannot be
bounded safely, or if a useful accuracy threshold cannot be met without misleading users.

---

## 7. Scope explicitly left behind

The removed prototype is research input, not a merge source. Do not restore its settings pane,
history/stability store, coupled five-hour/weekly state, duplicate sign-in UI, platform contract, or
capacity labels as the starting point for the redesign.

General improvements discovered during the prototype—such as duration provenance, auth-generation
guards, or additional response metadata—may be proposed independently when they solve an existing
Usage Window problem. They must not be smuggled back into `main` solely as prerequisites for an
unproven estimator.

The Phase 0 field-whitelist DTO is isolated inside the development harness and does not itself
justify a change to the production `UsageSnapshot` or persistence contract.

The next code change, if Phase 0 is authorized, should branch from the current remote `main` and add
only the development-only paired-observation recorder plus its ordering and continuity tests.
