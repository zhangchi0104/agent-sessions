//
//  HomeDirectory.swift
//  TokenStats
//
//  Where on disk TokenStats looks for the Coding Agents' own files. Only the
//  home directory itself lives here; which subdirectory each agent uses is the
//  agent's business, not this file's.
//

import Foundation

/// The user's *real* home directory. Inside the App Sandbox,
/// `NSHomeDirectory()` points at the container, while the Coding Agents write
/// their transcripts under the actual home — which the entitlements'
/// home-relative exceptions grant us read access to.
///
/// `nonisolated` because callers resolve scan roots off the main actor; the
/// target defaults to `MainActor` isolation, which a bare global would inherit.
nonisolated func realHomeDirectory() -> String {
    if let passwd = getpwuid(getuid()), let dir = passwd.pointee.pw_dir {
        return String(cString: dir)
    }
    return NSHomeDirectory()
}
