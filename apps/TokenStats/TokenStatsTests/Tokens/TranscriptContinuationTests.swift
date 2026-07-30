//
//  TranscriptContinuationTests.swift
//  TokenStatsTests
//
//  Restart-safe framing at the TranscriptTokenReader boundary. These tests use
//  real JSONL files and observe only the reader's result, continuation summary,
//  and I/O statistics; the parser and framer remain free to change internally.
//

import Foundation
import Testing
@testable import TokenStats

struct TranscriptContinuationTests {
    @Test func anOrdinaryPartialTailCommitsOnlyAfterItsNewline() async throws {
        let root = try TempTranscripts("continuation-partial")
        let name = "transcript.jsonl"
        let file = root.url.appendingPathComponent(name)
        let first = claudeUsageLine(id: "first", input: 10, output: 20)
        try root.write(name, [first])

        let second = claudeUsageLine(id: "second", input: 7, output: 3)
        let split = second.index(second.startIndex, offsetBy: second.count / 2)
        let partial = String(second[..<split])
        let remainder = String(second[split...])
        try root.appendPartial(name, partial)

        let reader = TranscriptTokenReader()
        let initial = await reader.readTranscript(at: file.path)
        let firstRecordBytes = UInt64(first.utf8.count + 1)
        let initialSourceBytes = firstRecordBytes + UInt64(partial.utf8.count)

        #expect(initial.usage?.totalTokens == 30)
        #expect(initial.usage?.responseCount == 1)
        #expect(initial.continuation?.safeCommittedBytes == firstRecordBytes)
        #expect(initial.continuation?.observedBytes == initialSourceBytes)
        #expect(initial.continuation?.bufferedPartialBytes == partial.utf8.count)
        #expect(initial.continuation?.isDiscardingOversizedLine == false)
        #expect(initial.continuation?.discardedThroughBytes == nil)
        #expect(initial.statistics.transcriptContentBytesRead == initialSourceBytes)
        #expect(initial.statistics.jsonLinesSubmittedForDecoding == 1)

        try root.appendPartial(name, remainder + "\n")
        let completed = await reader.readTranscript(at: file.path)
        let completedSourceBytes = initialSourceBytes + UInt64(remainder.utf8.count + 1)

        #expect(completed.usage?.totalTokens == 40)
        #expect(completed.usage?.responseCount == 2)
        #expect(completed.continuation?.safeCommittedBytes == completedSourceBytes)
        #expect(completed.continuation?.observedBytes == completedSourceBytes)
        #expect(completed.continuation?.bufferedPartialBytes == 0)
        #expect(completed.statistics.transcriptContentBytesRead == UInt64(remainder.utf8.count + 1))
        #expect(completed.statistics.jsonLinesSubmittedForDecoding == 1)

        let unchanged = await reader.readTranscript(at: file.path)
        #expect(unchanged.usage == completed.usage)
        #expect(unchanged.statistics.transcriptContentBytesRead == 0)
        #expect(unchanged.statistics.jsonLinesSubmittedForDecoding == 0)
    }

    @Test func anOversizedUnfinishedRecordIsBoundedAndTheNextRecordStillParses() async throws {
        let root = try TempTranscripts("continuation-oversized")
        let name = "transcript.jsonl"
        let file = root.url.appendingPathComponent(name)
        let first = claudeUsageLine(id: "before", input: 11)
        try root.write(name, [first])

        let maximumLineBytes = 16 * 1024 * 1024
        try root.appendPartial(name, String(repeating: "x", count: maximumLineBytes + 1))

        let reader = TranscriptTokenReader()
        let discarding = await reader.readTranscript(at: file.path)
        let firstRecordBytes = UInt64(first.utf8.count + 1)

        #expect(discarding.usage?.totalTokens == 11)
        #expect(discarding.continuation?.safeCommittedBytes == firstRecordBytes)
        #expect(discarding.continuation?.bufferedPartialBytes ?? .max <= maximumLineBytes)
        #expect(discarding.continuation?.isDiscardingOversizedLine == true)
        #expect(discarding.continuation?.discardedThroughBytes == discarding.continuation?.observedBytes)
        #expect(discarding.statistics.jsonLinesSubmittedForDecoding == 1)

        let after = claudeUsageLine(id: "after", output: 13)
        try root.appendPartial(name, "\n" + after + "\n")
        let recovered = await reader.readTranscript(at: file.path)

        #expect(recovered.usage?.totalTokens == 24)
        #expect(recovered.usage?.responseCount == 2)
        #expect(recovered.continuation?.safeCommittedBytes == recovered.continuation?.observedBytes)
        #expect(recovered.continuation?.bufferedPartialBytes == 0)
        #expect(recovered.continuation?.isDiscardingOversizedLine == false)
        #expect(recovered.continuation?.discardedThroughBytes == nil)
        #expect(recovered.statistics.transcriptContentBytesRead == UInt64(after.utf8.count + 2))
        #expect(recovered.statistics.jsonLinesSubmittedForDecoding == 1)
    }

    @Test func eachCandidateJSONLineIsCountedOnceAcrossDecoderFallbacks() async throws {
        let root = try TempTranscripts("continuation-statistics")
        let name = "rollout.jsonl"
        let file = root.url.appendingPathComponent(name)
        let lines = [
            #"{"timestamp":"ignored","type":"event_msg","payload":{"type":"notice"}}"#,
            codexTurnContextLine(model: "gpt-5.6-sol"),
            codexTokenCountLine(totalInput: 100, totalCached: 40, totalOutput: 20),
        ]
        try root.write(name, lines)

        let reader = TranscriptTokenReader()
        let result = await reader.readTranscript(at: file.path)
        let sourceBytes = UInt64(lines.joined(separator: "\n").utf8.count + 1)

        #expect(result.usage?.totalTokens == 120)
        #expect(result.statistics.transcriptContentBytesRead == sourceBytes)
        #expect(result.statistics.jsonLinesSubmittedForDecoding == 2)
    }

    @Test func m1DoesNotTouchItsCheckpointStoreDuringConstructionOrReads() async throws {
        let root = try TempTranscripts("continuation-no-store")
        let name = "transcript.jsonl"
        let file = root.url.appendingPathComponent(name)
        try root.write(name, [claudeUsageLine(id: "one", input: 1)])
        let store = RecordingCheckpointStore()

        let reader = TranscriptTokenReader(
            checkpointStore: store,
            now: Date.init,
            timeZone: TimeZone(secondsFromGMT: 0) ?? .current
        )

        #expect(store.counts == .zero)
        #expect(await reader.readTranscript(at: file.path).usage?.totalTokens == 1)
        #expect(store.counts == .zero)
    }
}

private final class RecordingCheckpointStore: TranscriptCheckpointStoring, @unchecked Sendable {
    struct Counts: Equatable {
        var loads = 0
        var publications = 0
        var removals = 0

        static let zero = Counts()
    }

    private let lock = NSLock()
    private var storedCounts = Counts()

    var counts: Counts {
        lock.withLock { storedCounts }
    }

    func loadCheckpoint(forTranscriptAt path: String) throws -> Data? {
        lock.withLock { storedCounts.loads += 1 }
        return nil
    }

    func publishCheckpoint(_ data: Data, forTranscriptAt path: String) throws {
        lock.withLock { storedCounts.publications += 1 }
    }

    func removeCheckpoint(forTranscriptAt path: String) throws {
        lock.withLock { storedCounts.removals += 1 }
    }
}
