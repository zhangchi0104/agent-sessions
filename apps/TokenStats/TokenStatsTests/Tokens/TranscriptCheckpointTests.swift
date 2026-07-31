//
//  TranscriptCheckpointTests.swift
//  TokenStatsTests
//
//  Restart behavior at the TranscriptTokenReader boundary. Every parse uses a
//  real temporary JSONL source and every restart uses a new native disk store;
//  only the platform cache root is redirected into a temporary directory.
//

import Foundation
import Testing
@testable import TokenStats

struct TranscriptCheckpointTests {
    @Test func nativeStoreUsesTheVersionedPlatformCacheAndConstructionIsLazy() throws {
        let expectedRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches", isDirectory: true)
            .appendingPathComponent("dev.otakuma.TokenStats", isDirectory: true)
            .appendingPathComponent("token-reader-v1", isDirectory: true)
        #expect(
            TranscriptCheckpointStore.defaultCacheRoot.standardizedFileURL
                == expectedRoot.standardizedFileURL
        )

        let isolatedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkpoint-lazy-\(UUID().uuidString)")
            .appendingPathComponent("token-reader-v1", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: isolatedRoot.path) == false)
        _ = TranscriptCheckpointStore(cacheRoot: isolatedRoot)
        #expect(FileManager.default.fileExists(atPath: isolatedRoot.path) == false)
    }

    @Test func aFreshReaderHydratesAnUnchangedCompletedTranscriptWithoutParsingItAgain() async throws {
        let root = try TempTranscripts("checkpoint-hydrate")
        let checkpoints = TempCheckpointDirectory("checkpoint-hydrate")
        let name = "project/session.jsonl"
        let file = root.url.appendingPathComponent(name)
        let lines = [
            claudeUsageLine(
                id: "hydrate-one",
                input: 11,
                output: 13,
                cacheWrite: 17,
                cacheRead: 19
            ),
            claudeUsageLine(id: "hydrate-two", input: 23, output: 29),
        ]
        try root.write(name, lines)

        let coldReader = makeReader(checkpoints)
        let cold = await coldReader.readTranscript(at: file.path)

        #expect(cold.statistics.checkpointWrites == 1)
        #expect(cold.statistics.transcriptContentBytesRead == encodedBytes(lines))
        #expect(cold.usage?.responseCount == 2)

        let freshReader = makeReader(checkpoints)
        let warm = await freshReader.readTranscript(at: file.path)

        #expect(warm.usage == cold.usage)
        #expect(warm.continuation == cold.continuation)
        #expect(warm.statistics.checkpointLoads == 1)
        #expect(warm.statistics.checkpointMisses == 0)
        #expect(warm.statistics.fingerprintBytesRead > 0)
        #expect(warm.statistics.fingerprintBytesRead <= 8 * 1024)
        #expect(warm.statistics.transcriptContentBytesRead == 0)
        #expect(warm.statistics.jsonLinesSubmittedForDecoding == 0)
    }

    @Test func anAppendResumesAtTheExactCommittedBoundary() async throws {
        let root = try TempTranscripts("checkpoint-append")
        let checkpoints = TempCheckpointDirectory("checkpoint-append")
        let name = "session.jsonl"
        let file = root.url.appendingPathComponent(name)
        let first = claudeUsageLine(id: "append-first", input: 10, output: 20)
        try root.write(name, [first])

        let cold = await makeReader(checkpoints).readTranscript(at: file.path)
        let firstBoundary = encodedBytes([first])
        #expect(cold.continuation?.safeCommittedBytes == firstBoundary)

        let appended = claudeUsageLine(
            id: "append-second",
            input: 3,
            output: 5,
            cacheWrite: 7,
            cacheRead: 11
        )
        try root.append(name, [appended])

        let resumed = await makeReader(checkpoints).readTranscript(at: file.path)
        let appendedBytes = encodedBytes([appended])

        #expect(resumed.usage?.inputTokens == 13)
        #expect(resumed.usage?.outputTokens == 25)
        #expect(resumed.usage?.cacheCreationTokens == 7)
        #expect(resumed.usage?.cacheReadTokens == 11)
        #expect(resumed.usage?.responseCount == 2)
        #expect(resumed.continuation?.safeCommittedBytes == firstBoundary + appendedBytes)
        #expect(resumed.continuation?.observedBytes == firstBoundary + appendedBytes)
        #expect(resumed.statistics.checkpointLoads == 1)
        #expect(resumed.statistics.transcriptContentBytesRead == appendedBytes)
        #expect(resumed.statistics.jsonLinesSubmittedForDecoding == 1)
        #expect(resumed.statistics.fingerprintBytesRead <= 8 * 1024)
    }

    @Test func claudeResponseDeduplicationSurvivesAReaderRestart() async throws {
        let root = try TempTranscripts("checkpoint-claude-dedup")
        let checkpoints = TempCheckpointDirectory("checkpoint-claude-dedup")
        let name = "session.jsonl"
        let file = root.url.appendingPathComponent(name)
        let responseID = "same-response-across-restart"
        let first = claudeUsageLine(id: responseID, input: 100, output: 50)
        try root.write(name, [first])
        _ = await makeReader(checkpoints).readTranscript(at: file.path)

        let repeated = claudeUsageLine(
            id: responseID,
            input: 9_999,
            output: 8_888,
            cacheWrite: 7_777,
            cacheRead: 6_666
        )
        try root.append(name, [repeated])

        let resumed = await makeReader(checkpoints).readTranscript(at: file.path)

        #expect(resumed.usage?.inputTokens == 100)
        #expect(resumed.usage?.outputTokens == 50)
        #expect(resumed.usage?.cacheCreationTokens == 0)
        #expect(resumed.usage?.cacheReadTokens == 0)
        #expect(resumed.usage?.responseCount == 1)
        #expect(resumed.statistics.transcriptContentBytesRead == encodedBytes([repeated]))
        #expect(resumed.statistics.jsonLinesSubmittedForDecoding == 1)
    }

    @Test func codexPendingAttributionModelAndRunningBaselineAllSurviveRestarts() async throws {
        let root = try TempTranscripts("checkpoint-codex")
        let checkpoints = TempCheckpointDirectory("checkpoint-codex")
        let name = "2026/07/rollout.jsonl"
        let file = root.url.appendingPathComponent(name)
        let opening = codexTokenCountLine(
            totalInput: 1_000,
            totalCached: 400,
            totalOutput: 100
        )
        try root.write(name, [opening])

        let initial = await makeReader(checkpoints).readTranscript(at: file.path)
        #expect(initial.usage?.totalTokens == 1_100)

        let model = codexTurnContextLine(model: "gpt-5.6-sol")
        let second = codexTokenCountLine(
            totalInput: 1_500,
            totalCached: 600,
            totalOutput: 250,
            lastInput: 500,
            lastCached: 200,
            lastOutput: 150
        )
        try root.append(name, [model, second])

        let afterPendingRestart = makeReader(checkpoints)
        let attributed = await afterPendingRestart.readTranscript(at: file.path)
        let attributedByModel = await afterPendingRestart.breakdown(
            underTranscriptRoot: root.path,
            range: .today,
            now: Date()
        )

        #expect(attributed.usage?.totalTokens == 1_750)
        #expect(attributed.statistics.transcriptContentBytesRead == encodedBytes([model, second]))
        #expect(attributedByModel[.named("gpt-5.6-sol")]?.totalTokens == 1_750)
        #expect(attributedByModel[.unattributed] == nil)

        let third = codexTokenCountLine(
            totalInput: 1_800,
            totalCached: 700,
            totalOutput: 300,
            lastInput: 300,
            lastCached: 100,
            lastOutput: 50
        )
        try root.append(name, [third])

        let afterModelRestart = makeReader(checkpoints)
        let continued = await afterModelRestart.readTranscript(at: file.path)
        let continuedByModel = await afterModelRestart.breakdown(
            underTranscriptRoot: root.path,
            range: .today,
            now: Date()
        )

        #expect(continued.usage?.inputTokens == 1_100)
        #expect(continued.usage?.cacheReadTokens == 700)
        #expect(continued.usage?.outputTokens == 300)
        #expect(continued.usage?.totalTokens == 2_100)
        #expect(continued.usage?.responseCount == 3)
        #expect(continued.statistics.transcriptContentBytesRead == encodedBytes([third]))
        #expect(continued.statistics.jsonLinesSubmittedForDecoding == 1)
        #expect(continuedByModel[.named("gpt-5.6-sol")] == continued.usage)
        #expect(continuedByModel[.unattributed] == nil)
    }

    @Test func emptyModelAttributionKeepsItsExistingMeaningAcrossRestart() async throws {
        let root = try TempTranscripts("checkpoint-empty-model")
        let checkpoints = TempCheckpointDirectory("checkpoint-empty-model")
        let name = "rollout.jsonl"
        let file = root.url.appendingPathComponent(name)
        try root.write(name, [
            codexTokenCountLine(totalInput: 41, totalCached: 7, totalOutput: 25),
            codexTurnContextLine(model: ""),
        ])

        let initialReader = makeReader(checkpoints)
        let initial = await initialReader.readTranscript(at: file.path)
        let initialByModel = await initialReader.breakdown(
            underTranscriptRoot: root.path,
            range: .today,
            now: Date()
        )

        #expect(initial.statistics.checkpointWrites == 1)
        #expect(initialByModel[.named("")] == initial.usage)
        #expect(initialByModel[.unattributed] == nil)

        let freshReader = makeReader(checkpoints)
        let restored = await freshReader.readTranscript(at: file.path)
        let restoredByModel = await freshReader.breakdown(
            underTranscriptRoot: root.path,
            range: .today,
            now: Date()
        )

        #expect(restored.usage == initial.usage)
        #expect(restored.statistics.checkpointLoads == 1)
        #expect(restored.statistics.transcriptContentBytesRead == 0)
        #expect(restoredByModel[.named("")] == restored.usage)
        #expect(restoredByModel[.unattributed] == nil)
    }

    @Test func unusualCodexCountersKeepTheirExistingSafeMappingAcrossRestart() async throws {
        let cases: [(String, String, TokenUsage)] = [
            (
                "cached-exceeds-input",
                codexTokenCountLine(
                    totalInput: 5,
                    totalCached: 7,
                    totalOutput: 3
                ),
                TokenUsage(
                    inputTokens: 0,
                    outputTokens: 3,
                    cacheCreationTokens: 0,
                    cacheReadTokens: 7,
                    responseCount: 1
                )
            ),
            (
                "negative-input",
                codexTokenCountLine(totalInput: -5, totalOutput: 3),
                TokenUsage(
                    inputTokens: 0,
                    outputTokens: 3,
                    cacheCreationTokens: 0,
                    cacheReadTokens: 0,
                    responseCount: 1
                )
            ),
        ]

        for (label, line, expected) in cases {
            let root = try TempTranscripts("checkpoint-\(label)")
            let checkpoints = TempCheckpointDirectory("checkpoint-\(label)")
            let name = "rollout.jsonl"
            let file = root.url.appendingPathComponent(name)
            try root.write(name, [line])

            let initial = await makeReader(checkpoints)
                .readTranscript(at: file.path)
            let restored = await makeReader(checkpoints)
                .readTranscript(at: file.path)

            #expect(initial.usage == expected, Comment(rawValue: label))
            #expect(initial.statistics.checkpointWrites == 1)
            #expect(restored.usage == expected, Comment(rawValue: label))
            #expect(restored.statistics.checkpointLoads == 1)
            #expect(restored.statistics.transcriptContentBytesRead == 0)
        }
    }

    @Test func negativeClaudeCounterStillFailsOpenToSourceCounting() async throws {
        let root = try TempTranscripts("checkpoint-negative-claude")
        let checkpoints = TempCheckpointDirectory("checkpoint-negative-claude")
        let name = "session.jsonl"
        let file = root.url.appendingPathComponent(name)
        let line = claudeUsageLine(
            id: "negative-claude",
            input: -1,
            output: 10
        )
        try root.write(name, [line])
        let expected = TokenUsage(
            inputTokens: -1,
            outputTokens: 10,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            responseCount: 1
        )

        let initial = await makeReader(checkpoints)
            .readTranscript(at: file.path)
        let fresh = await makeReader(checkpoints)
            .readTranscript(at: file.path)

        #expect(initial.usage == expected)
        #expect(initial.usage?.totalTokens == 9)
        #expect(initial.statistics.checkpointWrites == 0)
        #expect(fresh.usage == expected)
        #expect(fresh.statistics.checkpointLoads == 0)
        #expect(fresh.statistics.transcriptContentBytesRead == encodedBytes([line]))
    }

    @Test func anOrdinaryPartialTailIsRereadUntilItCommitsThenBecomesAZeroContentHit() async throws {
        let root = try TempTranscripts("checkpoint-partial")
        let checkpoints = TempCheckpointDirectory("checkpoint-partial")
        let name = "session.jsonl"
        let file = root.url.appendingPathComponent(name)
        let first = claudeUsageLine(id: "partial-first", input: 10)
        let second = claudeUsageLine(id: "partial-second", output: 20)
        let split = second.index(second.startIndex, offsetBy: second.count / 2)
        let partial = String(second[..<split])
        let remainder = String(second[split...])
        try root.write(name, [first])
        try root.appendPartial(name, partial)

        let initial = await makeReader(checkpoints).readTranscript(at: file.path)
        let safeBoundary = encodedBytes([first])
        #expect(initial.usage?.totalTokens == 10)
        #expect(initial.continuation?.safeCommittedBytes == safeBoundary)
        #expect(initial.continuation?.observedBytes == safeBoundary + UInt64(partial.utf8.count))

        let rereadingReader = makeReader(checkpoints)
        let reread = await rereadingReader.readTranscript(at: file.path)

        #expect(reread.usage == initial.usage)
        #expect(reread.statistics.checkpointLoads == 1)
        #expect(reread.statistics.transcriptContentBytesRead == UInt64(partial.utf8.count))
        #expect(reread.statistics.jsonLinesSubmittedForDecoding == 0)
        #expect(reread.continuation?.safeCommittedBytes == safeBoundary)
        #expect(reread.continuation?.bufferedPartialBytes == partial.utf8.count)

        try root.appendPartial(name, remainder + "\n")
        let completed = await rereadingReader.readTranscript(at: file.path)

        #expect(completed.usage?.totalTokens == 30)
        #expect(completed.usage?.responseCount == 2)
        #expect(completed.continuation?.safeCommittedBytes == completed.continuation?.observedBytes)
        #expect(completed.statistics.transcriptContentBytesRead == UInt64(remainder.utf8.count + 1))
        #expect(completed.statistics.jsonLinesSubmittedForDecoding == 1)

        let nextFreshReader = makeReader(checkpoints)
        let unchanged = await nextFreshReader.readTranscript(at: file.path)

        #expect(unchanged.usage == completed.usage)
        #expect(unchanged.continuation == completed.continuation)
        #expect(unchanged.statistics.checkpointLoads == 1)
        #expect(unchanged.statistics.transcriptContentBytesRead == 0)
        #expect(unchanged.statistics.jsonLinesSubmittedForDecoding == 0)
    }

    @Test func allTokenKindsAndDailyRangesAreStructurallyEqualAfterRestart() async throws {
        let root = try TempTranscripts("checkpoint-days")
        let checkpoints = TempCheckpointDirectory("checkpoint-days")
        let name = "session.jsonl"
        try root.write(name, [
            claudeUsageLine(
                id: "today",
                input: 11,
                output: 13,
                cacheWrite: 17,
                cacheRead: 19
            ),
            claudeUsageLine(
                id: "within-seven",
                input: 2,
                output: 3,
                cacheWrite: 5,
                cacheRead: 7,
                daysAgo: 4
            ),
            claudeUsageLine(
                id: "within-thirty",
                input: 23,
                output: 29,
                cacheWrite: 31,
                cacheRead: 37,
                daysAgo: 12
            ),
        ])
        let now = Date()

        let coldReader = makeReader(checkpoints)
        let coldToday = await coldReader.breakdown(
            underTranscriptRoot: root.path,
            range: .today,
            now: now
        )
        let coldSeven = await coldReader.breakdown(
            underTranscriptRoot: root.path,
            range: .sevenDays,
            now: now
        )
        let coldThirty = await coldReader.breakdown(
            underTranscriptRoot: root.path,
            range: .thirtyDays,
            now: now
        )

        let freshReader = makeReader(checkpoints)
        let freshToday = await freshReader.breakdown(
            underTranscriptRoot: root.path,
            range: .today,
            now: now
        )
        let freshSeven = await freshReader.breakdown(
            underTranscriptRoot: root.path,
            range: .sevenDays,
            now: now
        )
        let freshThirty = await freshReader.breakdown(
            underTranscriptRoot: root.path,
            range: .thirtyDays,
            now: now
        )

        #expect(freshToday == coldToday)
        #expect(freshSeven == coldSeven)
        #expect(freshThirty == coldThirty)

        let today = try #require(freshToday[.named("claude-opus-5")])
        #expect(today.inputTokens == 11)
        #expect(today.outputTokens == 13)
        #expect(today.cacheCreationTokens == 17)
        #expect(today.cacheReadTokens == 19)
        #expect(today.totalTokens == 60)
        #expect(today.responseCount == 1)

        let seven = try #require(freshSeven[.named("claude-opus-5")])
        #expect(seven.inputTokens == 13)
        #expect(seven.outputTokens == 16)
        #expect(seven.cacheCreationTokens == 22)
        #expect(seven.cacheReadTokens == 26)
        #expect(seven.totalTokens == 77)
        #expect(seven.responseCount == 2)

        let thirty = try #require(freshThirty[.named("claude-opus-5")])
        #expect(thirty.inputTokens == 36)
        #expect(thirty.outputTokens == 45)
        #expect(thirty.cacheCreationTokens == 53)
        #expect(thirty.cacheReadTokens == 63)
        #expect(thirty.totalTokens == 197)
        #expect(thirty.responseCount == 3)
    }

    @Test func oversizedDiscardStateResumesAfterRestartAndMatchesAColdRebuild() async throws {
        let root = try TempTranscripts("checkpoint-oversized")
        let checkpoints = TempCheckpointDirectory("checkpoint-oversized")
        let name = "session.jsonl"
        let file = root.url.appendingPathComponent(name)
        let first = claudeUsageLine(id: "before-oversized", input: 11)
        try root.write(name, [first])
        try root.appendPartial(name, String(repeating: "x", count: 16 * 1024 * 1024 + 1))

        let discarding = await makeReader(checkpoints).readTranscript(at: file.path)

        #expect(discarding.usage?.totalTokens == 11)
        #expect(discarding.continuation?.safeCommittedBytes == encodedBytes([first]))
        #expect(discarding.continuation?.isDiscardingOversizedLine == true)
        #expect(discarding.continuation?.discardedThroughBytes == discarding.continuation?.observedBytes)
        #expect(discarding.statistics.checkpointWrites == 1)

        let after = claudeUsageLine(
            id: "after-oversized",
            output: 13,
            cacheWrite: 17,
            cacheRead: 19
        )
        try root.appendPartial(name, "\n" + after + "\n")

        let resumed = await makeReader(checkpoints).readTranscript(at: file.path)
        let cold = await TranscriptTokenReader(checkpointStore: nil).readTranscript(at: file.path)

        #expect(resumed.usage == cold.usage)
        #expect(resumed.continuation == cold.continuation)
        #expect(resumed.usage?.totalTokens == 60)
        #expect(resumed.usage?.responseCount == 2)
        #expect(resumed.statistics.checkpointLoads == 1)
        #expect(resumed.statistics.fingerprintBytesRead <= 8 * 1024)
        #expect(resumed.statistics.transcriptContentBytesRead == UInt64(after.utf8.count + 2))
        #expect(resumed.statistics.jsonLinesSubmittedForDecoding == 1)
    }

    @Test func aCheckpointArtifactUsesOnlyAHashedPathAndContainsNoRawTranscriptData() async throws {
        let root = try TempTranscripts("private-project-alex")
        let checkpoints = TempCheckpointDirectory("checkpoint-privacy")
        let name = "private-project-name/private-transcript-name.jsonl"
        let file = root.url.appendingPathComponent(name)
        let responseID = "raw-secret-response-id-046"
        let privateContent = "raw-super-secret-prompt-046"
        let nonUsageLine = #"{"type":"user","prompt":"\#(privateContent)"}"#
        let usageLine = claudeUsageLine(
            id: responseID,
            model: "claude-private-model",
            input: 41,
            output: 43
        )
        try root.write(name, [nonUsageLine, usageLine])

        let result = await makeReader(checkpoints).readTranscript(at: file.path)
        #expect(result.statistics.checkpointWrites == 1)

        let artifacts = try checkpoints.regularFiles()
        try #require(artifacts.count == 1)
        let artifact = try #require(artifacts.first)
        let expectedKey = sha256Hex(file.path)
        let artifactText = try String(contentsOf: artifact, encoding: .utf8)
        let envelope = try #require(
            JSONSerialization.jsonObject(with: Data(artifactText.utf8))
                as? [String: Any]
        )
        let checksum = try #require(envelope["checksum"] as? String)

        #expect(
            artifact.deletingLastPathComponent().resolvingSymlinksInPath()
                == checkpoints.url.resolvingSymlinksInPath()
        )
        #expect(artifact.lastPathComponent == "\(expectedKey).json")
        #expect(envelope["schemaVersion"] as? Int == TranscriptCheckpointCodec.schemaVersion)
        #expect(
            envelope["parserSemanticsVersion"] as? Int
                == TranscriptCheckpointCodec.parserSemanticsVersion
        )
        #expect(envelope["timeZoneIdentifier"] as? String == TimeZone.current.identifier)
        #expect(envelope["transcriptKey"] as? String == expectedKey)
        #expect(isSHA256Hex(checksum))
        #expect(artifactText.contains(#""cacheWriteTokens":"#))
        #expect(artifactText.contains(#""cacheCreationTokens":"#) == false)
        #expect(artifact.path.contains(file.lastPathComponent) == false)
        #expect(artifactText.contains(file.path) == false)
        #expect(artifactText.contains(root.path) == false)
        #expect(artifactText.contains(responseID) == false)
        #expect(artifactText.contains(privateContent) == false)
        #expect(artifactText.contains(nonUsageLine) == false)
        #expect(artifactText.contains(usageLine) == false)
    }

    @Test func unavailableCacheReadAndPublicationNeverDeleteThePreviousCheckpoint() async throws {
        let root = try TempTranscripts("checkpoint-preservation")
        let name = "session.jsonl"
        let file = root.url.appendingPathComponent(name)
        try root.write(name, [
            claudeUsageLine(id: "preserved", input: 17, output: 19),
        ])
        let store = RecordingCheckpointStore(
            loadAccess: .unavailable,
            publicationAccess: .unavailable
        )

        let result = await TranscriptTokenReader(
            checkpointStore: store,
            now: Date.init,
            timeZone: .current
        ).readTranscript(at: file.path)

        #expect(result.usage?.totalTokens == 36)
        #expect(result.usage?.responseCount == 1)
        #expect(result.statistics.checkpointInvalidations == 0)
        #expect(result.statistics.checkpointWrites == 0)
        #expect(store.counts.loads == 1)
        #expect(store.counts.publications == 1)
    }

    @Test func anUnavailableSourceNeverDeletesItsCheckpointSpeculatively() async throws {
        let root = try TempTranscripts("checkpoint-source-unavailable")
        let store = RecordingCheckpointStore(
            loadAccess: .unavailable,
            publicationAccess: .unavailable
        )
        let missingPath = root.url.appendingPathComponent("missing.jsonl").path

        let result = await TranscriptTokenReader(
            checkpointStore: store,
            now: Date.init,
            timeZone: .current
        ).readTranscript(at: missingPath)

        #expect(result.usage == nil)
        #expect(result.continuation == nil)
        #expect(store.counts.loads == 0)
        #expect(store.counts.publications == 0)
    }
}
