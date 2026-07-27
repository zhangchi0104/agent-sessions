//
//  TranscriptChangeSource.swift
//  TokenStats
//
//  The file-watch seam behind the popover's Tokens Today refresh (ADR-0003):
//  a source that ticks whenever transcripts under the watched roots change, so
//  TokensTodayModel can re-read instead of polling on a timer. The real source
//  wraps FSEvents; tests inject a fake that ticks on demand.
//

import Foundation

/// Emits a tick whenever a watched transcript file changes. Iterating the
/// stream stops — and the underlying watch tears down — when the consuming task
/// is cancelled (i.e. when the popover closes).
protocol TranscriptChangeSource: Sendable {
    func ticks() -> AsyncStream<Void>
}

/// Real source: one FSEvents stream over the given roots, coalescing bursts of
/// appends via a ~1s latency so an active session triggers at most ~one
/// tick/second and an idle-but-open popover triggers none (ADR-0003). An
/// untested imperative shell over the C FSEvents API.
final class FSEventsTranscriptChangeSource: TranscriptChangeSource {
    private let paths: [String]

    init(paths: [String]) {
        self.paths = paths
    }

    func ticks() -> AsyncStream<Void> {
        let paths = paths
        return AsyncStream { continuation in
            guard !paths.isEmpty else { continuation.finish(); return }

            let box = ContinuationBox(continuation)
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(box).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
                guard let info else { return }
                Unmanaged<ContinuationBox>.fromOpaque(info).takeUnretainedValue().continuation.yield(())
            }
            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &context,
                paths as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                1.0, // coalescing latency, seconds
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
            ) else {
                continuation.finish()
                return
            }

            let queue = DispatchQueue(label: "dev.otakuma.TokenStats.transcript-watch")
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)

            continuation.onTermination = { _ in
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                _ = box // hold the callback's info box alive until the watch ends
            }
        }
    }

    /// Bridges the Swift continuation through FSEvents' opaque `info` pointer.
    private final class ContinuationBox {
        let continuation: AsyncStream<Void>.Continuation
        init(_ continuation: AsyncStream<Void>.Continuation) { self.continuation = continuation }
    }
}
