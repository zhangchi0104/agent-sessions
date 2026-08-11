//
//  TranscriptCheckpointStoreTests.swift
//  TokenStatsTests
//
//  Native publication failures and transcript lifecycle changes are exercised
//  through real temporary JSONL sources. Only store I/O and time are injected.
//

import Darwin
import Foundation
import Testing

@MainActor
struct TranscriptCheckpointStoreTests {
    @Test func theNativeStoreCreatesItsDirectoryOnlyWhenAReadPublishes() async throws {
        let root = try TempTranscripts("store-mkdir")
        let name = "session.jsonl"
        let transcript = root.url.appendingPathComponent(name)
        try root.write(name, [claudeUsageLine(id: "mkdir", input: 11, output: 13)])
        let cacheRoot = temporaryCacheRoot("mkdir")
        let store = TranscriptCheckpointStore(cacheRoot: cacheRoot)

        #expect(FileManager.default.fileExists(atPath: cacheRoot.path) == false)
        let reader = TranscriptTokenReader(
            checkpointStore: store,
            now: Date.init,
            timeZone: .current
        )
        #expect(FileManager.default.fileExists(atPath: cacheRoot.path) == false)

        let result = await reader.readTranscript(at: transcript.path)

        #expect(result.usage?.totalTokens == 24)
        #expect(result.statistics.checkpointWrites == 1)
        #expect(FileManager.default.fileExists(atPath: cacheRoot.path))
        #expect(
            FileManager.default.fileExists(
                atPath: try store.checkpointURL(forTranscriptAt: transcript.path).path
            )
        )
    }

    @Test func everyAtomicPublicationPhaseFailsOpenAndPreservesThePreviousEntry() async throws {
        for phase in TranscriptCheckpointStore.PublicationPhase.allCases {
            let root = try TempTranscripts("store-fault-\(phase)")
            let name = "session.jsonl"
            let transcript = root.url.appendingPathComponent(name)
            let first = claudeUsageLine(id: "old-\(phase)", input: 10, output: 20)
            try root.write(name, [first])
            let cacheRoot = temporaryCacheRoot("fault-\(phase)")
            let normalStore = TranscriptCheckpointStore(cacheRoot: cacheRoot)
            let initial = await TranscriptTokenReader(
                checkpointStore: normalStore,
                now: Date.init,
                timeZone: .current
            ).readTranscript(at: transcript.path)
            #expect(initial.statistics.checkpointWrites == 1)

            let checkpointURL = try normalStore.checkpointURL(
                forTranscriptAt: transcript.path
            )
            let previousEntry = try Data(contentsOf: checkpointURL)
            let appended = claudeUsageLine(
                id: "new-\(phase)",
                input: 3,
                output: 5,
                cacheRead: 11
            )
            try root.append(name, [appended])

            let faultStore = TranscriptCheckpointStore(
                cacheRoot: cacheRoot,
                publicationFault: { reached in
                    if reached == phase { throw InjectedStoreFailure.atPublicationPhase }
                }
            )
            let failedPublication = await TranscriptTokenReader(
                checkpointStore: faultStore,
                now: Date.init,
                timeZone: .current
            ).readTranscript(at: transcript.path)

            #expect(
                failedPublication.usage?.totalTokens == 49,
                Comment(rawValue: "\(phase) changed source-derived totals")
            )
            #expect(failedPublication.usage?.responseCount == 2)
            #expect(
                failedPublication.statistics.transcriptContentBytesRead
                    == UInt64(appended.utf8.count + 1)
            )
            #expect(failedPublication.statistics.checkpointWrites == 0)
            #expect(try Data(contentsOf: checkpointURL) == previousEntry)
            #expect(try checkpointTemporaryFiles(in: cacheRoot).isEmpty)

            // The prior checkpoint remains loadable. It resumes the same append
            // and replaces itself once publication is available again.
            let recovered = await TranscriptTokenReader(
                checkpointStore: normalStore,
                now: Date.init,
                timeZone: .current
            ).readTranscript(at: transcript.path)
            #expect(recovered.usage == failedPublication.usage)
            #expect(recovered.statistics.checkpointLoads == 1)
            #expect(
                recovered.statistics.transcriptContentBytesRead
                    == UInt64(appended.utf8.count + 1)
            )
            #expect(recovered.statistics.checkpointWrites == 1)

            let warm = await TranscriptTokenReader(
                checkpointStore: normalStore,
                now: Date.init,
                timeZone: .current
            ).readTranscript(at: transcript.path)
            #expect(warm.usage == recovered.usage)
            #expect(warm.statistics.checkpointLoads == 1)
            #expect(warm.statistics.transcriptContentBytesRead == 0)
        }
    }

    @Test func firstPublicationFailuresNeverExposeAPartialDestination() async throws {
        for phase in TranscriptCheckpointStore.PublicationPhase.allCases {
            let root = try TempTranscripts("store-first-fault-\(phase)")
            let name = "session.jsonl"
            let transcript = root.url.appendingPathComponent(name)
            try root.write(name, [
                claudeUsageLine(
                    id: "first-\(phase)",
                    input: 17,
                    output: 19
                ),
            ])
            let cacheRoot = temporaryCacheRoot("first-fault-\(phase)")
            let faultStore = TranscriptCheckpointStore(
                cacheRoot: cacheRoot,
                publicationFault: { reached in
                    if reached == phase {
                        throw InjectedStoreFailure.atPublicationPhase
                    }
                }
            )
            let checkpointURL = try faultStore.checkpointURL(
                forTranscriptAt: transcript.path
            )

            let failed = await TranscriptTokenReader(
                checkpointStore: faultStore,
                now: Date.init,
                timeZone: .current
            ).readTranscript(at: transcript.path)

            #expect(failed.usage?.totalTokens == 36)
            #expect(failed.statistics.checkpointWrites == 0)
            #expect(
                FileManager.default.fileExists(atPath: checkpointURL.path)
                    == false
            )
            #expect(try checkpointTemporaryFiles(in: cacheRoot).isEmpty)

            let recovered = await nativeReader(cacheRoot)
                .readTranscript(at: transcript.path)
            #expect(recovered.usage == failed.usage)
            #expect(recovered.statistics.checkpointMisses == 1)
            #expect(recovered.statistics.checkpointWrites == 1)
        }
    }

    @Test func aNonRegularCheckpointCannotBlockAndIsColdReplaced() async throws {
        let root = try TempTranscripts("store-non-regular")
        let name = "session.jsonl"
        let transcript = root.url.appendingPathComponent(name)
        try root.write(name, [
            claudeUsageLine(id: "non-regular", input: 23, output: 29),
        ])
        let cacheRoot = temporaryCacheRoot("non-regular")
        try FileManager.default.createDirectory(
            at: cacheRoot,
            withIntermediateDirectories: true
        )
        let store = TranscriptCheckpointStore(cacheRoot: cacheRoot)
        let checkpointURL = try store.checkpointURL(
            forTranscriptAt: transcript.path
        )
        guard Darwin.mkfifo(
            checkpointURL.path,
            mode_t(S_IRUSR | S_IWUSR)
        ) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        let rebuilt = await TranscriptTokenReader(
            checkpointStore: store,
            now: Date.init,
            timeZone: .current
        ).readTranscript(at: transcript.path)

        #expect(rebuilt.usage?.totalTokens == 52)
        #expect(rebuilt.statistics.checkpointInvalidations == 1)
        #expect(rebuilt.statistics.checkpointWrites == 1)
        var status = stat()
        #expect(lstat(checkpointURL.path, &status) == 0)
        #expect((status.st_mode & S_IFMT) == S_IFREG)

        let warm = await nativeReader(cacheRoot)
            .readTranscript(at: transcript.path)
        #expect(warm.usage == rebuilt.usage)
        #expect(warm.statistics.checkpointLoads == 1)
        #expect(warm.statistics.transcriptContentBytesRead == 0)
    }

    @Test func aCacheReadFailureStillColdRebuildsAndPublishesCorrectTotals() async throws {
        let root = try TempTranscripts("store-read-failure")
        let name = "session.jsonl"
        let transcript = root.url.appendingPathComponent(name)
        try root.write(name, [
            claudeUsageLine(id: "read-failure", input: 17, output: 19),
        ])
        let cacheRoot = temporaryCacheRoot("read-failure")
        let nativeStore = TranscriptCheckpointStore(cacheRoot: cacheRoot)
        _ = await TranscriptTokenReader(
            checkpointStore: nativeStore,
            now: Date.init,
            timeZone: .current
        ).readTranscript(at: transcript.path)
        let readFailure = LoadFailingStore(base: nativeStore)

        let rebuilt = await TranscriptTokenReader(
            checkpointStore: readFailure,
            now: Date.init,
            timeZone: .current
        ).readTranscript(at: transcript.path)
        let sourceBytes = try fileSize(transcript)

        #expect(rebuilt.usage?.totalTokens == 36)
        #expect(rebuilt.usage?.responseCount == 1)
        #expect(rebuilt.statistics.checkpointInvalidations == 0)
        #expect(rebuilt.statistics.checkpointMisses == 0)
        #expect(rebuilt.statistics.transcriptContentBytesRead == sourceBytes)
        #expect(rebuilt.statistics.checkpointWrites == 1)
    }

    @Test func abandonedTemporaryFilesAreIgnored() async throws {
        let root = try TempTranscripts("store-abandoned-temp")
        let name = "session.jsonl"
        let transcript = root.url.appendingPathComponent(name)
        try root.write(name, [claudeUsageLine(id: "temp", input: 23, output: 29)])
        let cacheRoot = temporaryCacheRoot("abandoned-temp")
        try FileManager.default.createDirectory(
            at: cacheRoot,
            withIntermediateDirectories: true
        )
        let abandoned = cacheRoot.appendingPathComponent(".interrupted.tmp")
        try Data("partial checkpoint".utf8).write(to: abandoned)
        let store = TranscriptCheckpointStore(cacheRoot: cacheRoot)

        let cold = await TranscriptTokenReader(
            checkpointStore: store,
            now: Date.init,
            timeZone: .current
        ).readTranscript(at: transcript.path)
        let warm = await TranscriptTokenReader(
            checkpointStore: store,
            now: Date.init,
            timeZone: .current
        ).readTranscript(at: transcript.path)

        #expect(cold.usage?.totalTokens == 52)
        #expect(cold.statistics.checkpointMisses == 1)
        #expect(cold.statistics.checkpointWrites == 1)
        #expect(warm.usage == cold.usage)
        #expect(warm.statistics.checkpointLoads == 1)
        #expect(warm.statistics.transcriptContentBytesRead == 0)
        #expect(FileManager.default.fileExists(atPath: abandoned.path))
    }

    @Test func deletingATranscriptMakesItsOrphanedCheckpointInert() async throws {
        let root = try TempTranscripts("lifecycle-delete")
        let name = "deleted.jsonl"
        let transcript = root.url.appendingPathComponent(name)
        try root.write(name, [claudeUsageLine(id: "deleted", input: 31, output: 37)])
        let cacheRoot = temporaryCacheRoot("lifecycle-delete")
        let seedReader = nativeReader(cacheRoot)
        let seeded = await seedReader.breakdown(
            underTranscriptRoot: root.path,
            range: .today,
            now: Date()
        )
        #expect(seeded[.named("claude-opus-5")]?.totalTokens == 68)
        try FileManager.default.removeItem(at: transcript)

        let freshReader = nativeReader(cacheRoot)
        let afterDeletion = await freshReader.breakdown(
            underTranscriptRoot: root.path,
            range: .today,
            now: Date()
        )

        #expect(afterDeletion.isEmpty)
        #expect(await freshReader.statistics == TranscriptReadStatistics())
        #expect(try checkpointRegularFiles(in: cacheRoot).count == 1)
    }

    @Test func aRenameIsAColdNewPathAndNeverDoubleCountsTheOldKey() async throws {
        let root = try TempTranscripts("lifecycle-rename")
        let old = root.url.appendingPathComponent("old.jsonl")
        let renamed = root.url.appendingPathComponent("renamed.jsonl")
        try root.write("old.jsonl", [
            claudeUsageLine(id: "renamed", input: 41, output: 43),
        ])
        let cacheRoot = temporaryCacheRoot("lifecycle-rename")
        _ = await nativeReader(cacheRoot).breakdown(
            underTranscriptRoot: root.path,
            range: .today,
            now: Date()
        )
        try FileManager.default.moveItem(at: old, to: renamed)

        let freshReader = nativeReader(cacheRoot)
        let result = await freshReader.breakdown(
            underTranscriptRoot: root.path,
            range: .today,
            now: Date()
        )
        let statistics = await freshReader.statistics
        let renamedBytes = try fileSize(renamed)

        #expect(result[.named("claude-opus-5")]?.totalTokens == 84)
        #expect(result[.named("claude-opus-5")]?.responseCount == 1)
        #expect(statistics.checkpointMisses == 1)
        #expect(statistics.checkpointLoads == 0)
        #expect(statistics.transcriptContentBytesRead == renamedBytes)
        #expect(try checkpointRegularFiles(in: cacheRoot).count == 2)
    }

    @Test func aNewTranscriptIsDiscoveredAlongsideExistingWarmEntries() async throws {
        let root = try TempTranscripts("lifecycle-new")
        try root.write("existing.jsonl", [
            claudeUsageLine(id: "existing", input: 10, output: 20),
        ])
        let cacheRoot = temporaryCacheRoot("lifecycle-new")
        _ = await nativeReader(cacheRoot).breakdown(
            underTranscriptRoot: root.path,
            range: .today,
            now: Date()
        )

        let newURL = root.url.appendingPathComponent("new.jsonl")
        try root.write("new.jsonl", [
            claudeUsageLine(id: "new", input: 30, output: 40),
        ])
        let freshReader = nativeReader(cacheRoot)
        let result = await freshReader.breakdown(
            underTranscriptRoot: root.path,
            range: .today,
            now: Date()
        )
        let statistics = await freshReader.statistics
        let newSourceBytes = try fileSize(newURL)

        #expect(result[.named("claude-opus-5")]?.totalTokens == 100)
        #expect(result[.named("claude-opus-5")]?.responseCount == 2)
        #expect(statistics.checkpointLoads == 1)
        #expect(statistics.checkpointMisses == 1)
        #expect(statistics.transcriptContentBytesRead == newSourceBytes)
        #expect(statistics.jsonLinesSubmittedForDecoding == 1)
    }

    @Test func checkpointWorkRemainsLazyUntilVisibleObservationAndStopsWhenHidden() async throws {
        let root = try TempTranscripts("lifecycle-visible")
        let name = "session.jsonl"
        try root.write(name, [claudeUsageLine(id: "visible", input: 11, output: 13)])
        let store = RecordingCheckpointStore()
        let reader = TranscriptTokenReader(
            checkpointStore: store,
            now: Date.init,
            timeZone: .current
        )
        let changes = EmittingTicks()
        let model = TokenOdometerModel(
            reader: reader,
            roots: [TranscriptRoot(id: .claudeCode, label: "Claude", path: root.path)],
            changeSource: changes
        )

        #expect(store.counts == .zero)
        #expect(await reader.statistics == TranscriptReadStatistics())
        #expect(model.hasLoaded == false)

        let observation = Task { await model.observeWhileVisible() }
        #expect(await waitUntil { model.usage?.totalTokens == 24 })
        #expect(store.counts.loads == 1)
        #expect(store.counts.publications == 1)

        observation.cancel()
        try? await Task.sleep(for: .milliseconds(50))
        let hiddenCounts = store.counts
        try root.append(name, [claudeUsageLine(id: "hidden", input: 100)])
        changes.emit()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(store.counts == hiddenCounts)
        #expect(model.usage?.totalTokens == 24)
    }

    @Test func theFortyEightHourEvictionDropsMemoryButReusesTheDiskCheckpoint() async throws {
        let source = try TempTranscripts("lifecycle-eviction-source")
        let otherRoot = try TempTranscripts("lifecycle-eviction-other")
        let name = "session.jsonl"
        let transcript = source.url.appendingPathComponent(name)
        try source.write(name, [
            claudeUsageLine(id: "eviction", input: 17, output: 19),
        ])
        let cacheRoot = temporaryCacheRoot("lifecycle-eviction")
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let store = TranscriptCheckpointStore(cacheRoot: cacheRoot)
        let reader = TranscriptTokenReader(
            checkpointStore: store,
            now: { clock.now },
            timeZone: .current
        )
        let initial = await reader.readTranscript(at: transcript.path)
        #expect(initial.statistics.checkpointWrites == 1)

        clock.advance(by: 49 * 60 * 60)
        _ = await reader.breakdown(
            underTranscriptRoot: otherRoot.path,
            range: .today,
            now: clock.now
        )
        let restored = await reader.readTranscript(at: transcript.path)

        #expect(restored.usage == initial.usage)
        #expect(restored.statistics.checkpointLoads == 1)
        #expect(restored.statistics.transcriptContentBytesRead == 0)
        #expect(restored.statistics.jsonLinesSubmittedForDecoding == 0)
        #expect(
            FileManager.default.fileExists(
                atPath: try store.checkpointURL(forTranscriptAt: transcript.path).path
            )
        )
    }

    @Test func deletingTheDisposableCacheDirectorySimplyCausesAColdRebuild() async throws {
        let root = try TempTranscripts("lifecycle-cache-delete")
        let name = "session.jsonl"
        let transcript = root.url.appendingPathComponent(name)
        try root.write(name, [
            claudeUsageLine(id: "cache-delete", input: 23, output: 29),
        ])
        let cacheRoot = temporaryCacheRoot("lifecycle-cache-delete")
        let first = await nativeReader(cacheRoot).readTranscript(at: transcript.path)
        #expect(first.statistics.checkpointWrites == 1)
        try FileManager.default.removeItem(at: cacheRoot)

        let rebuilt = await nativeReader(cacheRoot).readTranscript(at: transcript.path)
        let sourceBytes = try fileSize(transcript)

        #expect(rebuilt.usage == first.usage)
        #expect(rebuilt.statistics.checkpointMisses == 1)
        #expect(rebuilt.statistics.transcriptContentBytesRead == sourceBytes)
        #expect(rebuilt.statistics.checkpointWrites == 1)
    }
}

private enum InjectedStoreFailure: Error {
    case atPublicationPhase
    case load
}

private final class LoadFailingStore: TranscriptCheckpointStoring, @unchecked Sendable {
    private let base: TranscriptCheckpointStore

    init(base: TranscriptCheckpointStore) {
        self.base = base
    }

    func loadCheckpoint(forTranscriptAt path: String) throws -> Data? {
        throw InjectedStoreFailure.load
    }

    func publishCheckpoint(_ data: Data, forTranscriptAt path: String) throws {
        try base.publishCheckpoint(data, forTranscriptAt: path)
    }
}
