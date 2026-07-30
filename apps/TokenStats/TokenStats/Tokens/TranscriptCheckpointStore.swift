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
    case unavailable
}

/// One JSON file per transcript, named only by the SHA-256 path identity.
nonisolated final class TranscriptCheckpointStore: TranscriptCheckpointStoring, @unchecked Sendable {
    enum PublicationPhase: CaseIterable, Sendable {
        case createDirectory
        case openTemporary
        case write
        case synchronize
        case replace
    }

    static let maximumEntryBytes = TranscriptCheckpointCodec.maximumEntryBytes

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
    private let publicationFault: (@Sendable (PublicationPhase) throws -> Void)?

    init(
        cacheRoot: URL,
        fileManager: FileManager = .default,
        publicationFault: (@Sendable (PublicationPhase) throws -> Void)? = nil
    ) {
        self.cacheRoot = cacheRoot
        self.fileManager = fileManager
        self.publicationFault = publicationFault
    }

    func checkpointURL(forTranscriptAt path: String) throws -> URL {
        let key = try TranscriptCheckpointKey.transcriptKey(for: path)
        return cacheRoot.appendingPathComponent("\(key).json", isDirectory: false)
    }

    func loadCheckpoint(forTranscriptAt path: String) throws -> Data? {
        let url = try checkpointURL(forTranscriptAt: path)
        let descriptor = Darwin.open(
            url.path,
            O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            if errno == ELOOP {
                throw TranscriptCheckpointStoreError.invalidEntry
            }
            throw TranscriptCheckpointStoreError.unavailable
        }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var initialStatus = stat()
        guard fstat(descriptor, &initialStatus) == 0 else {
            throw TranscriptCheckpointStoreError.unavailable
        }
        guard (initialStatus.st_mode & S_IFMT) == S_IFREG,
              initialStatus.st_size > 0,
              initialStatus.st_size <= Self.maximumEntryBytes
        else {
            throw TranscriptCheckpointStoreError.invalidEntry
        }

        let expectedCount = Int(initialStatus.st_size)
        var data = Data()
        data.reserveCapacity(expectedCount)
        do {
            while data.count < expectedCount {
                guard let chunk = try handle.read(
                    upToCount: min(1 << 20, expectedCount - data.count)
                ),
                chunk.isEmpty == false
                else {
                    throw TranscriptCheckpointStoreError.invalidEntry
                }
                data.append(chunk)
            }
            if let extra = try handle.read(upToCount: 1), extra.isEmpty == false {
                throw TranscriptCheckpointStoreError.invalidEntry
            }
        } catch let error as TranscriptCheckpointStoreError {
            throw error
        } catch {
            throw TranscriptCheckpointStoreError.unavailable
        }

        var finalStatus = stat()
        guard fstat(descriptor, &finalStatus) == 0 else {
            throw TranscriptCheckpointStoreError.unavailable
        }
        guard finalStatus.st_dev == initialStatus.st_dev,
              finalStatus.st_ino == initialStatus.st_ino,
              finalStatus.st_size == initialStatus.st_size,
              finalStatus.st_mtimespec.tv_sec == initialStatus.st_mtimespec.tv_sec,
              finalStatus.st_mtimespec.tv_nsec == initialStatus.st_mtimespec.tv_nsec
        else {
            throw TranscriptCheckpointStoreError.invalidEntry
        }
        return data
    }

    func publishCheckpoint(_ data: Data, forTranscriptAt path: String) throws {
        guard data.isEmpty == false, data.count <= Self.maximumEntryBytes else {
            throw TranscriptCheckpointStoreError.invalidEntry
        }

        let destination = try checkpointURL(forTranscriptAt: path)
        try publicationFault?(.createDirectory)
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
            try publicationFault?(.openTemporary)
            let descriptor = Darwin.open(
                temporary.path,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
                mode_t(S_IRUSR | S_IWUSR)
            )
            guard descriptor >= 0 else {
                throw currentPOSIXError()
            }

            let opened = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            handle = opened
            try publicationFault?(.write)
            try opened.write(contentsOf: data)
            try publicationFault?(.synchronize)
            try opened.synchronize()
            try opened.close()
            handle = nil

            try publicationFault?(.replace)
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
        guard Darwin.unlink(url.path) == 0 else {
            if errno == ENOENT { return }
            throw TranscriptCheckpointStoreError.unavailable
        }
    }
}

nonisolated private func currentPOSIXError() -> POSIXError {
    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
}
