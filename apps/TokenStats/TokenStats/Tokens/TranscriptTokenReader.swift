//
//  TranscriptTokenReader.swift
//  TokenStats
//
//  Coordinates transcript discovery and process-local per-file state. The
//  atomic file read, checkpoint transaction, and JSONL parsing live behind
//  TranscriptFileReader so this actor owns only collection-level policy.
//

import Foundation

/// Parses transcripts off the main actor and remembers the last stable state
/// for each file, so each poll pays only for newly appended bytes.
actor TranscriptTokenReader {
    private struct CachedFile {
        let parsed: TranscriptFileState
        let lastAccessed: Date
    }

    private var states: [String: CachedFile] = [:]
    private(set) var statistics = TranscriptReadStatistics()
    private let fileReader: TranscriptFileReader
    private let nowProvider: @Sendable () -> Date
    private let dayKeyFormatter: DateFormatter

    init(
        checkpointStore: (any TranscriptCheckpointStoring)? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        timeZone: TimeZone = .current
    ) {
        fileReader = TranscriptFileReader(
            checkpointStore: checkpointStore,
            timeZone: timeZone
        )
        nowProvider = now

        // Day keys are internal identifiers, never shown: locale and calendar
        // are pinned so a non-Gregorian system calendar cannot change them.
        dayKeyFormatter = DateFormatter()
        dayKeyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayKeyFormatter.calendar = Calendar(identifier: .gregorian)
        dayKeyFormatter.dateFormat = "yyyy-MM-dd"
        dayKeyFormatter.timeZone = timeZone
    }

    /// Token usage recorded within `range` (local time) as of `now`, per Model,
    /// across every agent .jsonl under `root`.
    ///
    /// `now` is passed in so every Coding Agent in one refresh uses the same
    /// range, even when a scan straddles local midnight.
    func breakdown(
        underTranscriptRoot root: String,
        range: TokenRange,
        now: Date
    ) -> [ModelName: TokenUsage] {
        let rangeStart = range.start(from: now)
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return [:]
        }

        let dayKeys = Set((0..<range.days).compactMap { offset in
            Calendar.current.date(
                byAdding: .day,
                value: offset,
                to: rangeStart
            ).map(dayKeyFormatter.string)
        })
        var inRange: [ModelName: TokenUsage] = [:]
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  let modificationDate = try? url.resourceValues(
                      forKeys: [.contentModificationDateKey]
                  ).contentModificationDate,
                  modificationDate >= rangeStart
            else {
                continue
            }

            // A large first read is chunked. A local autorelease pool prevents
            // a long range scan from retaining every chunk until enumeration
            // completes.
            autoreleasepool {
                _ = readTranscript(at: url.path)
            }
            guard let parsed = states[url.path]?.parsed else {
                continue
            }
            for (model, usage) in parsed.breakdown(forDayKeys: dayKeys) {
                inRange[model, default: TokenUsage()].add(usage)
            }
        }
        evictStaleStates()
        return inRange.filter { $0.value.responseCount > 0 }
    }

    /// Totals for the transcript at `path`, or nil when the file is missing or
    /// holds no usage entries.
    func usage(forTranscriptAt path: String) -> TokenUsage? {
        readTranscript(at: path).usage
    }

    /// Reads one transcript and reports both its totals and deterministic work.
    /// A file transition is committed to process state only after its source
    /// has remained stable for the complete read.
    func readTranscript(at path: String) -> TranscriptReadResult {
        let transition = fileReader.read(
            at: path,
            resuming: states[path]?.parsed
        )
        if let parsed = transition.nextState {
            states[path] = CachedFile(
                parsed: parsed,
                lastAccessed: nowProvider()
            )
        } else {
            states[path] = nil
        }
        statistics.add(transition.result.statistics)
        return transition.result
    }

    /// Parse state for files nothing has read in days is archaeology. This
    /// process runs for weeks, and response-id sets dominate the retained size.
    private func evictStaleStates() {
        let cutoff = nowProvider().addingTimeInterval(-48 * 60 * 60)
        states = states.filter { $0.value.lastAccessed > cutoff }
    }
}
