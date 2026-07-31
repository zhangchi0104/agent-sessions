# 8. macOS restores disposable transcript parse checkpoints

Date: 2026-07-31

Status: Accepted

Amends
[ADR-0003 — Tokens Today stays an in-process estimate](0003-tokens-today-stays-an-in-process-estimate.md)
and complements
[ADR-0007 — Windows keeps a disposable local token parse cache](0007-local-token-parse-cache.md).

## Context

The macOS Token Odometer remains an in-process estimate derived from the
Claude Code and Codex transcript files that currently exist. Its FSEvents watch
is armed only while the Tokens tab is visible, but the first visible scan after
an application restart previously had to parse every relevant byte again.
For a large 30-day corpus, that repeated parsing is materially slower than the
enumeration and metadata checks needed to discover authoritative files.

A persistent aggregate, shared database, startup pre-warm, or always-on cache
scan would change the accepted ownership and lifecycle boundaries. A
disposable per-transcript checkpoint can avoid repeated parsing without making
the cache authoritative.

## Decision

The native macOS reader may persist one Swift `Codable` checkpoint per
transcript under:

```text
~/Library/Caches/dev.otakuma.TokenStats/token-reader-v1
```

Store construction is inert, and a cache miss does not create the directory.
Publication creates it lazily before writing. Each filename is the lowercase
SHA-256 of the normalized absolute transcript path followed by `.json`; neither
the filename nor payload stores the raw path.

The application composition root explicitly injects the native store. A
reader constructed without a store remains persistence-free, which keeps
tests and non-production callers independent of ambient XCTest detection.
The collection-level actor owns only enumeration, per-file state, statistics,
and eviction. One atomic per-file module owns stable source reads, checkpoint
restore/publication, bounded fingerprints, and cold retry; a separate JSONL
parser owns framing and Coding-Agent-specific continuation.

The current envelope has cache-schema version `1` and parser-semantics version
`1`. It repeats the transcript key and local time-zone identifier, contains one
coherent source-validation and parser-continuation entry, and carries a
SHA-256 checksum over the sorted-key integrity payload. Decode requires the
exact canonical bytes produced by this implementation. The checksum detects
accidental mutation; it is not authentication against a local attacker. A
parser or day-bucketing change must advance the applicable version and
cold-rebuild rather than migrate an old entry.

The macOS and Windows implementations share the same safety contract:
transcripts stay authoritative; checkpoints are disposable, bounded,
source-validated, privacy-minimized, atomically published, and fail open. They
do not share cache paths, schemas, serialized bytes, lifecycle triggers, or
implementation code.

## Safe continuation and source validation

`safeCommittedBytes` advances only at a newline boundary, after a complete
JSONL record has been processed or an oversized record has been deliberately
discarded. Any resulting aggregate and parser-specific continuation changes
commit as one unit. An ordinary incomplete trailing line remains process-only
and is reread from that safe cursor after restart.

An unfinished record larger than 16 MiB is deliberately discarded without
entering aggregate state. While waiting for its terminating newline, the
checkpoint may carry `discardedThroughBytes` and a discard-mode flag so the
same ignored bytes are not replayed after restart. This cursor is distinct from
`safeCommittedBytes`, represents no committed aggregate state, must match the
validated observed source end, and is cleared when the newline arrives.

The persisted source facts are the source length, last-write seconds and
nanoseconds, and SHA-256 fingerprints of bounded windows at the source prefix
and the old checkpoint end. Each window is at most 4 KiB. Runtime validation
additionally compares the opened descriptor with the path's current device,
inode, length, and modification time before and after fingerprinting and
parsing.

A stable append may resume after the safe cursor even though its length and
modification time have advanced. A source shrink, same-length
modification-time change, prefix or old-tail mismatch, or time-zone change
invalidates the whole checkpoint and rebuilds from byte zero. During an
attempt, divergence between the opened descriptor and the path currently
installed there, or another source mutation, discards that attempt and triggers
the stable cold-retry path.

## Bounded schema and privacy

Version 1 rejects an empty or non-canonical envelope, unknown or duplicate
state, invalid calendar keys, inconsistent aggregates, invalid hashes, invalid
offsets or counters, numeric overflow, and entries larger than 64 MiB before
hydrating parser state. It also limits:

- Claude response hashes to 1,000,000;
- per-day aggregate entries to 100,000;
- pending day entries to 100,000;
- each Model name to 1,024 Swift `Character` values;
- the time-zone identifier to 1,024 UTF-8 bytes; and
- each source fingerprint window to 4 KiB, or at most 8 KiB of validation reads
  per source.

The payload may contain derived per-day, per-Model, and per-Token-Kind
counters; SHA-256 response-deduplication identifiers; active Codex Model and
running-total baseline; and pending attribution required for exact
continuation. It never stores the raw path, transcript lines, prompts,
responses, tool payloads, raw partial-line bytes, raw response identifiers,
OAuth material, credentials, API prices, final API-equivalent values,
process-only work statistics, or the in-memory `lastAccessed` time.

## Reconciliation and work accounting

The cache optimizes parsing, not discovery. Every visible macOS observation
still enumerates the authoritative transcript roots, filters the files that
currently exist, and inspects source metadata. Only after that enumeration
finds and successfully opens an authoritative regular transcript does the
reader, when it has no in-memory state for that path, lazily try its per-file
checkpoint. New files are discovered by enumeration. A deleted file contributes
nothing; a rename is a new path and therefore a new key. An orphaned old entry
is inert because no cache-wide index is consulted or swept.

The read statistics distinguish parser work from the discovery work outside
their counters:

- filesystem enumeration and metadata filtering discover candidate files but
  are not represented by a `TranscriptReadStatistics` byte counter;
- `fingerprintBytesRead` counts only bounded validation-window bytes;
- `transcriptContentBytesRead` counts source bytes read into the parser from
  the current process cursor and excludes fingerprint reads. On disk restore,
  that cursor is `discardedThroughBytes` in discard mode and otherwise
  `safeCommittedBytes`; and
- `jsonLinesSubmittedForDecoding` counts each complete candidate JSONL record
  once per parse attempt after the cheap marker filter, independent of decoder
  fallbacks inside that submission. A cold retry is a new attempt and may count
  the same physical line again, but never commits the unstable attempt's state.

Consequently, a valid unchanged checkpoint can still require enumeration,
metadata checks, and bounded fingerprints while reporting zero transcript
content bytes and zero candidate JSON lines submitted for decoding.

Checkpoint activity follows the existing macOS visibility lifecycle.
Constructing the reader or store performs no checkpoint access or transcript
enumeration, and there is no startup pre-warm, startup reconciliation,
application-lifetime watcher, or polling timer. The existing FSEvents watch
remains limited to Tokens-tab visibility. Active in-memory parse states
untouched for 48 hours are evicted on a later visible scan; the disk checkpoint
is not subject to that memory window and may hydrate the next observation or a
new process.

## Atomic publication, invalidation, and failure

An entry is written to a unique sibling temporary file with user-only
permissions, fully written, synchronized, and closed before one same-directory
atomic rename replaces the destination. A create, open, write, synchronize,
close, or replace failure exposes no partial destination, preserves any
previously published entry, and never erases the already-correct in-memory
result. Abandoned temporary files are ignored rather than treated as entries.
This is process-visible namespace atomicity. The implementation does not
`fsync` the parent directory or request `F_FULLFSYNC`, so it makes no
power-loss durability guarantee for the renamed directory entry.

Loads reject symlinks, non-regular files, empty or oversized entries,
short/long reads, and files that change while being read. A missing entry is a
normal miss. Corrupt or incompatible data is a whole-entry invalidation.
Generic cache read or write failures mean the optimization is unavailable;
they are non-fatal and cannot suppress a cold parse. There is no per-entry
deletion seam: orphan entries are inert, and deleting the cache directory
remains the supported way to discard the optimization.

If the source itself changes during an attempt, no mixed state is committed.
The reader clears that attempt, reopens the authoritative path once, and cold
retries against the identity now installed there. If the source cannot produce
one stable snapshot, no derived state from either attempt is published.
Deleting the cache directory is always safe and causes the same totals to be
rebuilt from transcripts.

## Consequences

- With a valid checkpoint, unchanged completed transcript content is not
  reparsed across application launches or after the 48-hour in-memory eviction.
- Appends resume from the last safe complete-record boundary while preserving
  Claude deduplication and Codex attribution/baseline state.
- A checkpoint-backed first visible scan still pays authoritative enumeration,
  source metadata, and bounded fingerprint costs; checkpoints do not make the
  cache a file index or source of truth.
- The two bounded fingerprints are not a whole-file identity or integrity
  proof. Device and inode are runtime stability checks, not persisted identity;
  a replacement installed before validation can pass if its length/mtime
  relationship and both bounded windows satisfy the append-compatible checks.
- Derived usage metadata now exists on disk, but opaque path keys, user-only
  files, strict bounds, and omission of transcript content minimize the
  privacy and corruption surface.
- There is still one native application process, no daemon, no shared token
  table, no IPC surface, and no checkpoint scan while the Tokens tab is hidden.
