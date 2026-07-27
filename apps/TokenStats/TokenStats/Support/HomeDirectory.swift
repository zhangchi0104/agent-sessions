//
//  HomeDirectory.swift
//  TokenStats
//
//  Where on disk TokenStats looks for the Coding Agents' own files. Only the
//  home directory itself lives here; which subdirectory each agent uses is the
//  agent's business, not this file's.
//

import Foundation

/// The user's *real* home directory, where the Coding Agents write their
/// transcripts. TokenStats is a non-sandboxed Developer ID app and reads those
/// paths directly, with no entitlement — and must keep it that way: any
/// restricted entitlement, App Sandbox temporary-exceptions included, makes the
/// kernel SIGKILL the app at launch. See ADR-0004 and TokenStats.entitlements.
///
/// `NSHomeDirectory()` is the fallback rather than the answer because it points
/// at the container for a sandboxed process, which this app is not, but may be
/// under a future host that runs it sandboxed.
func realHomeDirectory() -> String {
    if let passwd = getpwuid(getuid()), let dir = passwd.pointee.pw_dir {
        return String(cString: dir)
    }
    return NSHomeDirectory()
}
