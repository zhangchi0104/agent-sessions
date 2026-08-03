//
//  TranscriptCheckpointInvalidationSupport.swift
//  TokenStatsTests
//
//  Seeded native checkpoints and deterministic authoritative-source mutations
//  shared by the invalidation behavior tests.
//

import Foundation
import Testing

struct InvalidationFixture {
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
            codexTokenCountLine(
                totalInput: 41,
                totalCached: 7,
                totalOutput: 25
            ),
        ],
        timeZone: TimeZone = .current
    ) async throws -> InvalidationFixture {
        let root = try TempTranscripts("invalidation-\(label)")
        let name = "session.jsonl"
        let transcriptURL = root.url.appendingPathComponent(name)
        try root.write(name, lines)
        let cacheRoot = temporaryCacheRoot(
            "invalidation-cache-\(label)"
        )
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
            checkpointURL: try store.checkpointURL(
                forTranscriptAt: transcriptURL.path
            ),
            sourceBytes: try fileSize(transcriptURL)
        )
    }

    func makeReader(
        timeZone: TimeZone = .current
    ) -> TranscriptTokenReader {
        nativeReader(cacheRoot, timeZone: timeZone)
    }
}

enum SourceRewrite: String, CaseIterable {
    case truncation
    case replacement
    case sameSizeSameMtime
    case modificationTimeOnly

    var originalLines: [String] {
        switch self {
        case .truncation:
            [
                claudeUsageLine(
                    id: "truncate-one",
                    input: 100,
                    output: 20
                ),
                claudeUsageLine(
                    id: "truncate-two",
                    input: 30,
                    output: 4
                ),
            ]
        case .replacement:
            [
                claudeUsageLine(
                    id: "replace-old",
                    input: 10,
                    output: 20
                ),
            ]
        case .sameSizeSameMtime:
            [
                claudeUsageLine(
                    id: "same-a",
                    input: 111,
                    output: 222
                ),
            ]
        case .modificationTimeOnly:
            [
                claudeUsageLine(
                    id: "mtime",
                    input: 17,
                    output: 19
                ),
            ]
        }
    }

    func apply(to url: URL) throws {
        switch self {
        case .truncation:
            try writeLines(
                [
                    claudeUsageLine(
                        id: "short",
                        input: 7,
                        output: 5
                    ),
                ],
                to: url
            )
        case .replacement:
            try writeLines(
                [
                    claudeUsageLine(
                        id: "replace-new-one",
                        input: 31,
                        output: 37
                    ),
                    claudeUsageLine(
                        id: "replace-new-two",
                        input: 41,
                        output: 43
                    ),
                ],
                to: url
            )
        case .sameSizeSameMtime:
            let replacement = claudeUsageLine(
                id: "same-b",
                input: 333,
                output: 444
            )
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
                [
                    .modificationDate:
                        modificationDate.addingTimeInterval(10),
                ],
                ofItemAtPath: url.path
            )
        }
    }
}

enum FingerprintMutation: String, CaseIterable {
    case prefix
    case oldTail
}

final class MutatingLoadStore: TranscriptCheckpointStoring,
    @unchecked Sendable
{
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
        if shouldMutate {
            try mutation()
        }
        return data
    }

    func publishCheckpoint(_ data: Data, forTranscriptAt path: String) throws {
        try base.publishCheckpoint(data, forTranscriptAt: path)
    }
}

func assertColdRebuildThenWarmHit(
    _ fixture: InvalidationFixture,
    label: String
) async throws {
    let expected = await TranscriptTokenReader(checkpointStore: nil)
        .readTranscript(at: fixture.transcriptURL.path)
    let rebuilt = await fixture.makeReader()
        .readTranscript(at: fixture.transcriptURL.path)
    let rebuiltSourceBytes = try fileSize(fixture.transcriptURL)
    #expect(
        rebuilt.usage == expected.usage,
        Comment(rawValue: "\(label) totals")
    )
    #expect(rebuilt.continuation == expected.continuation)
    #expect(rebuilt.statistics.checkpointInvalidations == 1)
    #expect(
        rebuilt.statistics.transcriptContentBytesRead
            == rebuiltSourceBytes
    )
    #expect(rebuilt.statistics.checkpointWrites == 1)

    let warm = await fixture.makeReader()
        .readTranscript(at: fixture.transcriptURL.path)
    #expect(warm.usage == expected.usage)
    #expect(warm.statistics.checkpointLoads == 1)
    #expect(warm.statistics.transcriptContentBytesRead == 0)
    #expect(warm.statistics.jsonLinesSubmittedForDecoding == 0)
}

func writeLines(_ lines: [String], to url: URL) throws {
    try Data((lines.joined(separator: "\n") + "\n").utf8)
        .write(to: url, options: .atomic)
}

func appendLines(_ lines: [String], to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(
        contentsOf: Data(
            (lines.joined(separator: "\n") + "\n").utf8
        )
    )
}

func overwriteByte(
    _ byte: UInt8,
    at offset: UInt64,
    in url: URL
) throws {
    let handle = try FileHandle(forUpdating: url)
    defer { try? handle.close() }
    try handle.seek(toOffset: offset)
    try handle.write(contentsOf: Data([byte]))
    try handle.synchronize()
}

func replacePreservingTimestamps(
    _ data: Data,
    at url: URL
) throws {
    let attributes = try FileManager.default.attributesOfItem(
        atPath: url.path
    )
    let modificationDate = try #require(
        attributes[.modificationDate] as? Date
    )
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes(
        [.modificationDate: modificationDate],
        ofItemAtPath: url.path
    )
}
