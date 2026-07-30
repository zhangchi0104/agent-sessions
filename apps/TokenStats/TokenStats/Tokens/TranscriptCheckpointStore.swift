//
//  TranscriptCheckpointStore.swift
//  TokenStats
//
//  Native macOS persistence for disposable transcript parse checkpoints.
//  Construction is inert; directories and files are touched only when a
//  transcript read asks the store to load, publish, or remove one entry.
//

import Darwin
import Foundation

nonisolated enum TranscriptCheckpointStoreError: Error {
    case invalidEntry
}

/// One JSON file per transcript, named only by the SHA-256 path identity.
nonisolated final class TranscriptCheckpointStore: TranscriptCheckpointStoring, @unchecked Sendable {
    static let maximumEntryBytes = 64 * 1024 * 1024

    static var defaultCacheRoot: URL {
        let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches", isDirectory: true)
        return caches
            .appendingPathComponent("dev.otakuma.TokenStats", isDirectory: true)
            .appendingPathComponent("token-reader-v1", isDirectory: true)
    }

    /// Unit-test hosts construct the production AppDelegate too. Default
    /// persistence is disabled there so unrelated tests never write fixture
    /// checkpoints into the developer's real cache; checkpoint tests inject an
    /// isolated native store explicitly.
    static var productionDefault: (any TranscriptCheckpointStoring)? {
        let environment = ProcessInfo.processInfo.environment
        let isTesting = environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        return isTesting ? nil : TranscriptCheckpointStore(cacheRoot: defaultCacheRoot)
    }

    let cacheRoot: URL
    private let fileManager: FileManager

    init(
        cacheRoot: URL,
        fileManager: FileManager = .default
    ) {
        self.cacheRoot = cacheRoot
        self.fileManager = fileManager
    }

    func checkpointURL(forTranscriptAt path: String) throws -> URL {
        let key = try TranscriptCheckpointKey.transcriptKey(for: path)
        return cacheRoot.appendingPathComponent("\(key).json", isDirectory: false)
    }

    func loadCheckpoint(forTranscriptAt path: String) throws -> Data? {
        let url = try checkpointURL(forTranscriptAt: path)
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let size = values.fileSize,
              size > 0,
              size <= Self.maximumEntryBytes
        else {
            throw TranscriptCheckpointStoreError.invalidEntry
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.isEmpty == false, data.count <= Self.maximumEntryBytes else {
            throw TranscriptCheckpointStoreError.invalidEntry
        }
        return data
    }

    func publishCheckpoint(_ data: Data, forTranscriptAt path: String) throws {
        guard data.isEmpty == false, data.count <= Self.maximumEntryBytes else {
            throw TranscriptCheckpointStoreError.invalidEntry
        }

        let destination = try checkpointURL(forTranscriptAt: path)
        try fileManager.createDirectory(
            at: cacheRoot,
            withIntermediateDirectories: true
        )

        let temporary = cacheRoot.appendingPathComponent(
            ".\(UUID().uuidString).tmp",
            isDirectory: false
        )
        var handle: FileHandle?
        do {
            let descriptor = Darwin.open(
                temporary.path,
                O_WRONLY | O_CREAT | O_EXCL,
                mode_t(S_IRUSR | S_IWUSR)
            )
            guard descriptor >= 0 else {
                throw currentPOSIXError()
            }

            let opened = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            handle = opened
            try opened.write(contentsOf: data)
            try opened.synchronize()
            try opened.close()
            handle = nil

            guard Darwin.rename(temporary.path, destination.path) == 0 else {
                throw currentPOSIXError()
            }
        } catch {
            try? handle?.close()
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    func removeCheckpoint(forTranscriptAt path: String) throws {
        let url = try checkpointURL(forTranscriptAt: path)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

nonisolated private func currentPOSIXError() -> POSIXError {
    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
}
