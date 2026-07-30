# Goal spec: macOS Token Odometer restores disposable per-transcript checkpoints without rereading committed content

- Execution branch: `feat/macos-tokens-storage`
- Repository root: `/Users/alexzhang/code/github.com/zhangchi0104/agent-sessions`
- Frozen baseline: `a0290d59e21849f727976c42155833e744c8fe01`

## 1. End state

**A newly launched macOS TokenStats process can restore a valid, disposable, versioned checkpoint for each Claude or Codex transcript, report the same daily token totals as a cold scan, and resume only from the last safely committed record without rereading committed transcript content.**

The cache is an optimization, never authoritative history. Missing, stale, corrupt, incompatible, or unpublished entries cause a fail-open cold rebuild from the source transcript. Windows behavior, app lifecycle and UI wiring, Xcode project membership, and package scripts stay unchanged.

The checkpoint mechanism is:

1. Enumerate transcript metadata and derive a non-reversible cache key from source identity.
2. Validate a versioned/checksummed envelope, source metadata, time-zone context, bounds, and small bounded source fingerprints.
3. If valid, hydrate aggregates and provider continuation state at the last safe complete-record boundary.
4. Read and parse only bytes appended after that boundary.
5. Publish the replacement entry atomically; if publication fails, keep correct in-memory results and the prior valid entry.
6. If any validation step fails, discard the whole checkpoint state and rebuild from the transcript.

## 2. Observable success criteria

Run every command from the repository root. A criterion passes only when its entire shell block exits zero.

### S1 — Platform-neutral domain vocabulary

```zsh
rg -q \
  'TokenStats clients may keep disposable, versioned per-file parse checkpoints in their platform-local cache' \
  apps/TokenStats/CONTEXT.md &&
! rg -q \
  -e 'Windows may keep disposable' \
  -e 'Windows parse cache' \
  apps/TokenStats/CONTEXT.md
```

### S2 — Restart-safe continuation state exists independently of disk persistence

```zsh
rg -q 'safeCommittedBytes' \
  apps/TokenStats/TokenStats/Tokens/TranscriptTokenReader.swift &&
rg -q 'struct TranscriptReadStatistics' \
  apps/TokenStats/TokenStats/Tokens --glob '*.swift' &&
rg -q 'jsonLinesSubmittedForDecoding' \
  apps/TokenStats/TokenStats/Tokens --glob '*.swift' &&
rg -q 'struct TranscriptContinuationTests' \
  apps/TokenStats/TokenStatsTests/Tokens --glob '*.swift' &&
(
  cd apps/TokenStats
  set -o pipefail
  xcodebuild test \
    -project TokenStats.xcodeproj \
    -scheme TokenStats \
    -destination 'platform=macOS' \
    -only-testing:TokenStatsTests/TranscriptContinuationTests \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
    2>&1 | tee /tmp/tokenstats-transcript-continuation-tests.log
  rg -q 'Suite TranscriptContinuationTests passed' \
    /tmp/tokenstats-transcript-continuation-tests.log
)
```

The focused suite proves that durable continuation excludes partial-line bytes, advances `safeCommittedBytes` only at a complete-record boundary, bounds oversized-line state to 16 MiB, and reports source-content bytes separately from candidate JSON lines. An unfinished oversized record may additionally persist a validated `discardedThroughBytes` cursor plus discard-mode flag so a restart does not replay bytes that have already been deliberately ignored; that cursor never represents committed aggregate state.

### S3 — Fresh readers restore and resume valid checkpoints exactly

```zsh
rg -q 'struct TranscriptCheckpointTests' \
  apps/TokenStats/TokenStatsTests/Tokens --glob '*.swift' &&
(
  cd apps/TokenStats
  set -o pipefail
  xcodebuild test \
    -project TokenStats.xcodeproj \
    -scheme TokenStats \
    -destination 'platform=macOS' \
    -only-testing:TokenStatsTests/TranscriptCheckpointTests \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
    2>&1 | tee /tmp/tokenstats-transcript-checkpoint-tests.log
  rg -q 'Suite TranscriptCheckpointTests passed' \
    /tmp/tokenstats-transcript-checkpoint-tests.log
)
```

The suite must prove:

- Cold read, checkpoint write, and fresh-reader hydrate produce structurally equal daily totals.
- An unchanged warm read whose previously observed source end equals its safe continuation cursor loads one checkpoint, reads zero transcript-content bytes, and submits zero JSON lines for decoding.
- Append resumes at the exact safe committed byte boundary.
- Claude de-duplication and Codex model/baseline/pending state remain exact across restart.
- Incomplete trailing lines, multi-day totals, all token kinds, and oversized records match a cold rebuild.
- An ordinary incomplete tail is not checkpointed: a fresh reader rereads those uncommitted bytes from `safeCommittedBytes`, and the next fresh read after the line commits is a zero-content hit.
- Fingerprinting reads no more than 8 KiB per source and is accounted separately from transcript-content reads.

### S4 — Invalid data and cache I/O failures always fail open

```zsh
rg -q 'struct TranscriptCheckpointInvalidationTests' \
  apps/TokenStats/TokenStatsTests/Tokens --glob '*.swift' &&
rg -q 'struct TranscriptCheckpointStoreTests' \
  apps/TokenStats/TokenStatsTests/Tokens --glob '*.swift' &&
(
  cd apps/TokenStats
  set -o pipefail
  xcodebuild test \
    -project TokenStats.xcodeproj \
    -scheme TokenStats \
    -destination 'platform=macOS' \
    -only-testing:TokenStatsTests/TranscriptCheckpointInvalidationTests \
    -only-testing:TokenStatsTests/TranscriptCheckpointStoreTests \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
    2>&1 | tee /tmp/tokenstats-transcript-checkpoint-hardening-tests.log
  rg -q 'Suite TranscriptCheckpointInvalidationTests passed' \
    /tmp/tokenstats-transcript-checkpoint-hardening-tests.log &&
  rg -q 'Suite TranscriptCheckpointStoreTests passed' \
    /tmp/tokenstats-transcript-checkpoint-hardening-tests.log
)
```

The focused suites cover version, checksum, bounds, source identity, time zone, corruption, truncation, replacement, same-size rewrite, prefix/tail mutation, cache directory creation, write, sync, and replace failures. They also cover abandoned temporary files, deletion, rename, new-file discovery, lazy visible-window behavior, and disk reuse after the existing 48-hour in-memory eviction window.

### S5 — The accepted macOS contract is recorded

```zsh
rg -q '0008-' \
  apps/TokenStats/docs/adr/0003-tokens-today-stays-an-in-process-estimate.md &&
rg -q '0008-' \
  apps/TokenStats/docs/adr/0007-local-token-parse-cache.md &&
rg -q 'enumerat' apps/TokenStats/docs/adr/0008-*.md &&
rg -q 'fingerprint' apps/TokenStats/docs/adr/0008-*.md &&
! rg -q \
  -e 'Windows-only.*cache' \
  -e 'macOS behavior is unchanged' \
  apps/TokenStats/docs/adr/0003-*.md \
  apps/TokenStats/docs/adr/0007-*.md
```

ADR 0008 records the cache schema/version boundary, safe continuation boundary, source validation, privacy, atomic publication, invalidation, and fail-open behavior. ADRs 0003 and 0007 link to it and no longer describe the optimization as Windows-only or macOS-unchanged.

### S6 — No prototype or package-script hook ships

```zsh
! rg -q '"prototype:macos-checkpoint"' \
  apps/TokenStats/package.json &&
! rg -q 'CheckpointPrototype-PROTOTYPE' \
  apps/TokenStats/TokenStats \
  apps/TokenStats/TokenStatsTests \
  --glob '*.swift'
```

## 3. Invariants

All invariants are reasserted at every milestone gate.

### I1 — Full macOS suite remains green

```zsh
set -o pipefail
npm --prefix apps/TokenStats test \
  2>&1 | tee /tmp/tokenstats-full-tests.log
rg -q '\*\* TEST SUCCEEDED \*\*' /tmp/tokenstats-full-tests.log &&
! rg 'warning:' /tmp/tokenstats-full-tests.log |
  rg -qv \
    -e 'CodexOAuthFlow.swift:65' \
    -e 'UsageModel.swift:52'
```

The frozen baseline is 119 tests in 17 suites.

### I2 — Universal Release build remains green

```zsh
set -o pipefail
npm --prefix apps/TokenStats run build \
  2>&1 | tee /tmp/tokenstats-release-build.log
rg -q '\*\* BUILD SUCCEEDED \*\*' /tmp/tokenstats-release-build.log &&
lipo -archs \
  apps/TokenStats/build/Build/Products/Release/TokenStats.app/Contents/MacOS/TokenStats |
  rg -q \
    -e '^arm64 x86_64$' \
    -e '^x86_64 arm64$'
```

### I3 — Patch whitespace remains valid

Before commit, after staging the complete milestone:

```zsh
git diff --cached --check
```

After commit, where `<milestone-start>` is the SHA recorded immediately before that milestone:

```zsh
git diff --check <milestone-start> HEAD
```

### I4 — Branch diff remains inside the closed implementation surface

```zsh
test -z "$(
  git diff --name-only \
    a0290d59e21849f727976c42155833e744c8fe01 -- |
  rg -v \
    '^(apps/TokenStats/(CONTEXT\.md|TokenStats/Tokens/(TranscriptTokenReader|TranscriptCheckpoint[^/]*)\.swift|TokenStatsTests/Tokens/(TranscriptFixtures|TranscriptContinuationTests|TranscriptCheckpoint[^/]*)\.swift|docs/adr/000(3-tokens-today-stays-an-in-process-estimate|7-local-token-parse-cache|8-[^/]+)\.md)|docs/goals/2026-07-30-macos-token-parse-checkpoints\.md)$' ||
  true
)"
```

### I5 — App lifecycle, UI/model ownership, and Xcode membership remain unchanged

```zsh
git diff --exit-code \
  a0290d59e21849f727976c42155833e744c8fe01 -- \
  apps/TokenStats/TokenStats.xcodeproj/project.pbxproj \
  apps/TokenStats/TokenStats/App/TokenStatsApp.swift \
  apps/TokenStats/TokenStats/Tokens/ModelName.swift \
  apps/TokenStats/TokenStats/Tokens/TokenOdometerModel.swift \
  apps/TokenStats/TokenStats/Tokens/TranscriptChangeSource.swift \
  apps/TokenStats/TokenStats/Tokens/TokensTabView.swift
```

### I6 — Windows implementation remains byte-for-byte unchanged

```zsh
git diff --exit-code \
  a0290d59e21849f727976c42155833e744c8fe01 -- \
  apps/TokenStats.Windows
```

### I7 — Each milestone ends in exactly one named commit and preserves only the known unrelated untracked directory

Record `MILESTONE_START="$(git rev-parse HEAD)"` before changing a milestone. Run after its commit, substituting that recorded SHA and the milestone's prescribed subject:

```zsh
test "$(git rev-list --count <milestone-start>..HEAD)" = "1" &&
test "$(git log -1 --pretty=%s)" = "<prescribed-subject>" &&
test "$(git status --porcelain)" = "?? .claude/"
```

### I8 — Package commands and production surface remain unchanged

```zsh
git diff --exit-code \
  a0290d59e21849f727976c42155833e744c8fe01 -- \
  apps/TokenStats/package.json
```

## 4. Milestones

Tickets define work items; they do not create commits. For every milestone:

1. Record the milestone-start SHA before editing.
2. Complete its tickets and stage the entire intended milestone diff.
3. Pass the retired success criteria plus the pre-commit forms of I1–I6 and I8, including staged I3 and an explicit staged-scope review.
4. Create exactly the single named commit.
5. Pass the post-commit forms of I3–I8, including the I7 count, title, and worktree checks.

This two-phase gate is the full milestone gate; a post-commit invariant is never treated as a prerequisite for creating the commit it verifies.

### M0 — Freeze the execution contract

- Ticket: [#52 Adopt platform-local Token Odometer checkpoint vocabulary](https://github.com/zhangchi0104/agent-sessions/issues/52)
- Deliverables: the already-approved platform-neutral `CONTEXT.md` wording and this goal file.
- Retires: S1.
- Gate: S1, then the full pre/post-commit invariant protocol above.
- Commit: `docs(TokenStats): define macOS checkpoint execution goal`

### M1 — Make continuation restart-safe without enabling disk

- Ticket: [#53 Make transcript continuation restart-safe without disk persistence](https://github.com/zhangchi0104/agent-sessions/issues/53)
- Deliverables: durable/runtime state split, safe committed cursor, bounded oversized-line discard, read statistics, injected internal store and clock seams, and focused continuation tests.
- Retires: S2.
- Gate: S1–S2, then the full pre/post-commit invariant protocol above.
- Commit: `refactor(TokenStats): separate durable transcript continuation`

### M2 — Persist and resume the happy path

- Tickets:
  - [#54 Hydrate unchanged transcripts from native macOS checkpoints](https://github.com/zhangchi0104/agent-sessions/issues/54)
  - [#55 Resume appended Claude and Codex transcripts across restarts](https://github.com/zhangchi0104/agent-sessions/issues/55)
- Deliverables: store/schema/default path/key/checksum/privacy/atomic publication, unchanged-file hydration, exact append continuation, and provider-specific restart state.
- Retires: S3.
- Gate: S1–S3, then the full pre/post-commit invariant protocol above.
- Commit: `feat(TokenStats): persist macOS transcript checkpoints`

### M3 — Harden invalidation, I/O, and lifecycle behavior

- Tickets:
  - [#56 Cold-rebuild every invalid checkpoint or source identity](https://github.com/zhangchi0104/agent-sessions/issues/56)
  - [#57 Fail open across cache I/O and macOS lifecycle edges](https://github.com/zhangchi0104/agent-sessions/issues/57)
- Deliverables: strict table-driven validation, whole-state invalidation, source-mutation coverage, fault-injected atomic publication, stale-temp handling, transcript lifecycle coverage, and disk reuse after in-memory eviction.
- Retires: S4.
- Gate: S1–S4, then the full pre/post-commit invariant protocol above.
- Commit: `feat(TokenStats): harden checkpoint invalidation`

### M4 — Record the contract and close delivery

- Ticket: [#58 Record the macOS checkpoint contract and close delivery gates](https://github.com/zhangchi0104/agent-sessions/issues/58)
- Deliverables: ADR 0008, amendments to ADRs 0003 and 0007, aligned comments, complete verification evidence, and confirmation that no prototype hook ships.
- Retires: S5–S6.
- Gate: S1–S6, then the full pre/post-commit invariant protocol above.
- Commit: `docs(TokenStats): record macOS checkpoint contract`

## 5. Standing decision rules

1. New Swift files under the synchronized source and test groups are discovered automatically. Never edit `project.pbxproj` for this work.
2. Run repository commands from the root with `npm --prefix apps/TokenStats ...`. If the execution sandbox prevents Xcode from writing DerivedData, rerun the same command with the required host permission; do not redirect project outputs or weaken the test.
3. Keep one production seam from `TranscriptTokenReader` to the checkpoint store. Fault injection may be internal to that seam; do not add a second cross-module cache abstraction.
4. Preserve the sole production reader construction and existing model/lifecycle ownership. The reader may construct its default live store; tests inject isolated stores and clocks.
5. Treat persisted `sourceLengthAtCheckpoint` validation metadata separately from continuation cursors. Restore ordinary parsing from the safe committed complete-record position. While an oversized record is deliberately being discarded, a separately validated `discardedThroughBytes` cursor may resume that discard without representing committed aggregate state; clear it at the terminating newline.
6. Treat schema version, checksum, bounds, or source validation mismatch as a whole-entry miss. Do not add checkpoint migration in this delivery.
7. Cache read/write/delete failures are non-fatal. They cannot erase correct in-memory totals or destroy the last valid entry before a replacement is durable.
8. “Fingerprint bytes” are bounded source-validation reads. “Transcript-content bytes” are bytes submitted to continuation parsing. `jsonLinesSubmittedForDecoding` increments once per candidate JSON line, not once per decoder-internal attempt.
9. Inject time into reader/store tests. Do not move clock or time-zone ownership into the app model.
10. Encode provider model state through checkpoint DTOs. Do not modify `ModelName.swift`.
11. Production data lives below the macOS Caches directory; tests use temporary cache roots. Fixtures and persisted envelopes contain no real transcript data, raw path, partial content, credential, or raw response ID.
12. Use deterministic counters and structural equality for performance claims. Do not add wall-clock performance thresholds.
13. Make exactly one commit per milestone after its full gate passes. Individual tickets inside a milestone do not commit.

## 6. Stop conditions

Stop and return to the user before changing scope when any condition is met:

1. The pre-milestone full suite is red for a reason other than the two accepted actor-isolation warnings, or the observed baseline is no longer 119 tests in 17 suites before feature tests are added.
2. The initial worktree differs from the exact baseline in §8, or user-owned `.claude/` content would need to be read, modified, staged, or removed.
3. Correct implementation appears to require changing app construction, model/watch/UI files, `project.pbxproj`, Windows sources, or `package.json`.
4. An unchanged warm restore cannot reach zero transcript-content bytes and zero candidate JSON lines while validation remains bounded to an 8 KiB fingerprint.
5. Exact continuation appears to require persisting a raw transcript path, raw content, partial line, credential, raw response ID, or whole-file content hash.
6. Injected atomic-publication failures cannot preserve the previous valid checkpoint while keeping source-derived totals correct.
7. A focused-suite source guard succeeds but the Xcode log does not explicitly report that named suite passed; treat this as a zero-test or discovery failure, not success.
8. Before implementation, the count of production `TranscriptTokenReader` constructions is no longer exactly one.

## 7. Non-goals

- No Windows checkpoint behavior or schema change.
- No authoritative token history, database, cloud sync, or cross-device cache.
- No change to token-counting semantics, price calculation, UI, visible-window laziness, watchers, or the 48-hour in-memory eviction rule.
- No full transcript copy, raw path, raw response ID, credentials, partial line, or whole-file content hash in the checkpoint.
- No checkpoint migration framework; incompatible versions rebuild.
- No manual Xcode project membership change.
- No prototype package command or prototype source in production.
- No wall-clock benchmark gate.

## 8. Ground truth and execution baseline

- Branch: `feat/macos-tokens-storage`; frozen commit: `a0290d59e21849f727976c42155833e744c8fe01`; no upstream is configured.
- Exact worktree state after this goal file is created:

  ```text
   M apps/TokenStats/CONTEXT.md
  ?? .claude/
  ?? docs/goals/2026-07-30-macos-token-parse-checkpoints.md
  ```

- `apps/TokenStats/CONTEXT.md` is an approved, in-scope pre-existing edit and belongs to M0. `.claude/` is unrelated user content and must remain untouched and untracked.
- The active tracker is `zhangchi0104/agent-sessions`; the local `apps/TokenStats/docs/agents/issue-tracker.md` reference to the archived standalone repository is stale.
- Parent spec: [#51 Spec: persistent macOS Token Odometer parse checkpoints](https://github.com/zhangchi0104/agent-sessions/issues/51). Accepted checkpoint semantics are also recorded in the closed decision chain ending at [#48](https://github.com/zhangchi0104/agent-sessions/issues/48#issuecomment-5129964743).
- `TranscriptTokenReader.swift` is 450 lines at baseline and currently keeps continuation only in memory. There are 27 constructions: one production construction in `TokenStatsApp.swift` and 26 test constructions.
- The Xcode project has five `PBXFileSystemSynchronizedRootGroup` entries, so new files in the existing synchronized directories require no project-file edit.
- Local toolchain: Xcode 26.6 (`17F113`). CI uses macOS 15 with Xcode 26.
- `npm --prefix apps/TokenStats test` passes 119 tests in 17 suites at baseline. A direct `-only-testing:TokenStatsTests/CodexCountingTests` invocation proves focused Swift Testing suite selection works.
- `npm --prefix apps/TokenStats run build` produces a successful universal Release build at baseline.
- Two pre-existing actor-isolation warnings are accepted but must not increase: `CodexOAuthFlow.swift:65` and `UsageModel.swift:52`.
- ADR 0003 describes Tokens Today as an in-process estimate, and ADR 0007 records only the Windows local parse cache. Both currently say macOS is unchanged and require amendment in M4.
- Prototype evidence is preserved only on branch `prototype/macos-checkpoint-state` at `96b70c578f3ac5abd0f9cc8142279789103c041b`. It is not production code, must not be cherry-picked wholesale, and has no active worktree.
- Commit convention is `type(TokenStats): subject`. No co-author trailer is required by observed repository history.

## 9. Tracking and dependency graph

Parent spec: [#51](https://github.com/zhangchi0104/agent-sessions/issues/51), kept open and unchanged.

All implementation tickets carry `ready-for-agent` and are native sub-issues of #51:

| Ticket | Milestone | Native blocked by |
| --- | --- | --- |
| [#52 Adopt platform-local Token Odometer checkpoint vocabulary](https://github.com/zhangchi0104/agent-sessions/issues/52) | M0 | None |
| [#53 Make transcript continuation restart-safe without disk persistence](https://github.com/zhangchi0104/agent-sessions/issues/53) | M1 | #52 |
| [#54 Hydrate unchanged transcripts from native macOS checkpoints](https://github.com/zhangchi0104/agent-sessions/issues/54) | M2 | #53 |
| [#55 Resume appended Claude and Codex transcripts across restarts](https://github.com/zhangchi0104/agent-sessions/issues/55) | M2 | #53, #54 |
| [#56 Cold-rebuild every invalid checkpoint or source identity](https://github.com/zhangchi0104/agent-sessions/issues/56) | M3 | #54, #55 |
| [#57 Fail open across cache I/O and macOS lifecycle edges](https://github.com/zhangchi0104/agent-sessions/issues/57) | M3 | #54, #55, #56 |
| [#58 Record the macOS checkpoint contract and close delivery gates](https://github.com/zhangchi0104/agent-sessions/issues/58) | M4 | #56, #57 |

The native graph deliberately contains both cross-milestone and within-milestone edges. A later milestone cannot start early merely because one same-milestone ticket finished. Closing an implementation ticket does not authorize a commit until the milestone's final ticket and full gate are complete.
