# 7. Windows keeps a disposable local token parse cache

Date: 2026-07-29

Status: Accepted

Amends
[ADR-0003 — Tokens Today stays an in-process estimate](0003-tokens-today-stays-an-in-process-estimate.md)
and
[ADR-0006 — A native Windows companion](0006-native-windows-companion.md).

## Context

Windows keeps the Token Odometer's selected range current for both the flyout
and notification-area tooltip. A full startup reconciliation is still needed
because `FileSystemWatcher` events are hints, not a durable journal. Re-parsing
every unchanged transcript during that reconciliation makes a persisted 30-day
range unnecessarily expensive.

ADR-0003 and ADR-0006 deliberately kept all parse state in memory. The user has
now asked for a local cache, so this decision revises that one boundary. It
does not revise the estimate-grade nature of the Token Odometer or introduce a
second authority.

## Decision

The Windows app may persist versioned, per-file transcript parse checkpoints
under:

```text
%LocalAppData%\TokenStats\Cache\token-reader-v1
```

The cache is a disposable performance aid:

- Coding Agent transcript files remain the source of the Token Odometer.
- Usage endpoints remain the source of authoritative Usage Windows.
- The cache is not a database, historical ledger, IPC surface, service, or
  source of truth. Deleting it is always safe and causes a rebuild.
- The in-process transcript reader still owns parsing and publishes one
  reconciled in-memory result. No other consumer reads the cache directly.
- At this decision's date, macOS retained process-only parse state.

Each entry is named by a SHA-256 key over the normalized absolute transcript
path, which also captures the Coding Agent root and root-relative path without
revealing either one. Absolute transcript paths, which can expose user and
project names, are not used as cache filenames or stored as payload. An entry
carries:

- cache-schema and parser-semantics versions;
- the local time-zone identity used to form calendar-day buckets;
- source identity and validation data, including committed length, last-write
  metadata, and prefix/checkpoint-tail fingerprints;
- derived per-day, per-Model, and per-Token-Kind counters; and
- only the parser continuation metadata needed at a complete-line boundary,
  such as hashed deduplication identifiers, pending attribution, active Codex
  Model, and the Codex running-total baseline.

The envelope repeats the hashed transcript key and includes a SHA-256 integrity
checksum over its version, time-zone identity, key, and derived entry. The
checksum detects accidental, still-valid-JSON mutation; it is not an
authentication boundary against a local attacker.

A durable checkpoint advances only through the last complete JSONL line.
Incomplete trailing bytes are read again after restart. The cache never stores
transcript lines, prompts, responses, tool payloads, raw `partialLine` bytes,
OAuth tokens, authorization codes, or any Coding Agent credential. API prices
and final API-equivalent values are also recomputed rather than cached.

Every entry is written through a unique sibling temporary file, flushed, and
atomically replaced. Interrupted-write temporary files and malformed entries
are ignored. Cache reads enforce schema, entry-count, field-size, and numeric
bounds before allocating parser state.

## Reconciliation and invalidation

Startup and an explicit **Refresh all** perform a full reconciliation of both
transcript roots. They enumerate the files that currently exist, validate
matching cache entries, remove known entries whose source disappeared, and
publish only after the in-memory result is internally consistent. Because
entries deliberately contain no reversible path index, an entry for a file
deleted while the app was not running can remain as inert derived data; it
cannot contribute unless the authoritative transcript path exists and is
enumerated again. Deleting the cache directory removes such orphan entries.

While the resident app is running, debounced watcher events request a targeted
reconciliation of the affected path:

- An unchanged file with a valid entry hydrates from its checkpoint without
  re-parsing its completed prefix.
- An append resumes only when source identity and the cached prefix/tail still
  match and the file has not moved behind the committed offset.
- Truncation, replacement, an identity/fingerprint mismatch, schema or parser
  change, or local time-zone change discards the entry and parses from byte
  zero.
- Deletion or archival removes the entry and its contribution. A rename is
  treated conservatively as deletion of the old hashed key and discovery of a
  new file.
- Corrupt, oversized, or partially written entries are cache misses; they can
  never suppress transcript parsing or prevent tray startup.
- Watcher overflow, watcher error, transcript-root creation/replacement, or an
  event that cannot be mapped safely to one file schedules a full
  reconciliation.

Watcher notifications therefore improve freshness but never establish truth.
The startup/manual full reconciliation closes gaps caused by missed,
coalesced, or process-offline events.

## Consequences

- Unchanged historical files avoid repeated JSON parsing across Windows app
  launches; a cold cache, invalidation, or first launch still pays the full
  parse cost.
- The app still enumerates authoritative roots and validates file identity at
  startup. The cache optimizes parsing, not reconciliation.
- There is still one native process, no daemon, no shared SQLite token table,
  and no IPC protocol.
- Derived usage metadata now exists on disk. Hashed keys, complete-line-only
  checkpoints, bounded decoding, and omission of transcript content minimize
  that privacy and corruption surface.
- Identity validation follows the agents' append-only transcript contract:
  length/last-write metadata plus prefix and committed-tail fingerprints catch
  ordinary append, truncation, and replacement. It is not a whole-file
  integrity proof for an adversarial in-place rewrite that preserves metadata
  and both fingerprint windows.
- Parser or day-bucketing changes must intentionally advance the applicable
  version and rebuild the cache rather than attempt a lossy migration.

## Amendment — 2026-07-31

[ADR-0008](0008-macos-transcript-parse-checkpoints.md) supersedes the earlier
exclusion of macOS from disposable checkpoint persistence. macOS now follows
the same source-authority, bounded-validation, privacy, atomic-publication, and
fail-open safety contract through an independent Swift `Codable` format and
Tokens-tab-visible lifecycle.

This does not change the Windows cache path or schema, startup reconciliation,
resident `FileSystemWatcher`, targeted event handling, or any Windows source.
