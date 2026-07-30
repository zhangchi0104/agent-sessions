//
//  TranscriptCheckpointInvalidationTests.swift
//  TokenStatsTests
//
//  Invalid checkpoints and changed authoritative transcripts must discard the
//  whole restored state, cold rebuild, and publish one coherent replacement.
//

import CryptoKit
import Foundation
import Testing
@testable import TokenStats

struct TranscriptCheckpointInvalidationTests {
    @Test func acceptedCollectionBoundsRemainCompatibleWithTheVersionOneContract() {
        #expect(TranscriptCheckpointCodec.maximumResponseHashes == 1_000_000)
        #expect(TranscriptCheckpointCodec.maximumDailyEntries == 100_000)
    }

    @Test func everyInvalidEnvelopeStateColdRebuildsAndTheReplacementThenHits() async throws {
        for invalidity in InvalidEnvelopeState.allCases {
            let fixture = try await InvalidationFixture.seeded(invalidity.rawValue)
            let original = try Data(contentsOf: fixture.checkpointURL)
            let invalid = try invalidity.data(from: original)
            try invalid.write(to: fixture.checkpointURL, options: .atomic)

            let expected = await TranscriptTokenReader(checkpointStore: nil)
                .readTranscript(at: fixture.transcriptURL.path)
            let rebuilt = await fixture.makeReader()
                .readTranscript(at: fixture.transcriptURL.path)

            #expect(
                rebuilt.usage == expected.usage,
                Comment(rawValue: "\(invalidity.rawValue) kept invalid aggregates")
            )
            #expect(
                rebuilt.continuation == expected.continuation,
                Comment(rawValue: "\(invalidity.rawValue) kept invalid continuation")
            )
            #expect(
                rebuilt.statistics.checkpointInvalidations == 1,
                Comment(rawValue: "\(invalidity.rawValue) was not invalidated")
            )
            #expect(
                rebuilt.statistics.transcriptContentBytesRead == fixture.sourceBytes,
                Comment(rawValue: "\(invalidity.rawValue) did not cold rebuild")
            )
            #expect(
                rebuilt.statistics.checkpointWrites == 1,
                Comment(rawValue: "\(invalidity.rawValue) did not publish a replacement")
            )

            let warm = await fixture.makeReader()
                .readTranscript(at: fixture.transcriptURL.path)
            #expect(
                warm.usage == expected.usage,
                Comment(rawValue: "\(invalidity.rawValue) replacement changed totals")
            )
            #expect(
                warm.statistics.checkpointLoads == 1,
                Comment(rawValue: "\(invalidity.rawValue) replacement did not load")
            )
            #expect(
                warm.statistics.transcriptContentBytesRead == 0,
                Comment(rawValue: "\(invalidity.rawValue) replacement was not a warm hit")
            )
            #expect(warm.statistics.jsonLinesSubmittedForDecoding == 0)
        }
    }

    @Test func anImpossibleGregorianDayIsRejectedEvenWhenEverythingElseIsValid() async throws {
        let fixture = try await InvalidationFixture.seeded(
            "impossible-gregorian-day",
            lines: [claudeUsageLine(id: "invalid-day", input: 11, output: 13)]
        )
        let original = try Data(contentsOf: fixture.checkpointURL)
        let decoded = try TranscriptCheckpointCodec.decode(
            original,
            transcriptPath: fixture.transcriptURL.path,
            timeZoneIdentifier: TimeZone.current.identifier
        )
        var continuation = decoded.continuation
        let existing = try #require(continuation.perDay.first)
        continuation.perDay.removeValue(forKey: existing.key)
        continuation.perDay[
            TranscriptTokenReader.UsageKey(
                day: "2026-02-29",
                model: existing.key.model
            )
        ] = existing.value
        let invalid = TranscriptCheckpoint(
            source: decoded.source,
            continuation: continuation
        )

        #expect(throws: (any Error).self) {
            _ = try TranscriptCheckpointCodec.encode(
                invalid,
                transcriptPath: fixture.transcriptURL.path,
                timeZoneIdentifier: TimeZone.current.identifier
            )
        }
    }

    @Test func semanticMutationFixturePreservesCanonicalEncoding() async throws {
        let fixture = try await InvalidationFixture.seeded(
            "canonical-mutation",
            lines: [claudeUsageLine(id: "canonical", input: 11, output: 13)]
        )
        let original = try Data(contentsOf: fixture.checkpointURL)
        let roundTripped = try mutateEnvelope(original) { _ in }

        _ = try TranscriptCheckpointCodec.decode(
            roundTripped,
            transcriptPath: fixture.transcriptURL.path,
            timeZoneIdentifier: TimeZone.current.identifier
        )
    }

    @Test func anOversizedCheckpointIsRejectedBeforeDecodeAndReplaced() async throws {
        let fixture = try await InvalidationFixture.seeded("oversized-entry")
        let handle = try FileHandle(forWritingTo: fixture.checkpointURL)
        try handle.truncate(atOffset: UInt64(TranscriptCheckpointStore.maximumEntryBytes + 1))
        try handle.close()

        let rebuilt = await fixture.makeReader()
            .readTranscript(at: fixture.transcriptURL.path)

        #expect(rebuilt.usage?.totalTokens == 126)
        #expect(rebuilt.statistics.checkpointInvalidations == 1)
        #expect(rebuilt.statistics.transcriptContentBytesRead == fixture.sourceBytes)
        #expect(rebuilt.statistics.checkpointWrites == 1)
        #expect(
            try Data(contentsOf: fixture.checkpointURL).count
                < TranscriptCheckpointStore.maximumEntryBytes
        )
    }

    @Test func truncationReplacementAndSameSizeSameMtimeRewriteColdRebuild() async throws {
        for rewrite in SourceRewrite.allCases {
            let fixture = try await InvalidationFixture.seeded(
                "source-\(rewrite.rawValue)",
                lines: rewrite.originalLines
            )
            try rewrite.apply(to: fixture.transcriptURL)
            try await assertColdRebuildThenWarmHit(fixture, label: rewrite.rawValue)
        }
    }

    @Test func prefixAndPreviousEndMutationInvalidateAnOtherwiseValidAppend() async throws {
        for mutation in FingerprintMutation.allCases {
            let leadingNoise = #"{"noise":"\#(String(repeating: "a", count: 5_000))"}"#
            let trailingNoise = #"{"noise":"\#(String(repeating: "z", count: 5_000))"}"#
            let fixture = try await InvalidationFixture.seeded(
                "fingerprint-\(mutation.rawValue)",
                lines: [
                    leadingNoise,
                    claudeUsageLine(id: "fingerprint-old", input: 17, output: 19),
                    trailingNoise,
                ]
            )

            let sourceSize = try fileSize(fixture.transcriptURL)
            let offset: UInt64 = mutation == .prefix ? 20 : sourceSize - 20
            try overwriteByte(0x62, at: offset, in: fixture.transcriptURL)
            let appended = claudeUsageLine(id: "fingerprint-new", input: 23, output: 29)
            try appendLines([appended], to: fixture.transcriptURL)

            try await assertColdRebuildThenWarmHit(fixture, label: mutation.rawValue)
        }
    }

    @Test func aCheckpointCopiedToAnotherTranscriptIdentityCannotContribute() async throws {
        let first = try await InvalidationFixture.seeded("source-key-first")
        let secondRoot = try TempTranscripts("source-key-second")
        let secondName = "other-session.jsonl"
        let secondURL = secondRoot.url.appendingPathComponent(secondName)
        try secondRoot.write(secondName, [
            claudeUsageLine(id: "other-source", input: 31, output: 37),
        ])
        let secondStore = TranscriptCheckpointStore(cacheRoot: first.cacheRoot)
        let secondCheckpoint = try secondStore.checkpointURL(
            forTranscriptAt: secondURL.path
        )
        try Data(contentsOf: first.checkpointURL)
            .write(to: secondCheckpoint, options: .atomic)

        let result = await TranscriptTokenReader(
            checkpointStore: secondStore,
            now: Date.init,
            timeZone: .current
        ).readTranscript(at: secondURL.path)
        let secondSourceBytes = try fileSize(secondURL)

        #expect(result.usage?.totalTokens == 68)
        #expect(result.usage?.responseCount == 1)
        #expect(result.statistics.checkpointInvalidations == 1)
        #expect(result.statistics.transcriptContentBytesRead == secondSourceBytes)
        #expect(result.statistics.checkpointWrites == 1)

        let warm = await TranscriptTokenReader(
            checkpointStore: secondStore,
            now: Date.init,
            timeZone: .current
        ).readTranscript(at: secondURL.path)
        #expect(warm.statistics.checkpointLoads == 1)
        #expect(warm.statistics.transcriptContentBytesRead == 0)
    }

    @Test func aTimeZoneChangeRebuildsEveryDayBucketAsOneUnit() async throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let fixture = try await InvalidationFixture.seeded(
            "timezone",
            timeZone: utc
        )

        let rebuilt = await fixture.makeReader(timeZone: losAngeles)
            .readTranscript(at: fixture.transcriptURL.path)

        #expect(rebuilt.usage?.totalTokens == 126)
        #expect(rebuilt.statistics.checkpointInvalidations == 1)
        #expect(rebuilt.statistics.transcriptContentBytesRead == fixture.sourceBytes)
        #expect(rebuilt.statistics.checkpointWrites == 1)

        let warm = await fixture.makeReader(timeZone: losAngeles)
            .readTranscript(at: fixture.transcriptURL.path)
        #expect(warm.usage == rebuilt.usage)
        #expect(warm.statistics.checkpointLoads == 1)
        #expect(warm.statistics.transcriptContentBytesRead == 0)
    }

    @Test func aSourceMutationDuringValidationNeverCombinesTwoVersions() async throws {
        let old = claudeUsageLine(id: "validation-race", input: 10, output: 20)
        let replacement = claudeUsageLine(id: "validation-race", input: 90, output: 80)
        #expect(old.utf8.count == replacement.utf8.count)
        let fixture = try await InvalidationFixture.seeded(
            "validation-race",
            lines: [old]
        )
        let mutatingStore = MutatingLoadStore(
            base: TranscriptCheckpointStore(cacheRoot: fixture.cacheRoot)
        ) {
            try Data((replacement + "\n").utf8)
                .write(to: fixture.transcriptURL, options: .atomic)
        }

        let raced = await TranscriptTokenReader(
            checkpointStore: mutatingStore,
            now: Date.init,
            timeZone: .current
        ).readTranscript(at: fixture.transcriptURL.path)
        let racedSourceBytes = try fileSize(fixture.transcriptURL)

        #expect(raced.usage?.totalTokens == 170)
        #expect(raced.usage?.responseCount == 1)
        #expect(raced.statistics.checkpointInvalidations == 1)
        #expect(raced.statistics.transcriptContentBytesRead == racedSourceBytes)
        #expect(raced.statistics.checkpointWrites == 1)

        let warm = await fixture.makeReader()
            .readTranscript(at: fixture.transcriptURL.path)
        #expect(warm.usage == raced.usage)
        #expect(warm.statistics.checkpointLoads == 1)
        #expect(warm.statistics.transcriptContentBytesRead == 0)
    }

    @Test func anAppendThatWouldOverflowRestoredTotalsColdRebuildsInstead() async throws {
        let fixture = try await InvalidationFixture.seeded(
            "append-overflow",
            lines: [
                claudeUsageLine(id: "before-overflow", input: 10),
            ]
        )
        let original = try Data(contentsOf: fixture.checkpointURL)
        let nearLimit = try mutateContinuation(original) { continuation in
            let usage: [String: Any] = [
                "inputTokens": NSNumber(value: Int.max),
                "outputTokens": 0,
                "cacheWriteTokens": 0,
                "cacheReadTokens": 0,
                "responseCount": 1,
            ]
            continuation["usage"] = usage
            var daily = try array(continuation["perDay"])
            var first = try dictionary(daily[0])
            first["usage"] = usage
            daily[0] = first
            continuation["perDay"] = daily
        }
        try nearLimit.write(to: fixture.checkpointURL, options: .atomic)
        let appended = claudeUsageLine(id: "after-overflow", input: 1)
        try appendLines([appended], to: fixture.transcriptURL)

        let rebuilt = await fixture.makeReader()
            .readTranscript(at: fixture.transcriptURL.path)

        #expect(rebuilt.usage?.totalTokens == 11)
        #expect(rebuilt.usage?.responseCount == 2)
        #expect(rebuilt.statistics.checkpointInvalidations == 1)
        #expect(rebuilt.statistics.checkpointWrites == 1)

        let warm = await fixture.makeReader()
            .readTranscript(at: fixture.transcriptURL.path)
        #expect(warm.usage == rebuilt.usage)
        #expect(warm.statistics.checkpointLoads == 1)
        #expect(warm.statistics.transcriptContentBytesRead == 0)
    }
}

private struct InvalidationFixture {
    let transcriptURL: URL
    let cacheRoot: URL
    let checkpointURL: URL
    let sourceBytes: UInt64

    static func seeded(
        _ label: String,
        lines: [String] = [
            claudeUsageLine(
                id: "checkpoint-invalid",
                input: 11,
                output: 13,
                cacheWrite: 17,
                cacheRead: 19
            ),
            codexTokenCountLine(totalInput: 41, totalCached: 7, totalOutput: 25),
        ],
        timeZone: TimeZone = .current
    ) async throws -> InvalidationFixture {
        let root = try TempTranscripts("invalidation-\(label)")
        let name = "session.jsonl"
        let transcriptURL = root.url.appendingPathComponent(name)
        try root.write(name, lines)
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalidation-cache-\(label)-\(UUID().uuidString)")
        let store = TranscriptCheckpointStore(cacheRoot: cacheRoot)
        let seeded = await TranscriptTokenReader(
            checkpointStore: store,
            now: Date.init,
            timeZone: timeZone
        ).readTranscript(at: transcriptURL.path)
        #expect(seeded.statistics.checkpointWrites == 1)
        return InvalidationFixture(
            transcriptURL: transcriptURL,
            cacheRoot: cacheRoot,
            checkpointURL: try store.checkpointURL(forTranscriptAt: transcriptURL.path),
            sourceBytes: try fileSize(transcriptURL)
        )
    }

    func makeReader(timeZone: TimeZone = .current) -> TranscriptTokenReader {
        TranscriptTokenReader(
            checkpointStore: TranscriptCheckpointStore(cacheRoot: cacheRoot),
            now: Date.init,
            timeZone: timeZone
        )
    }
}

private enum InvalidEnvelopeState: String, CaseIterable {
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
                $0["schemaVersion"] = TranscriptCheckpointCodec.schemaVersion + 1
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
                    "cacheWriteTokens": 0,
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
                let length = try number(source["sourceLengthAtCheckpoint"]).uint64Value
                var continuation = try dictionary(entry["continuation"])
                continuation["safeCommittedBytes"] = NSNumber(value: length + 1)
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
                let safe = try number($0["safeCommittedBytes"]).uint64Value
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
                prefix["length"] = TranscriptCheckpointCodec.fingerprintWindowBytes + 1
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

private enum SourceRewrite: String, CaseIterable {
    case truncation
    case replacement
    case sameSizeSameMtime
    case modificationTimeOnly

    var originalLines: [String] {
        switch self {
        case .truncation:
            [
                claudeUsageLine(id: "truncate-one", input: 100, output: 20),
                claudeUsageLine(id: "truncate-two", input: 30, output: 4),
            ]
        case .replacement:
            [claudeUsageLine(id: "replace-old", input: 10, output: 20)]
        case .sameSizeSameMtime:
            [claudeUsageLine(id: "same-a", input: 111, output: 222)]
        case .modificationTimeOnly:
            [claudeUsageLine(id: "mtime", input: 17, output: 19)]
        }
    }

    func apply(to url: URL) throws {
        switch self {
        case .truncation:
            try writeLines(
                [claudeUsageLine(id: "short", input: 7, output: 5)],
                to: url
            )
        case .replacement:
            try writeLines([
                claudeUsageLine(id: "replace-new-one", input: 31, output: 37),
                claudeUsageLine(id: "replace-new-two", input: 41, output: 43),
            ], to: url)
        case .sameSizeSameMtime:
            let replacement = claudeUsageLine(id: "same-b", input: 333, output: 444)
            let originalSize = try fileSize(url)
            let replacementData = Data((replacement + "\n").utf8)
            #expect(UInt64(replacementData.count) == originalSize)
            try replacePreservingTimestamps(replacementData, at: url)
        case .modificationTimeOnly:
            let attributes = try FileManager.default.attributesOfItem(
                atPath: url.path
            )
            let modificationDate = try #require(
                attributes[.modificationDate] as? Date
            )
            try FileManager.default.setAttributes(
                [.modificationDate: modificationDate.addingTimeInterval(10)],
                ofItemAtPath: url.path
            )
        }
    }
}

private enum FingerprintMutation: String, CaseIterable {
    case prefix
    case oldTail
}

private final class MutatingLoadStore: TranscriptCheckpointStoring, @unchecked Sendable {
    private let base: TranscriptCheckpointStore
    private let mutation: @Sendable () throws -> Void
    private let lock = NSLock()
    private var hasMutated = false

    init(
        base: TranscriptCheckpointStore,
        mutation: @escaping @Sendable () throws -> Void
    ) {
        self.base = base
        self.mutation = mutation
    }

    func loadCheckpoint(forTranscriptAt path: String) throws -> Data? {
        let data = try base.loadCheckpoint(forTranscriptAt: path)
        let shouldMutate = lock.withLock {
            guard hasMutated == false else { return false }
            hasMutated = true
            return true
        }
        if shouldMutate { try mutation() }
        return data
    }

    func publishCheckpoint(_ data: Data, forTranscriptAt path: String) throws {
        try base.publishCheckpoint(data, forTranscriptAt: path)
    }

    func removeCheckpoint(forTranscriptAt path: String) throws {
        try base.removeCheckpoint(forTranscriptAt: path)
    }
}

private func assertColdRebuildThenWarmHit(
    _ fixture: InvalidationFixture,
    label: String
) async throws {
    let expected = await TranscriptTokenReader(checkpointStore: nil)
        .readTranscript(at: fixture.transcriptURL.path)
    let rebuilt = await fixture.makeReader()
        .readTranscript(at: fixture.transcriptURL.path)
    let rebuiltSourceBytes = try fileSize(fixture.transcriptURL)
    #expect(rebuilt.usage == expected.usage, Comment(rawValue: "\(label) totals"))
    #expect(rebuilt.continuation == expected.continuation)
    #expect(rebuilt.statistics.checkpointInvalidations == 1)
    #expect(rebuilt.statistics.transcriptContentBytesRead == rebuiltSourceBytes)
    #expect(rebuilt.statistics.checkpointWrites == 1)

    let warm = await fixture.makeReader()
        .readTranscript(at: fixture.transcriptURL.path)
    #expect(warm.usage == expected.usage)
    #expect(warm.statistics.checkpointLoads == 1)
    #expect(warm.statistics.transcriptContentBytesRead == 0)
    #expect(warm.statistics.jsonLinesSubmittedForDecoding == 0)
}

private func mutateContinuation(
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

private func mutateEnvelope(
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
    return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
}

private func envelopeObject(_ data: Data) throws -> [String: Any] {
    try dictionary(JSONSerialization.jsonObject(with: data))
}

private func dictionary(_ value: Any?) throws -> [String: Any] {
    try #require(value as? [String: Any])
}

private func array(_ value: Any?) throws -> [Any] {
    try #require(value as? [Any])
}

private func number(_ value: Any?) throws -> NSNumber {
    try #require(value as? NSNumber)
}

private func checkpointSHA256(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

private func fileSize(_ url: URL) throws -> UInt64 {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var status = stat()
    guard fstat(handle.fileDescriptor, &status) == 0, status.st_size >= 0 else {
        throw POSIXError(.EIO)
    }
    return UInt64(status.st_size)
}

private func writeLines(_ lines: [String], to url: URL) throws {
    try Data((lines.joined(separator: "\n") + "\n").utf8)
        .write(to: url, options: .atomic)
}

private func appendLines(_ lines: [String], to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func overwriteByte(_ byte: UInt8, at offset: UInt64, in url: URL) throws {
    let handle = try FileHandle(forUpdating: url)
    defer { try? handle.close() }
    try handle.seek(toOffset: offset)
    try handle.write(contentsOf: Data([byte]))
    try handle.synchronize()
}

private func replacePreservingTimestamps(_ data: Data, at url: URL) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let modificationDate = try #require(
        attributes[.modificationDate] as? Date
    )
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes(
        [.modificationDate: modificationDate],
        ofItemAtPath: url.path
    )
}
