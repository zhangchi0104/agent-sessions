//
//  HookInstallerTests.swift
//  TokenStatsTests
//
//  Exercises the pure Claude Code settings merge in HookInstaller: it must add
//  our hooks, preserve everything else the user has, stay idempotent, and remove
//  cleanly. The file I/O, bun discovery, and symlink handling are integration
//  concerns left out here; the merge is where the real logic risk lives.
//

import Testing
import Foundation
@testable import TokenStats

struct HookInstallerTests {
    private let bun = "/opt/homebrew/bin/bun"
    private let cli = "/Users/test/.local/agent-sessions/bin/agent-sessions-cli.js"

    /// Every command string across all hook groups, flattened.
    private func commands(in settings: [String: Any]) -> [String] {
        guard let hooks = settings["hooks"] as? [String: Any] else { return [] }
        return hooks.values.flatMap { value -> [String] in
            (value as? [[String: Any]] ?? []).flatMap { group in
                (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
            }
        }
    }

    private func ourCommands(in settings: [String: Any]) -> [String] {
        commands(in: settings).filter { $0.contains("agent-sessions/bin/agent-sessions-cli.js") }
    }

    @Test func installsAHookForEveryEvent() {
        let result = HookInstaller.applyClaudeHooks(to: [:], bun: bun, cli: cli)
        let hooks = result["hooks"] as? [String: Any]

        // One event key per supported Claude Code event, each carrying our command.
        #expect(hooks?.count == 8)
        for event in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                      "PermissionRequest", "Notification", "Stop", "SessionEnd"] {
            #expect(hooks?[event] != nil)
        }
        #expect(ourCommands(in: result).count == 8)
        // The command references both our CLI and the resolved bun, and won't block.
        #expect(ourCommands(in: result).allSatisfy { $0.contains(cli) && $0.contains(bun) && $0.hasSuffix("|| true") })
    }

    @Test func preservesUnrelatedSettingsAndHooks() {
        let existing: [String: Any] = [
            "model": "opus",
            "hooks": [
                "PreToolUse": [[
                    "matcher": "Bash",
                    "hooks": [["type": "command", "command": "/usr/bin/true"]],
                ]],
            ],
        ]
        let result = HookInstaller.applyClaudeHooks(to: existing, bun: bun, cli: cli)

        // Untouched top-level key survives.
        #expect(result["model"] as? String == "opus")
        // The user's own PreToolUse hook is still present alongside ours.
        let preToolUse = (result["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]]
        #expect(preToolUse?.count == 2)
        #expect(commands(in: result).contains("/usr/bin/true"))
    }

    @Test func reinstallIsIdempotent() {
        let once = HookInstaller.applyClaudeHooks(to: [:], bun: bun, cli: cli)
        let twice = HookInstaller.applyClaudeHooks(to: once, bun: bun, cli: cli)
        // Re-running replaces our entries rather than stacking duplicates.
        #expect(ourCommands(in: twice).count == 8)
    }

    @Test func uninstallRemovesOnlyOurEntries() {
        let withUserHook: [String: Any] = [
            "model": "opus",
            "hooks": [
                "PreToolUse": [[
                    "matcher": "Bash",
                    "hooks": [["type": "command", "command": "/usr/bin/true"]],
                ]],
            ],
        ]
        let installed = HookInstaller.applyClaudeHooks(to: withUserHook, bun: bun, cli: cli)
        let removed = HookInstaller.removeClaudeHooks(from: installed)

        #expect(ourCommands(in: removed).isEmpty)
        #expect(removed["model"] as? String == "opus")
        // The user's PreToolUse hook remains; events that were only ours are gone.
        let preToolUse = (removed["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]]
        #expect(preToolUse?.count == 1)
        #expect((removed["hooks"] as? [String: Any])?["SessionStart"] == nil)
    }

    @Test func uninstallDropsHooksKeyWhenNothingRemains() {
        let installed = HookInstaller.applyClaudeHooks(to: [:], bun: bun, cli: cli)
        let removed = HookInstaller.removeClaudeHooks(from: installed)
        // Nothing but our hooks existed, so the whole hooks key is cleaned up.
        #expect(removed["hooks"] == nil)
    }

    // MARK: - Codex (inline [hooks] in config.toml)

    private let codexMarker = "# >>> TokenStats agent-sessions hooks (managed) >>>"

    @Test func codexBlockWritesCodexEvents() {
        let result = HookInstaller.applyingCodexBlock(to: "", bun: bun, cli: cli)
        #expect(result.contains("[[hooks.SessionStart]]"))
        #expect(result.contains("matcher = \"startup|resume|clear\""))
        #expect(result.contains("[[hooks.SubagentStop]]"))
        #expect(result.contains("codex SessionStart"))
        #expect(result.contains(cli))
        // Codex has no Notification event (that's a Claude Code event).
        #expect(!result.contains("[[hooks.Notification]]"))
    }

    @Test func codexPreservesExistingConfig() {
        let result = HookInstaller.applyingCodexBlock(to: "model = \"gpt-5\"\n", bun: bun, cli: cli)
        #expect(result.contains("model = \"gpt-5\""))
    }

    @Test func codexBlockRoundTrips() {
        let existing = "model = \"gpt-5\"\n\n[other]\nkey = 1\n"
        let installed = HookInstaller.applyingCodexBlock(to: existing, bun: bun, cli: cli)
        let removed = HookInstaller.removingCodexBlock(from: installed)
        #expect(removed.trimmingCharacters(in: .whitespacesAndNewlines)
                == existing.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test func codexReinstallIsIdempotent() {
        let once = HookInstaller.applyingCodexBlock(to: "x = 1\n", bun: bun, cli: cli)
        let twice = HookInstaller.applyingCodexBlock(to: once, bun: bun, cli: cli)
        let blocks = twice.components(separatedBy: codexMarker).count - 1
        #expect(blocks == 1)
    }
}
