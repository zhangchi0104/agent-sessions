//
//  TranscriptFileReader.swift
//  TokenStats
//
//  One atomic per-transcript read transaction. This module hides stable source
//  snapshots, checkpoint restore/publication, bounded fingerprints, cold retry,
//  and incremental JSONL parsing behind a single state transition.
//

import Darwin
import Foundation

nonisolated struct TranscriptFileState: Equatable, Sendable {
    let parserState: TranscriptParserState
    let sourceValidation: TranscriptSourceValidation

    func breakdown(
        forDayKeys dayKeys: Set<String>
    ) -> [ModelName: TokenUsage] {
        parserState.breakdown(forDayKeys: dayKeys)
    }
}

nonisolated struct TranscriptFileTransition: Equatable, Sendable {
    let nextState: TranscriptFileState?
    let result: TranscriptReadResult
}

/// Deep module for reading exactly one transcript.
///
/// Callers provide the previous stable state, if any, and receive a complete
/// replacement. No partially parsed candidate escapes this module.
nonisolated struct TranscriptFileReader {
    private enum ReadStart {
        case remembered(TranscriptFileState)
        case checkpointOrCold
        case cold
    }

    private enum ReadFailure: Error {
        case retry
    }

    private struct PreparedRead {
        var parserState: TranscriptParserState
        var fingerprints: FingerprintAccumulator
        let shouldPublish: Bool
        let resumedState: Bool

        static func fresh(shouldPublish: Bool) -> PreparedRead {
            PreparedRead(
                parserState: .fresh(),
                fingerprints: .fresh(),
                shouldPublish: shouldPublish,
                resumedState: false
            )
        }
    }

    private let checkpointStore: (any TranscriptCheckpointStoring)?
    private let timeZoneIdentifier: String
    private let parser: TranscriptJSONLParser
    private static let chunkSize = 4 << 20

    init(
        checkpointStore: (any TranscriptCheckpointStoring)?,
        timeZone: TimeZone
    ) {
        self.checkpointStore = checkpointStore
        timeZoneIdentifier = timeZone.identifier
        parser = TranscriptJSONLParser(timeZone: timeZone)
    }

    func read(
        at path: String,
        resuming previous: TranscriptFileState?
    ) -> TranscriptFileTransition {
        var statistics = TranscriptReadStatistics()
        let firstStart = previous.map(ReadStart.remembered)
            ?? .checkpointOrCold

        do {
            let state = try attempt(
                at: path,
                start: firstStart,
                statistics: &statistics
            )
            return transition(state: state, statistics: statistics)
        } catch {
            do {
                let state = try attempt(
                    at: path,
                    start: .cold,
                    statistics: &statistics
                )
                return transition(state: state, statistics: statistics)
            } catch {
                return transition(state: nil, statistics: statistics)
            }
        }
    }

    private func transition(
        state: TranscriptFileState?,
        statistics: TranscriptReadStatistics
    ) -> TranscriptFileTransition {
        TranscriptFileTransition(
            nextState: state,
            result: TranscriptReadResult(
                usage: state?.parserState.reportedUsage,
                continuation: state?.parserState.snapshot,
                statistics: statistics
            )
        )
    }

    /// Returns nil only when the authoritative path cannot be opened as a
    /// regular file. Any unstable or internally inconsistent candidate throws
    /// so the outer read can perform exactly one explicit cold retry.
    private func attempt(
        at path: String,
        start: ReadStart,
        statistics: inout TranscriptReadStatistics
    ) throws -> TranscriptFileState? {
        guard let source = StableTranscriptSource(path: path) else {
            return nil
        }
        defer { source.close() }

        var prepared = try prepare(
            start: start,
            path: path,
            source: source,
            statistics: &statistics
        )
        let contentBytesBefore = statistics.transcriptContentBytesRead
        let observedBytes = prepared.parserState.observedBytes
        guard source.metadata.length >= observedBytes else {
            throw ReadFailure.retry
        }

        if source.metadata.length > observedBytes {
            do {
                try source.seek(to: observedBytes)
                while prepared.parserState.observedBytes
                    < source.metadata.length
                {
                    let remaining = source.metadata.length
                        - prepared.parserState.observedBytes
                    let requested = Int(min(
                        UInt64(Self.chunkSize),
                        remaining
                    ))
                    guard let chunk = try source.read(upToCount: requested),
                          chunk.isEmpty == false
                    else {
                        throw ReadFailure.retry
                    }

                    prepared.fingerprints.observe(
                        chunk,
                        startingAt: prepared.parserState.observedBytes
                    )
                    statistics.transcriptContentBytesRead +=
                        UInt64(chunk.count)
                    do {
                        try parser.consume(
                            chunk,
                            into: &prepared.parserState,
                            statistics: &statistics
                        )
                    } catch {
                        if prepared.resumedState, checkpointStore != nil {
                            statistics.checkpointInvalidations += 1
                        }
                        throw ReadFailure.retry
                    }
                }
            } catch let failure as ReadFailure {
                throw failure
            } catch {
                throw ReadFailure.retry
            }
        }

        guard source.isStable,
              prepared.parserState.observedBytes
                  == source.metadata.length,
              let sourceValidation = prepared.fingerprints.sourceValidation(
                  for: source.metadata
              )
        else {
            throw ReadFailure.retry
        }

        let state = TranscriptFileState(
            parserState: prepared.parserState,
            sourceValidation: sourceValidation
        )
        let readContent = statistics.transcriptContentBytesRead
            > contentBytesBefore
        if (prepared.shouldPublish || readContent),
           let checkpointStore
        {
            do {
                let data = try TranscriptCheckpointCodec.encode(
                    TranscriptCheckpoint(
                        source: sourceValidation,
                        continuation: prepared.parserState
                            .durableContinuation
                    ),
                    transcriptPath: path,
                    timeZoneIdentifier: timeZoneIdentifier
                )
                try checkpointStore.publishCheckpoint(
                    data,
                    forTranscriptAt: path
                )
                statistics.checkpointWrites += 1
            } catch {
                // Checkpoints are disposable. A publication failure cannot
                // invalidate the stable source-derived result returned above.
            }
        }
        return state
    }

    private func prepare(
        start: ReadStart,
        path: String,
        source: StableTranscriptSource,
        statistics: inout TranscriptReadStatistics
    ) throws -> PreparedRead {
        switch start {
        case .cold:
            return .fresh(shouldPublish: checkpointStore != nil)

        case .remembered(let state):
            guard let material = try source.validate(
                state.sourceValidation,
                statistics: &statistics
            ) else {
                if checkpointStore != nil {
                    statistics.checkpointInvalidations += 1
                }
                return .fresh(shouldPublish: checkpointStore != nil)
            }
            return PreparedRead(
                parserState: state.parserState,
                fingerprints: .appending(
                    material,
                    after: state.sourceValidation
                        .sourceLengthAtCheckpoint
                ),
                shouldPublish: false,
                resumedState: true
            )

        case .checkpointOrCold:
            return try prepareCheckpointOrCold(
                path: path,
                source: source,
                statistics: &statistics
            )
        }
    }

    private func prepareCheckpointOrCold(
        path: String,
        source: StableTranscriptSource,
        statistics: inout TranscriptReadStatistics
    ) throws -> PreparedRead {
        guard let checkpointStore else {
            return .fresh(shouldPublish: false)
        }

        let load = Result {
            try checkpointStore.loadCheckpoint(forTranscriptAt: path)
        }
        guard source.pathStillMatches else {
            switch load {
            case .success(.some),
                 .failure(TranscriptCheckpointStoreError.invalidEntry):
                statistics.checkpointInvalidations += 1
            case .success(.none), .failure:
                break
            }
            throw ReadFailure.retry
        }

        let data: Data
        switch load {
        case .success(.none):
            statistics.checkpointMisses += 1
            return .fresh(shouldPublish: true)
        case .success(.some(let loaded)):
            data = loaded
        case .failure(TranscriptCheckpointStoreError.invalidEntry):
            statistics.checkpointInvalidations += 1
            return .fresh(shouldPublish: true)
        case .failure:
            return .fresh(shouldPublish: true)
        }

        let checkpoint: TranscriptCheckpoint
        do {
            checkpoint = try TranscriptCheckpointCodec.decode(
                data,
                transcriptPath: path,
                timeZoneIdentifier: timeZoneIdentifier
            )
        } catch {
            statistics.checkpointInvalidations += 1
            return .fresh(shouldPublish: true)
        }

        guard let material = try source.validate(
            checkpoint.source,
            statistics: &statistics
        ) else {
            statistics.checkpointInvalidations += 1
            return .fresh(shouldPublish: true)
        }
        guard source.pathStillMatches else {
            statistics.checkpointInvalidations += 1
            throw ReadFailure.retry
        }

        statistics.checkpointLoads += 1
        return PreparedRead(
            parserState: try .restore(checkpoint.continuation),
            fingerprints: .appending(
                material,
                after: checkpoint.source.sourceLengthAtCheckpoint
            ),
            shouldPublish: false,
            resumedState: true
        )
    }
}

nonisolated private struct FingerprintMaterial {
    let prefix: Data
    let oldEnd: Data
}

nonisolated private struct FingerprintAccumulator {
    private(set) var prefix: Data
    private(set) var oldEnd: Data
    private let appendStartsAt: UInt64

    static func fresh() -> FingerprintAccumulator {
        FingerprintAccumulator(
            prefix: Data(),
            oldEnd: Data(),
            appendStartsAt: 0
        )
    }

    static func appending(
        _ material: FingerprintMaterial,
        after sourceLength: UInt64
    ) -> FingerprintAccumulator {
        FingerprintAccumulator(
            prefix: material.prefix,
            oldEnd: material.oldEnd,
            appendStartsAt: sourceLength
        )
    }

    mutating func observe(_ data: Data, startingAt offset: UInt64) {
        let dataEnd = offset + UInt64(data.count)
        guard dataEnd > appendStartsAt else { return }
        let skipped = appendStartsAt > offset
            ? Int(appendStartsAt - offset)
            : 0
        let appended = data[data.index(
            data.startIndex,
            offsetBy: skipped
        )...]

        if prefix.count < TranscriptCheckpointCodec.fingerprintWindowBytes {
            let needed = TranscriptCheckpointCodec.fingerprintWindowBytes
                - prefix.count
            prefix.append(contentsOf: appended.prefix(needed))
        }

        if appended.count
            >= TranscriptCheckpointCodec.fingerprintWindowBytes
        {
            oldEnd = Data(appended.suffix(
                TranscriptCheckpointCodec.fingerprintWindowBytes
            ))
        } else {
            oldEnd.append(contentsOf: appended)
            if oldEnd.count
                > TranscriptCheckpointCodec.fingerprintWindowBytes
            {
                oldEnd.removeFirst(
                    oldEnd.count
                        - TranscriptCheckpointCodec.fingerprintWindowBytes
                )
            }
        }
    }

    func sourceValidation(
        for metadata: TranscriptSourceMetadata
    ) -> TranscriptSourceValidation? {
        let expectedLength = Int(min(
            metadata.length,
            UInt64(TranscriptCheckpointCodec.fingerprintWindowBytes)
        ))
        guard prefix.count == expectedLength,
              oldEnd.count == expectedLength
        else {
            return nil
        }
        return TranscriptSourceValidation(
            sourceLengthAtCheckpoint: metadata.length,
            lastWriteSeconds: metadata.lastWriteSeconds,
            lastWriteNanoseconds: metadata.lastWriteNanoseconds,
            prefixFingerprint: TranscriptFingerprint(
                offset: 0,
                length: expectedLength,
                sha256: TranscriptHash.sha256Hex(prefix)
            ),
            oldEndFingerprint: TranscriptFingerprint(
                offset: metadata.length - UInt64(expectedLength),
                length: expectedLength,
                sha256: TranscriptHash.sha256Hex(oldEnd)
            )
        )
    }
}

nonisolated private struct TranscriptSourceMetadata: Equatable {
    let device: UInt64
    let inode: UInt64
    let length: UInt64
    let lastWriteSeconds: Int64
    let lastWriteNanoseconds: Int64
}

/// One opened regular-file snapshot. The concrete POSIX implementation remains
/// internal; tests exercise it with real temporary files.
nonisolated private final class StableTranscriptSource {
    let path: String
    let handle: FileHandle
    let metadata: TranscriptSourceMetadata

    init?(path: String) {
        let descriptor = Darwin.open(
            path,
            O_RDONLY | O_CLOEXEC | O_NONBLOCK
        )
        guard descriptor >= 0,
              let metadata = Self.metadata(forDescriptor: descriptor)
        else {
            if descriptor >= 0 {
                Darwin.close(descriptor)
            }
            return nil
        }
        self.path = path
        handle = FileHandle(
            fileDescriptor: descriptor,
            closeOnDealloc: true
        )
        self.metadata = metadata
    }

    var pathStillMatches: Bool {
        Self.metadata(atPath: path) == metadata
    }

    var isStable: Bool {
        Self.metadata(forDescriptor: handle.fileDescriptor) == metadata
            && pathStillMatches
    }

    func close() {
        try? handle.close()
    }

    func seek(to offset: UInt64) throws {
        try handle.seek(toOffset: offset)
    }

    func read(upToCount count: Int) throws -> Data? {
        try handle.read(upToCount: count)
    }

    /// Returns nil when the checkpoint describes a different source. I/O
    /// failures throw so the caller retries the authoritative path.
    func validate(
        _ validation: TranscriptSourceValidation,
        statistics: inout TranscriptReadStatistics
    ) throws -> FingerprintMaterial? {
        guard metadata.length
            >= validation.sourceLengthAtCheckpoint
        else {
            return nil
        }
        if metadata.length == validation.sourceLengthAtCheckpoint {
            guard metadata.lastWriteSeconds
                    == validation.lastWriteSeconds,
                  metadata.lastWriteNanoseconds
                    == validation.lastWriteNanoseconds
            else {
                return nil
            }
        }

        guard let prefix = try read(
            validation.prefixFingerprint,
            statistics: &statistics
        ),
        let oldEnd = try read(
            validation.oldEndFingerprint,
            statistics: &statistics
        ),
        TranscriptHash.sha256Hex(prefix)
            == validation.prefixFingerprint.sha256,
        TranscriptHash.sha256Hex(oldEnd)
            == validation.oldEndFingerprint.sha256,
        Self.metadata(forDescriptor: handle.fileDescriptor) == metadata
        else {
            return nil
        }
        return FingerprintMaterial(prefix: prefix, oldEnd: oldEnd)
    }

    private func read(
        _ fingerprint: TranscriptFingerprint,
        statistics: inout TranscriptReadStatistics
    ) throws -> Data? {
        guard fingerprint.length >= 0,
              fingerprint.length
                  <= TranscriptCheckpointCodec.fingerprintWindowBytes,
              fingerprint.offset
                  <= UInt64.max - UInt64(fingerprint.length)
        else {
            return nil
        }

        try handle.seek(toOffset: fingerprint.offset)
        var result = Data()
        while result.count < fingerprint.length {
            let remaining = fingerprint.length - result.count
            guard let chunk = try handle.read(upToCount: remaining),
                  chunk.isEmpty == false
            else {
                return nil
            }
            result.append(chunk)
            statistics.fingerprintBytesRead += UInt64(chunk.count)
        }
        return result
    }

    private static func metadata(
        atPath path: String
    ) -> TranscriptSourceMetadata? {
        let descriptor = Darwin.open(
            path,
            O_RDONLY | O_CLOEXEC | O_NONBLOCK
        )
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }
        return metadata(forDescriptor: descriptor)
    }

    private static func metadata(
        forDescriptor descriptor: Int32
    ) -> TranscriptSourceMetadata? {
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_size >= 0
        else {
            return nil
        }
        return TranscriptSourceMetadata(
            device: UInt64(status.st_dev),
            inode: UInt64(status.st_ino),
            length: UInt64(status.st_size),
            lastWriteSeconds: Int64(status.st_mtimespec.tv_sec),
            lastWriteNanoseconds: Int64(status.st_mtimespec.tv_nsec)
        )
    }
}
