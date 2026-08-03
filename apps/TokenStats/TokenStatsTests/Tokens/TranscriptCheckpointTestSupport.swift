//
//  TranscriptCheckpointTestSupport.swift
//  TokenStatsTests
//
//  Shared filesystem, reader, clock, and empty-store fixtures for transcript
//  checkpoint tests. Production behavior remains exercised through real files
//  and the native store; only cache roots and deterministic failure points vary.
//

import CryptoKit
import Darwin
import Foundation

struct TempCheckpointDirectory {
    let url: URL

    init(_ label: String) {
        url = temporaryCacheRoot(label)
    }

    func regularFiles() throws -> [URL] {
        try checkpointRegularFiles(in: url)
    }

    func temporaryFiles() throws -> [URL] {
        try checkpointTemporaryFiles(in: url)
    }
}

func makeReader(
    _ checkpoints: TempCheckpointDirectory,
    now: @escaping @Sendable () -> Date = Date.init,
    timeZone: TimeZone = .current
) -> TranscriptTokenReader {
    nativeReader(checkpoints.url, now: now, timeZone: timeZone)
}

func nativeReader(
    _ cacheRoot: URL,
    now: @escaping @Sendable () -> Date = Date.init,
    timeZone: TimeZone = .current
) -> TranscriptTokenReader {
    TranscriptTokenReader(
        checkpointStore: TranscriptCheckpointStore(cacheRoot: cacheRoot),
        now: now,
        timeZone: timeZone
    )
}

func temporaryCacheRoot(_ label: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("\(label)-\(UUID().uuidString)")
        .appendingPathComponent("token-reader-v1")
}

func fileSize(_ url: URL) throws -> UInt64 {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var status = stat()
    guard fstat(handle.fileDescriptor, &status) == 0, status.st_size >= 0 else {
        throw POSIXError(.EIO)
    }
    return UInt64(status.st_size)
}

func checkpointRegularFiles(in root: URL) throws -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey]
    ) else { return [] }

    return enumerator.compactMap { item in
        guard let url = item as? URL,
              (try? url.resourceValues(
                  forKeys: [.isRegularFileKey]
              ).isRegularFile) == true
        else {
            return nil
        }
        return url
    }
}

func checkpointTemporaryFiles(in root: URL) throws -> [URL] {
    try checkpointRegularFiles(in: root).filter {
        $0.pathExtension == "tmp"
    }
}

func encodedBytes(_ lines: [String]) -> UInt64 {
    UInt64(lines.joined(separator: "\n").utf8.count + 1)
}

func sha256Hex(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
}

func isSHA256Hex(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy {
        ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66)
    }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedNow: Date

    init(_ now: Date) {
        storedNow = now
    }

    var now: Date {
        lock.withLock { storedNow }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock {
            storedNow = storedNow.addingTimeInterval(interval)
        }
    }
}

final class RecordingCheckpointStore: TranscriptCheckpointStoring,
    @unchecked Sendable
{
    struct Counts: Equatable {
        var loads = 0
        var publications = 0

        static let zero = Counts()
    }

    enum Access: Equatable {
        case available
        case unavailable
    }

    enum Failure: Error {
        case unavailable
    }

    private let loadAccess: Access
    private let publicationAccess: Access
    private let lock = NSLock()
    private var storedCounts = Counts()

    init(
        loadAccess: Access = .available,
        publicationAccess: Access = .available
    ) {
        self.loadAccess = loadAccess
        self.publicationAccess = publicationAccess
    }

    var counts: Counts {
        lock.withLock { storedCounts }
    }

    func loadCheckpoint(forTranscriptAt path: String) throws -> Data? {
        lock.withLock { storedCounts.loads += 1 }
        guard loadAccess == .available else {
            throw Failure.unavailable
        }
        return nil
    }

    func publishCheckpoint(_ data: Data, forTranscriptAt path: String) throws {
        lock.withLock { storedCounts.publications += 1 }
        guard publicationAccess == .available else {
            throw Failure.unavailable
        }
    }
}
