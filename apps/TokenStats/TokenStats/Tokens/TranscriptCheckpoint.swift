//
//  TranscriptCheckpoint.swift
//  TokenStats
//
//  Restart-safe Token Odometer continuation vocabulary. This file deliberately
//  defines no disk implementation yet: M1 separates durable parser state from
//  process-only buffers and establishes the one storage boundary M2 will use.
//

import Foundation

/// The only reader-to-storage boundary. The reader owns checkpoint semantics
/// and encoding; a store only loads, atomically publishes, or removes one
/// opaque entry for a transcript.
nonisolated protocol TranscriptCheckpointStoring: Sendable {
    func loadCheckpoint(forTranscriptAt path: String) throws -> Data?
    func publishCheckpoint(_ data: Data, forTranscriptAt path: String) throws
    func removeCheckpoint(forTranscriptAt path: String) throws
}

/// Deterministic work counters for one transcript read.
nonisolated struct TranscriptReadStatistics: Equatable, Sendable {
    var checkpointLoads = 0
    var checkpointMisses = 0
    var checkpointInvalidations = 0
    var checkpointWrites = 0
    var fingerprintBytesRead: UInt64 = 0
    var transcriptContentBytesRead: UInt64 = 0
    var jsonLinesSubmittedForDecoding = 0

    mutating func add(_ other: TranscriptReadStatistics) {
        checkpointLoads += other.checkpointLoads
        checkpointMisses += other.checkpointMisses
        checkpointInvalidations += other.checkpointInvalidations
        checkpointWrites += other.checkpointWrites
        fingerprintBytesRead += other.fingerprintBytesRead
        transcriptContentBytesRead += other.transcriptContentBytesRead
        jsonLinesSubmittedForDecoding += other.jsonLinesSubmittedForDecoding
    }
}

/// Non-content framing facts exposed with a read result. Raw partial bytes are
/// intentionally absent: they are runtime-only and can never enter a checkpoint.
nonisolated struct TranscriptContinuationSnapshot: Equatable, Sendable {
    let safeCommittedBytes: UInt64
    let observedBytes: UInt64
    let bufferedPartialBytes: Int
    let isDiscardingOversizedLine: Bool
    let discardedThroughBytes: UInt64?
}

/// One transcript read as observed at the reader boundary.
nonisolated struct TranscriptReadResult: Equatable, Sendable {
    let usage: TokenUsage?
    let continuation: TranscriptContinuationSnapshot?
    let statistics: TranscriptReadStatistics
}

/// Parser state that is safe to restore in a new process. It contains aggregate
/// facts and validated cursors, never a raw path, response id, or source bytes.
nonisolated struct TranscriptDurableContinuation: Equatable, Sendable {
    var safeCommittedBytes: UInt64 = 0
    var discardedThroughBytes: UInt64?
    var isDiscardingOversizedLine = false
    var seenClaudeResponseHashes: Set<String> = []
    var usage = TokenUsage()
    var perDay: [TranscriptTokenReader.UsageKey: TokenUsage] = [:]
    var currentCodexModel: ModelName?
    var pendingByDay: [String: TokenUsage] = [:]
    var codexRunningTotal: TranscriptTokenReader.CodexRunningTotal?
}
