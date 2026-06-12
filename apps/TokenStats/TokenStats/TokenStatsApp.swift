//
//  TokenStatsApp.swift
//  TokenStats
//
//  Menu-bar-only app (LSUIElement, set in the generated Info.plist — no Dock
//  icon). The label shows each signed-in Coding Agent's primary (5-hour) Usage
//  Window percent — a single percent when only one is available, or compact
//  side-by-side readings (e.g. "C: 24% X: 12%") when both are. Clicking opens
//  the popover anchored to it.
//

import SwiftUI

enum TokenStatsWindowID {
    static let settings = "settings"
}

@main
struct TokenStatsApp: App {
    private let model = UsageModel(appearance: AppearanceSettings())
    private let sessionsModel: SessionsModel
    private let tokensTodayModel: TokensTodayModel

    init() {
        // One reader shared by both models, so a transcript parsed for the
        // Sessions tab doesn't get re-parsed for the tokens-today figure.
        let tokenReader = TranscriptTokenReader()
        sessionsModel = SessionsModel(tokenReader: tokenReader)
        tokensTodayModel = TokensTodayModel(reader: tokenReader)
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model,
                        sessionsModel: sessionsModel,
                        tokensTodayModel: tokensTodayModel)
        } label: {
            // Monochrome icon + per-agent percent — no threshold colors (PRD).
            Image(systemName: "gauge.with.dots.needle.33percent")
            Text(MenuBarSummary.text(for: model.menuBarSummaries))
        }
        .menuBarExtraStyle(.window)

        // The dedicated settings window for managing accounts. It uses a named
        // Window so the menu-bar popover and Command-comma can target the same
        // native Settings surface.
        Window("Settings", id: TokenStatsWindowID.settings) {
            SettingsView(model: model)
        }
        .defaultSize(width: 700, height: 380)
        .windowResizability(.contentMinSize)
        // Full-size content with no opaque title strip, so the sidebar runs to
        // the top of the window and the traffic lights float over it.
        .windowStyle(.hiddenTitleBar)
        .commands {
            TokenStatsCommands()
        }
    }
}

struct TokenStatsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                PopoverView.openSettingsWindow(openWindow)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
