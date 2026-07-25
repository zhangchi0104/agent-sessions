//
//  HookInstaller.swift
//  TokenStats
//
//  Installs the session-tracking hook for Claude Code on the user's behalf, so
//  they don't have to run any /plugin commands. TokenStats is non-sandboxed
//  (ADR-0004), so it edits ~/.claude/settings.json directly. The hook CLI ships
//  inside the app bundle and is copied to a stable, home-relative path at install
//  time — the hooks reference that copy, not the app bundle, so they survive the
//  app being moved or deleted. The command is guarded with `|| true` so a missing
//  CLI can never block an agent.
//
//  Codex hooks are NOT installed here: Codex only loads hooks through its
//  plugin-marketplace config, whose format isn't verified, so onboarding keeps
//  guided instructions for Codex (see OnboardingView).
//

import Foundation

enum HookInstaller {
    enum InstallError: LocalizedError {
        case bunNotFound
        case cliResourceMissing
        case settingsUnreadable(String)
        case io(String)

        var errorDescription: String? {
            switch self {
            case .bunNotFound:
                return "Couldn't find bun, which the hooks run on. Install it from bun.sh, then try again."
            case .cliResourceMissing:
                return "TokenStats is missing its bundled tracking helper. Reinstalling the app should fix it."
            case .settingsUnreadable(let path):
                return "Couldn't parse \(path) as JSON. Fix any syntax error there, then try again."
            case .io(let message):
                return message
            }
        }
    }

    // MARK: - Paths

    private nonisolated static var home: String { SessionStore.realHomeDirectory() }

    /// Stable location the installed hooks invoke the CLI from — deliberately
    /// outside the app bundle so the hooks keep working if the app moves.
    nonisolated static var installedCLIPath: String {
        home + "/.local/agent-sessions/bin/agent-sessions-cli.js"
    }

    private nonisolated static var claudeSettingsPath: String { home + "/.claude/settings.json" }

    /// Substring tagging the hook commands we write, so we can find and remove
    /// only our own entries without disturbing the user's other hooks. Specific
    /// enough not to match the plugin's own `.../bin/agent-sessions-cli.js`.
    private nonisolated static let marker = "agent-sessions/bin/agent-sessions-cli.js"

    /// Claude Code hook events and matchers — mirrors the plugin's hooks.json.
    private nonisolated static let claudeEvents: [(event: String, matcher: String)] = [
        ("SessionStart", ""),
        ("UserPromptSubmit", ""),
        ("PreToolUse", ".*"),
        ("PostToolUse", ".*"),
        ("PermissionRequest", ".*"),
        ("Notification", ""),
        ("Stop", ""),
        ("SessionEnd", ""),
    ]

    // MARK: - Status

    /// Whether `bun` can be located (hooks can't run without it).
    nonisolated static func bunAvailable() -> Bool { findBun() != nil }

    /// Whether our Claude Code hooks are already present in the user's settings.
    nonisolated static func isClaudeInstalled() -> Bool {
        guard let settings = try? readJSONObject(at: claudeSettingsPath),
              let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            (value as? [[String: Any]])?.contains(where: groupIsOurs) ?? false
        }
    }

    // MARK: - Install / uninstall

    /// Copy the bundled CLI to its stable home and merge our hook entries into
    /// the user's Claude Code settings. Idempotent: re-running replaces our own
    /// entries and leaves everything else untouched.
    nonisolated static func installClaude() throws {
        guard let bun = findBun() else { throw InstallError.bunNotFound }
        let cli = try installCLIBundle()
        let settings = try readJSONObject(at: claudeSettingsPath) ?? [:]
        try writeJSONObject(applyClaudeHooks(to: settings, bun: bun, cli: cli), to: claudeSettingsPath)
    }

    /// Remove only our hook entries (and any now-empty event arrays / hooks key).
    nonisolated static func uninstallClaude() throws {
        guard let settings = try readJSONObject(at: claudeSettingsPath) else { return }
        try writeJSONObject(removeClaudeHooks(from: settings), to: claudeSettingsPath)
    }

    // MARK: - Pure merge (unit-tested)

    /// Merge our hook entries into a Claude settings object. Pure and idempotent:
    /// replaces any of our own previous entries and preserves all other settings
    /// and the user's own hooks. The `cli` path must contain `marker`.
    nonisolated static func applyClaudeHooks(to settings: [String: Any],
                                             bun: String, cli: String) -> [String: Any] {
        var settings = settings
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, matcher) in claudeEvents {
            var groups = (hooks[event] as? [[String: Any]] ?? []).filter { !groupIsOurs($0) }
            groups.append([
                "matcher": matcher,
                "hooks": [[
                    "type": "command",
                    "command": "\(shellQuote(bun)) \(shellQuote(cli)) claude \(event) || true",
                ]],
            ])
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        return settings
    }

    /// Remove our hook entries from a Claude settings object, dropping any event
    /// arrays (and the `hooks` key itself) left empty. Pure; preserves everything else.
    nonisolated static func removeClaudeHooks(from settings: [String: Any]) -> [String: Any] {
        var settings = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = groups.filter { !groupIsOurs($0) }
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        if hooks.isEmpty { settings.removeValue(forKey: "hooks") } else { settings["hooks"] = hooks }
        return settings
    }

    // MARK: - Codex (inline [hooks] in ~/.codex/config.toml)

    // Codex discovers inline [hooks] directly from config.toml (verified against
    // openai/codex `main`). We write a clearly delimited, managed block so we can
    // add/remove it by text without a full TOML parser. NOTE: Codex marks freshly
    // written command hooks as untrusted — the user must approve them once in
    // Codex's startup review before they fire (surfaced in onboarding copy).

    private nonisolated static var codexConfigPath: String { home + "/.codex/config.toml" }
    private nonisolated static let codexBeginMarker = "# >>> TokenStats agent-sessions hooks (managed) >>>"
    private nonisolated static let codexEndMarker = "# <<< TokenStats agent-sessions hooks (managed) <<<"

    /// Codex hook events + matchers (source-verified: no Notification event in
    /// Codex; it has SubagentStop instead).
    private nonisolated static let codexEvents: [(event: String, matcher: String)] = [
        ("SessionStart", "startup|resume|clear"),
        ("UserPromptSubmit", ""),
        ("PreToolUse", ".*"),
        ("PostToolUse", ".*"),
        ("Stop", ""),
        ("SubagentStop", ""),
    ]

    nonisolated static func isCodexInstalled() -> Bool {
        guard let text = try? readText(at: codexConfigPath) else { return false }
        return text.contains(codexBeginMarker)
    }

    nonisolated static func installCodex() throws {
        guard let bun = findBun() else { throw InstallError.bunNotFound }
        let cli = try installCLIBundle()
        let existing = (try? readText(at: codexConfigPath)) ?? ""
        try writeText(applyingCodexBlock(to: existing, bun: bun, cli: cli), to: codexConfigPath)
    }

    nonisolated static func uninstallCodex() throws {
        guard let existing = try? readText(at: codexConfigPath) else { return }
        try writeText(removingCodexBlock(from: existing), to: codexConfigPath)
    }

    /// Pure: replace any existing managed block and append a fresh one, keeping
    /// the rest of the file untouched. Exposed for unit tests.
    nonisolated static func applyingCodexBlock(to existing: String, bun: String, cli: String) -> String {
        let cleaned = removingCodexBlock(from: existing)
        let block = codexHooksBlock(bun: bun, cli: cli)
        if cleaned.isEmpty { return block + "\n" }
        return cleaned + "\n\n" + block + "\n"
    }

    /// Pure: drop our managed block (the marker lines and everything between),
    /// trimming any trailing blank lines left behind. Exposed for unit tests.
    nonisolated static func removingCodexBlock(from text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard let begin = lines.firstIndex(where: { $0.contains(codexBeginMarker) }),
              let end = lines.firstIndex(where: { $0.contains(codexEndMarker) }),
              begin <= end else { return text }
        var kept = Array(lines[..<begin]) + Array(lines[(end + 1)...])
        while kept.last?.isEmpty == true { kept.removeLast() }
        return kept.joined(separator: "\n")
    }

    private nonisolated static func codexHooksBlock(bun: String, cli: String) -> String {
        var lines = [
            codexBeginMarker,
            "# Managed by TokenStats. Approve these hooks once in Codex when it prompts you.",
        ]
        for (event, matcher) in codexEvents {
            lines.append("")
            lines.append("[[hooks.\(event)]]")
            if !matcher.isEmpty { lines.append("matcher = \(tomlString(matcher))") }
            lines.append("")
            lines.append("  [[hooks.\(event).hooks]]")
            lines.append("  type = \"command\"")
            lines.append("  command = \(tomlString("\(bun) \(cli) codex \(event)"))")
        }
        lines.append("")
        lines.append(codexEndMarker)
        return lines.joined(separator: "\n")
    }

    private nonisolated static func tomlString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: - bun discovery

    /// Locate the `bun` executable. Checks common install locations first, then
    /// falls back to a login shell so version-manager installs (mise, asdf, …)
    /// that only set PATH in shell startup files are still found.
    private nonisolated static func findBun() -> String? {
        let candidates = [
            home + "/.bun/bin/bun",
            "/opt/homebrew/bin/bun",
            "/usr/local/bin/bun",
            home + "/.local/bin/bun",
            home + "/.local/share/mise/shims/bun",
            home + "/.asdf/shims/bun",
            "/run/current-system/sw/bin/bun",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        if let resolved = loginShellResolve("bun"),
           FileManager.default.isExecutableFile(atPath: resolved) {
            return resolved
        }
        return nil
    }

    private nonisolated static func loginShellResolve(_ tool: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Login + interactive so the user's PATH (set in ~/.zprofile / ~/.zshrc)
        // is loaded the same way it is for a normal terminal session.
        process.arguments = ["-lic", "command -v \(tool)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            // Interactive shells emit prompt/terminal escape sequences (e.g. the
            // OSC `]7;file://…` cwd report) onto stdout. Split on every control
            // character so those land on their own lines, then keep the last line
            // that's an absolute path to the tool.
            let normalized = String(decoding: data, as: UTF8.self)
                .map { $0.isASCII && ($0.asciiValue ?? 0) < 0x20 ? "\n" : $0 }
            return String(normalized)
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .last { $0.hasPrefix("/") && $0.hasSuffix("/\(tool)") }
        } catch {
            return nil
        }
    }

    // MARK: - CLI bundle

    private nonisolated static func installCLIBundle() throws -> String {
        guard let source = Bundle.main.url(forResource: "agent-sessions-cli", withExtension: "js") else {
            throw InstallError.cliResourceMissing
        }
        let destination = URL(fileURLWithPath: installedCLIPath)
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw InstallError.io("Couldn't copy the tracking helper to \(installedCLIPath): "
                                  + error.localizedDescription)
        }
        return installedCLIPath
    }

    // MARK: - JSON helpers

    private nonisolated static func groupIsOurs(_ group: [String: Any]) -> Bool {
        guard let hooks = group["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { ($0["command"] as? String)?.contains(marker) ?? false }
    }

    /// Returns nil when the file doesn't exist (a fresh start); throws when it
    /// exists but isn't valid JSON, so we never clobber a file we can't parse.
    private nonisolated static func readJSONObject(at path: String) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard !data.isEmpty else { return nil }
        let parsed = try? JSONSerialization.jsonObject(with: data)
        guard let object = parsed as? [String: Any] else {
            throw InstallError.settingsUnreadable(path)
        }
        return object
    }

    private nonisolated static func writeJSONObject(_ object: [String: Any], to path: String) throws {
        // Follow a symlinked settings.json (e.g. one managed in a dotfiles repo)
        // and write to its target, so an atomic write doesn't replace the symlink
        // with a plain file and detach it from the repo.
        let url = URL(fileURLWithPath: resolvingSymlink(path))
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: url, options: .atomic)
        } catch {
            throw InstallError.io("Couldn't write \(path): \(error.localizedDescription)")
        }
    }

    /// The destination of `path` if it's a symlink (resolving a relative target
    /// against the link's directory), otherwise `path` unchanged.
    private nonisolated static func resolvingSymlink(_ path: String) -> String {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else {
            return path
        }
        if destination.hasPrefix("/") { return destination }
        return URL(fileURLWithPath: path)
            .deletingLastPathComponent()
            .appendingPathComponent(destination)
            .standardizedFileURL.path
    }

    private nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private nonisolated static func readText(at path: String) throws -> String {
        try String(contentsOfFile: resolvingSymlink(path), encoding: .utf8)
    }

    /// Atomic, symlink-preserving text write (mirrors writeJSONObject's handling
    /// of a dotfiles-managed config).
    private nonisolated static func writeText(_ text: String, to path: String) throws {
        let url = URL(fileURLWithPath: resolvingSymlink(path))
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            throw InstallError.io("Couldn't write \(path): \(error.localizedDescription)")
        }
    }
}
