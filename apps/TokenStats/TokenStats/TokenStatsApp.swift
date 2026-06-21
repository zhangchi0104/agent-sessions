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
//  The app's long-lived models live on an AppDelegate rather than the App struct
//  so the same instances can be shared with the AppKit-hosted onboarding window
//  and presented on first launch (see OnboardingWindowController).
//

import SwiftUI
import AppKit

enum TokenStatsWindowID {
    static let settings = "settings"
}

@main
struct TokenStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: appDelegate.model,
                        sessionsModel: appDelegate.sessionsModel,
                        tokensTodayModel: appDelegate.tokensTodayModel)
        } label: {
            // Monochrome icon + per-agent percent — no threshold colors (PRD).
            Image(systemName: "gauge.with.dots.needle.33percent")
            Text(MenuBarSummary.text(for: appDelegate.model.menuBarSummaries))
        }
        .menuBarExtraStyle(.window)

        // The dedicated settings window for managing accounts. It uses a named
        // Window so the menu-bar popover and Command-comma can target the same
        // native Settings surface.
        Window("Settings", id: TokenStatsWindowID.settings) {
            SettingsView(model: appDelegate.model,
                         onRunSetupAgain: { appDelegate.showOnboarding() })
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

/// Owns the app's long-lived models and the onboarding window. As an
/// `@NSApplicationDelegateAdaptor`, it's created before the scenes, so the App
/// struct reads its models when building them.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: UsageModel
    let sessionsModel: SessionsModel
    let tokensTodayModel: TokensTodayModel
    let onboarding = OnboardingSettings()
    private var onboardingController: OnboardingWindowController?

    override init() {
        // One reader shared by both models, so a transcript parsed for the
        // Sessions tab doesn't get re-parsed for the tokens-today figure.
        let tokenReader = TranscriptTokenReader()
        model = UsageModel(appearance: AppearanceSettings())
        sessionsModel = SessionsModel(tokenReader: tokenReader)
        tokensTodayModel = TokensTodayModel(reader: tokenReader)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        if !onboarding.completed { showOnboarding() }
    }

    /// Present (or re-present) the first-run onboarding flow. Reused for both the
    /// automatic first-launch prompt and the "Run setup again" action in Settings.
    func showOnboarding() {
        if onboardingController == nil {
            onboardingController = OnboardingWindowController(model: model, onboarding: onboarding)
        }
        onboardingController?.show()
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
