//
//  TranscriptCheckpointInvalidEnvelopeFixtures.swift
//  TokenStatsTests
//
//  Version-one envelope mutations used by the invalidation matrix. Keeping
//  these byte-level fixtures together makes the frozen schema easy to audit.
//

import CryptoKit
import Foundation
import Testing

enum InvalidEnvelopeState: String, CaseIterable {
    case schemaVersion
    case parserSemanticsVersion
    case timeZone
    case transcriptKey
    case checksum
    case malformedJSON
    case truncatedJSON
    case duplicateEnvelopeKey
    case unknownEnvelopeField
    case missingRequiredField
    case negativeCounter
    case overflowingAggregate
    case tokensWithoutResponses
    case zeroTokenBucketWithResponse
    case bucketExceedsAggregate
    case negativeCodexBaseline
    case overflowingCodexBaseline
    case invalidResponseHash
    case excessiveResponseHashes
    case excessiveDailyEntries
    case invalidLocalMonth
    case invalidLocalDay
    case overlongModel
    case unattributedDailyModel
    case unattributedCurrentModel
    case activeModelWithPendingUsage
    case safeCursorPastSource
    case discardCursorWithoutMode
    case discardModeWithoutCursor
    case discardCursorBeforeSafe
    case discardCursorPastSource
    case invalidSourceNanoseconds
    case sourceLengthBeyondOffsetRange
    case impossibleFingerprint
    case invalidFingerprintHash
    case invalidOldEndOffset
    case duplicateResponseHash
    case duplicateDailyKey
    case duplicatePendingDay

    func data(from original: Data) throws -> Data {
        switch self {
        case .malformedJSON:
            return Data(#"{"not":"json""#.utf8)
        case .truncatedJSON:
            return Data(original.prefix(original.count / 2))
        case .duplicateEnvelopeKey:
            let object = try envelopeObject(original)
            let version = (object["schemaVersion"] as? NSNumber)?.intValue ?? 1
            let text = try #require(String(data: original, encoding: .utf8))
            return Data("{\"schemaVersion\":\(version),\(text.dropFirst())".utf8)
        case .unknownEnvelopeField:
            return try mutateEnvelope(original) {
                $0["futureField"] = true
            }
        case .missingRequiredField:
            return try mutateEnvelope(original) {
                $0.removeValue(forKey: "entry")
            }
        case .checksum:
            return try mutateEnvelope(original, recomputeChecksum: false) {
                $0["checksum"] = String(repeating: "0", count: 64)
            }
        case .schemaVersion:
            return try mutateEnvelope(original) {
                $0["schemaVersion"] =
                    TranscriptCheckpointCodec.schemaVersion + 1
            }
        case .parserSemanticsVersion:
            return try mutateEnvelope(original) {
                $0["parserSemanticsVersion"] =
                    TranscriptCheckpointCodec.parserSemanticsVersion + 1
            }
        case .timeZone:
            return try mutateEnvelope(original) {
                $0["timeZoneIdentifier"] = "Invalid/Checkpoint-Time-Zone"
            }
        case .transcriptKey:
            return try mutateEnvelope(original) {
                $0["transcriptKey"] = String(repeating: "f", count: 64)
            }
        case .negativeCounter:
            return try mutateContinuation(original) {
                var usage = try dictionary($0["usage"])
                usage["inputTokens"] = -1
                $0["usage"] = usage
            }
        case .overflowingAggregate:
            return try mutateContinuation(original) {
                var usage = try dictionary($0["usage"])
                usage["inputTokens"] = NSNumber(value: Int.max)
                usage["outputTokens"] = 1
                $0["usage"] = usage
            }
        case .tokensWithoutResponses:
            return try mutateContinuation(original) {
                var usage = try dictionary($0["usage"])
                usage["responseCount"] = 0
                $0["usage"] = usage
            }
        case .zeroTokenBucketWithResponse:
            return try mutateContinuation(original) {
                var daily = try array($0["perDay"])
                var first = try dictionary(daily[0])
                first["usage"] = [
                    "inputTokens": 0,
                    "outputTokens": 0,
                    "cacheReadTokens": 0,
                    "responseCount": 1,
                ]
                daily[0] = first
                $0["perDay"] = daily
            }
        case .bucketExceedsAggregate:
            return try mutateContinuation(original) {
                let aggregate = try dictionary($0["usage"])
                let aggregateInput = try number(
                    aggregate["inputTokens"]
                ).intValue
                var daily = try array($0["perDay"])
                var first = try dictionary(daily[0])
                var usage = try dictionary(first["usage"])
                usage["inputTokens"] = aggregateInput + 1
                first["usage"] = usage
                daily[0] = first
                $0["perDay"] = daily
            }
        case .negativeCodexBaseline:
            return try mutateContinuation(original) {
                var baseline = try dictionary($0["codexRunningTotal"])
                baseline["directInput"] = -1
                $0["codexRunningTotal"] = baseline
            }
        case .overflowingCodexBaseline:
            return try mutateContinuation(original) {
                var baseline = try dictionary($0["codexRunningTotal"])
                baseline["directInput"] = NSNumber(value: Int.max)
                baseline["cacheRead"] = 1
                $0["codexRunningTotal"] = baseline
            }
        case .invalidResponseHash:
            return try mutateContinuation(original) {
                $0["seenClaudeResponseHashes"] = ["not-a-sha256"]
            }
        case .excessiveResponseHashes:
            return try mutateContinuation(original) {
                $0["seenClaudeResponseHashes"] = Array(
                    repeating: "",
                    count: TranscriptCheckpointCodec.maximumResponseHashes + 1
                )
            }
        case .excessiveDailyEntries:
            return try mutateContinuation(original) {
                $0["perDay"] = Array(
                    repeating: NSNull(),
                    count: TranscriptCheckpointCodec.maximumDailyEntries + 1
                )
            }
        case .invalidLocalMonth:
            return try mutateContinuation(original) {
                var daily = try array($0["perDay"])
                var first = try dictionary(daily[0])
                first["day"] = "2026-99-01"
                daily[0] = first
                $0["perDay"] = daily
            }
        case .invalidLocalDay:
            return try mutateContinuation(original) {
                var daily = try array($0["perDay"])
                var first = try dictionary(daily[0])
                first["day"] = "2026-02-29"
                daily[0] = first
                $0["perDay"] = daily
            }
        case .overlongModel:
            return try mutateContinuation(original) {
                var daily = try array($0["perDay"])
                var first = try dictionary(daily[0])
                var model = try dictionary(first["model"])
                model["name"] = String(repeating: "m", count: 1_025)
                first["model"] = model
                daily[0] = first
                $0["perDay"] = daily
            }
        case .unattributedDailyModel:
            return try mutateContinuation(original) {
                var daily = try array($0["perDay"])
                var first = try dictionary(daily[0])
                first["model"] = [
                    "kind": "unattributed",
                    "name": NSNull(),
                ]
                daily[0] = first
                $0["perDay"] = daily
            }
        case .unattributedCurrentModel:
            return try mutateContinuation(original) {
                $0["currentCodexModel"] = [
                    "kind": "unattributed",
                    "name": NSNull(),
                ]
            }
        case .activeModelWithPendingUsage:
            return try mutateContinuation(original) {
                $0["currentCodexModel"] = [
                    "kind": "named",
                    "name": "gpt-5.6-sol",
                ]
            }
        case .safeCursorPastSource:
            return try mutateEnvelope(original) { envelope in
                var entry = try dictionary(envelope["entry"])
                let source = try dictionary(entry["source"])
                let length = try number(
                    source["sourceLengthAtCheckpoint"]
                ).uint64Value
                var continuation = try dictionary(entry["continuation"])
                continuation["safeCommittedBytes"] = NSNumber(
                    value: length + 1
                )
                entry["continuation"] = continuation
                envelope["entry"] = entry
            }
        case .discardCursorWithoutMode:
            return try mutateContinuation(original) {
                $0["isDiscardingOversizedLine"] = false
                $0["discardedThroughBytes"] = 0
            }
        case .discardModeWithoutCursor:
            return try mutateContinuation(original) {
                $0["isDiscardingOversizedLine"] = true
                $0["discardedThroughBytes"] = NSNull()
            }
        case .discardCursorBeforeSafe:
            return try mutateContinuation(original) {
                let safe = try number(
                    $0["safeCommittedBytes"]
                ).uint64Value
                $0["isDiscardingOversizedLine"] = true
                $0["discardedThroughBytes"] = NSNumber(value: safe)
            }
        case .discardCursorPastSource:
            return try mutateEnvelope(original) { envelope in
                var entry = try dictionary(envelope["entry"])
                let source = try dictionary(entry["source"])
                let length = try number(
                    source["sourceLengthAtCheckpoint"]
                ).uint64Value
                var continuation = try dictionary(entry["continuation"])
                continuation["isDiscardingOversizedLine"] = true
                continuation["discardedThroughBytes"] = NSNumber(
                    value: length + 1
                )
                entry["continuation"] = continuation
                envelope["entry"] = entry
            }
        case .invalidSourceNanoseconds:
            return try mutateEnvelope(original) { envelope in
                var entry = try dictionary(envelope["entry"])
                var source = try dictionary(entry["source"])
                source["lastWriteNanoseconds"] = 1_000_000_000
                entry["source"] = source
                envelope["entry"] = entry
            }
        case .sourceLengthBeyondOffsetRange:
            return try mutateEnvelope(original) { envelope in
                var entry = try dictionary(envelope["entry"])
                var source = try dictionary(entry["source"])
                source["sourceLengthAtCheckpoint"] = NSNumber(
                    value: UInt64.max
                )
                entry["source"] = source
                envelope["entry"] = entry
            }
        case .impossibleFingerprint:
            return try mutateEnvelope(original) { envelope in
                var entry = try dictionary(envelope["entry"])
                var source = try dictionary(entry["source"])
                var prefix = try dictionary(source["prefixFingerprint"])
                prefix["length"] =
                    TranscriptCheckpointCodec.fingerprintWindowBytes + 1
                source["prefixFingerprint"] = prefix
                entry["source"] = source
                envelope["entry"] = entry
            }
        case .invalidFingerprintHash:
            return try mutateEnvelope(original) { envelope in
                var entry = try dictionary(envelope["entry"])
                var source = try dictionary(entry["source"])
                var prefix = try dictionary(source["prefixFingerprint"])
                prefix["sha256"] = String(repeating: "A", count: 64)
                source["prefixFingerprint"] = prefix
                entry["source"] = source
                envelope["entry"] = entry
            }
        case .invalidOldEndOffset:
            return try mutateEnvelope(original) { envelope in
                var entry = try dictionary(envelope["entry"])
                var source = try dictionary(entry["source"])
                var oldEnd = try dictionary(source["oldEndFingerprint"])
                oldEnd["offset"] = 1
                source["oldEndFingerprint"] = oldEnd
                entry["source"] = source
                envelope["entry"] = entry
            }
        case .duplicateResponseHash:
            return try mutateContinuation(original) {
                var hashes = try array($0["seenClaudeResponseHashes"])
                hashes.append(try #require(hashes.first))
                $0["seenClaudeResponseHashes"] = hashes
            }
        case .duplicateDailyKey:
            return try mutateContinuation(original) {
                var daily = try array($0["perDay"])
                daily.append(try #require(daily.first))
                $0["perDay"] = daily
            }
        case .duplicatePendingDay:
            return try mutateContinuation(original) {
                var pending = try array($0["pendingByDay"])
                pending.append(try #require(pending.first))
                $0["pendingByDay"] = pending
            }
        }
    }
}

func mutateContinuation(
    _ data: Data,
    mutation: (inout [String: Any]) throws -> Void
) throws -> Data {
    try mutateEnvelope(data) { envelope in
        var entry = try dictionary(envelope["entry"])
        var continuation = try dictionary(entry["continuation"])
        try mutation(&continuation)
        entry["continuation"] = continuation
        envelope["entry"] = entry
    }
}

func mutateEnvelope(
    _ data: Data,
    recomputeChecksum: Bool = true,
    mutation: (inout [String: Any]) throws -> Void
) throws -> Data {
    var envelope = try envelopeObject(data)
    try mutation(&envelope)
    if recomputeChecksum {
        var integrityPayload = envelope
        integrityPayload.removeValue(forKey: "checksum")
        let canonical = try JSONSerialization.data(
            withJSONObject: integrityPayload,
            options: [.sortedKeys]
        )
        envelope["checksum"] = checkpointSHA256(canonical)
    }
    return try JSONSerialization.data(
        withJSONObject: envelope,
        options: [.sortedKeys]
    )
}

func envelopeObject(_ data: Data) throws -> [String: Any] {
    try dictionary(JSONSerialization.jsonObject(with: data))
}

func dictionary(_ value: Any?) throws -> [String: Any] {
    try #require(value as? [String: Any])
}

func array(_ value: Any?) throws -> [Any] {
    try #require(value as? [Any])
}

func number(_ value: Any?) throws -> NSNumber {
    try #require(value as? NSNumber)
}

private func checkpointSHA256(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}
