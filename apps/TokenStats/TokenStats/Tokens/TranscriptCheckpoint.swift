//
//  TranscriptCheckpoint.swift
//  TokenStats
//
//  Restart-safe Token Odometer checkpoint vocabulary. Durable parser state,
//  source-validation metadata, and the encoded envelope stay independent of
//  process-only buffers and of the native store implementation.
//

import CryptoKit
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

/// The source facts a checkpoint's parser state was derived from. Fingerprints
/// are hashes of bounded windows, never transcript bytes.
nonisolated struct TranscriptSourceValidation: Codable, Equatable, Sendable {
    let sourceLengthAtCheckpoint: UInt64
    let lastWriteSeconds: Int64
    let lastWriteNanoseconds: Int64
    let prefixFingerprint: TranscriptFingerprint
    let oldEndFingerprint: TranscriptFingerprint
}

nonisolated struct TranscriptFingerprint: Codable, Equatable, Sendable {
    let offset: UInt64
    let length: Int
    let sha256: String
}

/// One coherent restorable unit. Source validation and parser continuation are
/// encoded together but kept conceptually separate.
nonisolated struct TranscriptCheckpoint: Equatable, Sendable {
    let source: TranscriptSourceValidation
    let continuation: TranscriptDurableContinuation
}

nonisolated enum TranscriptCheckpointCodingError: Error {
    case invalidPath
    case invalidEnvelope
}

/// One-way transcript identity shared by the envelope and its disk filename.
nonisolated enum TranscriptCheckpointKey {
    static func normalizedAbsolutePath(_ path: String) throws -> String {
        guard path.isEmpty == false else {
            throw TranscriptCheckpointCodingError.invalidPath
        }

        let expanded = (path as NSString).expandingTildeInPath
        let url: URL
        if expanded.hasPrefix("/") {
            url = URL(fileURLWithPath: expanded)
        } else {
            let workingDirectory = URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath,
                isDirectory: true
            )
            url = URL(fileURLWithPath: expanded, relativeTo: workingDirectory)
        }
        return url.standardizedFileURL.path
    }

    static func transcriptKey(for path: String) throws -> String {
        TranscriptHash.sha256Hex(Data(try normalizedAbsolutePath(path).utf8))
    }
}

/// Native Codable envelope and the explicit DTO conversion boundary around the
/// reader's domain state. Sorted arrays make the checksum encoding canonical.
nonisolated enum TranscriptCheckpointCodec {
    static let schemaVersion = 1
    static let parserSemanticsVersion = 1
    static let fingerprintWindowBytes = 4 * 1024

    static func encode(
        _ checkpoint: TranscriptCheckpoint,
        transcriptPath: String,
        timeZoneIdentifier: String
    ) throws -> Data {
        guard validate(source: checkpoint.source, continuation: checkpoint.continuation) else {
            throw TranscriptCheckpointCodingError.invalidEnvelope
        }

        let payload = IntegrityPayload(
            schemaVersion: schemaVersion,
            parserSemanticsVersion: parserSemanticsVersion,
            timeZoneIdentifier: timeZoneIdentifier,
            transcriptKey: try TranscriptCheckpointKey.transcriptKey(for: transcriptPath),
            entry: EntryDTO(checkpoint)
        )
        let checksum = TranscriptHash.sha256Hex(
            try canonicalEncoder().encode(payload)
        )
        return try canonicalEncoder().encode(Envelope(payload: payload, checksum: checksum))
    }

    static func decode(
        _ data: Data,
        transcriptPath: String,
        timeZoneIdentifier: String
    ) throws -> TranscriptCheckpoint {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        let expectedKey = try TranscriptCheckpointKey.transcriptKey(for: transcriptPath)
        guard envelope.schemaVersion == schemaVersion,
              envelope.parserSemanticsVersion == parserSemanticsVersion,
              envelope.timeZoneIdentifier == timeZoneIdentifier,
              envelope.transcriptKey == expectedKey,
              isSHA256Hex(envelope.checksum),
              envelope.checksum == TranscriptHash.sha256Hex(
                  try canonicalEncoder().encode(envelope.integrityPayload)
              )
        else {
            throw TranscriptCheckpointCodingError.invalidEnvelope
        }

        let checkpoint = try envelope.entry.checkpoint()
        guard validate(source: checkpoint.source, continuation: checkpoint.continuation) else {
            throw TranscriptCheckpointCodingError.invalidEnvelope
        }
        return checkpoint
    }

    private static func canonicalEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func validate(
        source: TranscriptSourceValidation,
        continuation: TranscriptDurableContinuation
    ) -> Bool {
        let expectedLength = Int(min(
            source.sourceLengthAtCheckpoint,
            UInt64(fingerprintWindowBytes)
        ))
        guard source.lastWriteNanoseconds >= 0,
              source.lastWriteNanoseconds < 1_000_000_000,
              source.prefixFingerprint.offset == 0,
              source.prefixFingerprint.length == expectedLength,
              source.oldEndFingerprint.length == expectedLength,
              source.oldEndFingerprint.offset
                  == source.sourceLengthAtCheckpoint - UInt64(expectedLength),
              isSHA256Hex(source.prefixFingerprint.sha256),
              isSHA256Hex(source.oldEndFingerprint.sha256),
              continuation.safeCommittedBytes <= source.sourceLengthAtCheckpoint,
              continuation.seenClaudeResponseHashes.count <= 1_000_000,
              continuation.perDay.count <= 100_000,
              continuation.pendingByDay.count <= 100_000,
              continuation.seenClaudeResponseHashes.allSatisfy(isSHA256Hex),
              isValid(continuation.usage),
              continuation.perDay.allSatisfy({
                  isValid(day: $0.key.day)
                      && isValid(model: $0.key.model)
                      && isValid($0.value)
              }),
              continuation.pendingByDay.allSatisfy({
                  isValid(day: $0.key) && isValid($0.value)
              }),
              continuation.currentCodexModel.map(isValid(model:)) ?? true,
              continuation.codexRunningTotal.map(isValid(_:)) ?? true
        else {
            return false
        }

        if continuation.isDiscardingOversizedLine {
            guard let discarded = continuation.discardedThroughBytes,
                  discarded >= continuation.safeCommittedBytes,
                  discarded <= source.sourceLengthAtCheckpoint
            else { return false }
        } else if continuation.discardedThroughBytes != nil {
            return false
        }
        return true
    }

    private static func isValid(_ usage: TokenUsage) -> Bool {
        usage.inputTokens >= 0
            && usage.outputTokens >= 0
            && usage.cacheCreationTokens >= 0
            && usage.cacheReadTokens >= 0
            && usage.responseCount >= 0
    }

    private static func isValid(_ total: TranscriptTokenReader.CodexRunningTotal) -> Bool {
        total.directInput >= 0 && total.cacheRead >= 0 && total.output >= 0
    }

    private static func isValid(day: String) -> Bool {
        guard day.utf8.count == 10 else { return false }
        for (index, byte) in day.utf8.enumerated() {
            if index == 4 || index == 7 {
                guard byte == 0x2D else { return false }
            } else {
                guard byte >= 0x30, byte <= 0x39 else { return false }
            }
        }
        return true
    }

    private static func isValid(model: ModelName) -> Bool {
        switch model {
        case .named(let name):
            return name.utf8.count <= 1_024
        case .unattributed:
            return true
        }
    }

    private static func isSHA256Hex(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66)
        }
    }

    private struct IntegrityPayload: Codable {
        let schemaVersion: Int
        let parserSemanticsVersion: Int
        let timeZoneIdentifier: String
        let transcriptKey: String
        let entry: EntryDTO
    }

    private struct Envelope: Codable {
        let schemaVersion: Int
        let parserSemanticsVersion: Int
        let timeZoneIdentifier: String
        let transcriptKey: String
        let entry: EntryDTO
        let checksum: String

        init(payload: IntegrityPayload, checksum: String) {
            schemaVersion = payload.schemaVersion
            parserSemanticsVersion = payload.parserSemanticsVersion
            timeZoneIdentifier = payload.timeZoneIdentifier
            transcriptKey = payload.transcriptKey
            entry = payload.entry
            self.checksum = checksum
        }

        var integrityPayload: IntegrityPayload {
            IntegrityPayload(
                schemaVersion: schemaVersion,
                parserSemanticsVersion: parserSemanticsVersion,
                timeZoneIdentifier: timeZoneIdentifier,
                transcriptKey: transcriptKey,
                entry: entry
            )
        }
    }

    private struct EntryDTO: Codable {
        let source: TranscriptSourceValidation
        let continuation: ContinuationDTO

        init(_ checkpoint: TranscriptCheckpoint) {
            source = checkpoint.source
            continuation = ContinuationDTO(checkpoint.continuation)
        }

        func checkpoint() throws -> TranscriptCheckpoint {
            TranscriptCheckpoint(
                source: source,
                continuation: try continuation.value()
            )
        }
    }

    private struct ContinuationDTO: Codable {
        let safeCommittedBytes: UInt64
        let discardedThroughBytes: UInt64?
        let isDiscardingOversizedLine: Bool
        let seenClaudeResponseHashes: [String]
        let usage: UsageDTO
        let perDay: [DailyUsageDTO]
        let currentCodexModel: ModelDTO?
        let pendingByDay: [PendingUsageDTO]
        let codexRunningTotal: CodexRunningTotalDTO?

        init(_ value: TranscriptDurableContinuation) {
            safeCommittedBytes = value.safeCommittedBytes
            discardedThroughBytes = value.discardedThroughBytes
            isDiscardingOversizedLine = value.isDiscardingOversizedLine
            seenClaudeResponseHashes = value.seenClaudeResponseHashes.sorted()
            usage = UsageDTO(value.usage)
            perDay = value.perDay.map {
                DailyUsageDTO(day: $0.key.day, model: ModelDTO($0.key.model), usage: UsageDTO($0.value))
            }.sorted {
                ($0.day, $0.model.sortKey) < ($1.day, $1.model.sortKey)
            }
            currentCodexModel = value.currentCodexModel.map(ModelDTO.init)
            pendingByDay = value.pendingByDay.map {
                PendingUsageDTO(day: $0.key, usage: UsageDTO($0.value))
            }.sorted { $0.day < $1.day }
            codexRunningTotal = value.codexRunningTotal.map(CodexRunningTotalDTO.init)
        }

        func value() throws -> TranscriptDurableContinuation {
            let hashes = Set(seenClaudeResponseHashes)
            guard hashes.count == seenClaudeResponseHashes.count else {
                throw TranscriptCheckpointCodingError.invalidEnvelope
            }

            var daily: [TranscriptTokenReader.UsageKey: TokenUsage] = [:]
            for item in perDay {
                let key = TranscriptTokenReader.UsageKey(
                    day: item.day,
                    model: try item.model.value()
                )
                guard daily.updateValue(item.usage.value, forKey: key) == nil else {
                    throw TranscriptCheckpointCodingError.invalidEnvelope
                }
            }

            var pending: [String: TokenUsage] = [:]
            for item in pendingByDay {
                guard pending.updateValue(item.usage.value, forKey: item.day) == nil else {
                    throw TranscriptCheckpointCodingError.invalidEnvelope
                }
            }

            var continuation = TranscriptDurableContinuation()
            continuation.safeCommittedBytes = safeCommittedBytes
            continuation.discardedThroughBytes = discardedThroughBytes
            continuation.isDiscardingOversizedLine = isDiscardingOversizedLine
            continuation.seenClaudeResponseHashes = hashes
            continuation.usage = usage.value
            continuation.perDay = daily
            continuation.currentCodexModel = try currentCodexModel?.value()
            continuation.pendingByDay = pending
            continuation.codexRunningTotal = codexRunningTotal?.value
            return continuation
        }
    }

    private struct UsageDTO: Codable {
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreationTokens: Int
        let cacheReadTokens: Int
        let responseCount: Int

        init(_ value: TokenUsage) {
            inputTokens = value.inputTokens
            outputTokens = value.outputTokens
            cacheCreationTokens = value.cacheCreationTokens
            cacheReadTokens = value.cacheReadTokens
            responseCount = value.responseCount
        }

        var value: TokenUsage {
            TokenUsage(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheCreationTokens: cacheCreationTokens,
                cacheReadTokens: cacheReadTokens,
                responseCount: responseCount
            )
        }
    }

    private struct ModelDTO: Codable {
        let kind: String
        let name: String?

        init(_ value: ModelName) {
            switch value {
            case .named(let name):
                kind = "named"
                self.name = name
            case .unattributed:
                kind = "unattributed"
                name = nil
            }
        }

        var sortKey: String { "\(kind):\(name ?? "")" }

        func value() throws -> ModelName {
            switch (kind, name) {
            case ("named", .some(let name)):
                return .named(name)
            case ("unattributed", .none):
                return .unattributed
            default:
                throw TranscriptCheckpointCodingError.invalidEnvelope
            }
        }
    }

    private struct DailyUsageDTO: Codable {
        let day: String
        let model: ModelDTO
        let usage: UsageDTO
    }

    private struct PendingUsageDTO: Codable {
        let day: String
        let usage: UsageDTO
    }

    private struct CodexRunningTotalDTO: Codable {
        let directInput: Int
        let cacheRead: Int
        let output: Int

        init(_ value: TranscriptTokenReader.CodexRunningTotal) {
            directInput = value.directInput
            cacheRead = value.cacheRead
            output = value.output
        }

        var value: TranscriptTokenReader.CodexRunningTotal {
            var total = TranscriptTokenReader.CodexRunningTotal()
            total.directInput = directInput
            total.cacheRead = cacheRead
            total.output = output
            return total
        }
    }
}

nonisolated enum TranscriptHash {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
