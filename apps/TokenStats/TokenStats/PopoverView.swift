//
//  PopoverView.swift
//  TokenStats
//
//  The popover anchored to the menu-bar item: a glass tab bar switching
//  between the Usage tab (the combined tokens-today hero, then one
//  AgentSection per Coding Agent in the user's Appearance order, primary
//  first) and the Sessions tab, plus a single Settings control in the footer
//  that manages every account (sign in / sign out per agent), a global
//  refresh control, and Quit. All copy follows the glossary (Usage Window,
//  never "session"; full agent names in the popover).
//

import SwiftUI
import AppKit

struct PopoverView: View {
    let model: UsageModel
    let sessionsModel: SessionsModel
    let tokensTodayModel: TokensTodayModel
    @Environment(\.openWindow) private var openWindow
    @State private var tab: PopoverTab = .usage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            GlassTabBar(selection: $tab)

            switch tab {
            case .usage:
                usage
            case .sessions:
                SessionsView(model: sessionsModel)
            }

            Divider()
            HStack {
                Spacer()
                settings
            }
        }
        .padding(16)
        // A touch wider than the old 308 so the one-step-larger type keeps
        // the same breathing room per line.
        .frame(width: 332)
    }

    /// The Usage tab: the combined tokens-today figure (every Coding Agent)
    /// on top, then one section per agent in the user's display order.
    @ViewBuilder private var usage: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let usage = tokensTodayModel.usage {
                TokensTodayHero(usage: usage, perAgent: tokensTodayModel.perAgent)
            }
            ForEach(Array(model.appearance.displayOrder.enumerated()), id: \.element) { index, id in
                if index > 0 { Divider() }
                AgentSection(model: model, id: id)
            }
        }
        // Watches transcripts only while the Usage tab shows the figure;
        // SwiftUI cancels this when the tab (or popover) goes away.
        .task { await tokensTodayModel.observeWhileVisible() }
    }

    /// Footer menu: open the dedicated Settings page (account management) or quit.
    private var settings: some View {
        Menu {
            Button("Settings…") { Self.openSettingsWindow(openWindow) }
            Divider()
            Button("Quit TokenStats") { model.quit() }
        } label: {
            Image(systemName: "gearshape")
                .imageScale(.large)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Settings")
        .accessibilityLabel("Settings")
    }

    /// Open the Settings window and pull it to the front. The extra `activate`
    /// is needed because TokenStats is an LSUIElement (menu-bar-only) app, so
    /// its windows don't come forward — or take focus — on their own.
    static func openSettingsWindow(_ openWindow: OpenWindowAction) {
        openWindow(id: TokenStatsWindowID.settings)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("TokenStats").font(.title3.weight(.semibold))
            Spacer()
            Button {
                switch tab {
                case .usage: model.refreshAllManually()
                case .sessions: Task { await sessionsModel.refresh() }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            // ⌘R refreshes whichever tab is visible while the popover is up.
            .keyboardShortcut("r", modifiers: .command)
            .help(tab == .usage ? "Refresh all (⌘R)" : "Refresh sessions (⌘R)")
        }
    }
}
