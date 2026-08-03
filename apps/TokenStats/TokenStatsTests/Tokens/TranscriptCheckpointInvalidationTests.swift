//
//  TranscriptCheckpointInvalidationTests.swift
//  TokenStatsTests
//
//  Invalid checkpoints and changed authoritative transcripts must discard the
//  whole restored state, cold rebuild, and publish one coherent replacement.
//

import Foundation
import Testing

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
            TranscriptUsageKey(
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
