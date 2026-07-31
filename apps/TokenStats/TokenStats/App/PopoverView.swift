//
//  PopoverView.swift
//  TokenStats
//
//  The popover anchored to the menu-bar item: a glass tab bar switching
//  between the Usage tab (one AgentSection per Coding Agent in the user's
//  Appearance order, primary first) and the Tokens tab (the Token Odometer
//  broken down by Coding Agent, Model and Token Kind). The Tokens tab keeps
//  itself current from a file watch, so the header's refresh control reaches
//  the Usage Windows only. The footer carries that refresh control and a single
//  Settings control that reaches account management (sign in / sign out per
//  agent) and Quit. All copy follows the glossary (Usage Window, never
//  "session"; full agent names in the popover).
//

import SwiftUI
import AppKit

struct PopoverView: View {
    let model: UsageModel
    let odometer: TokenOdometerModel
    @Environment(\.openWindow) private var openWindow
    @State private var tab: PopoverTab = .usage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            GlassTabBar(selection: $tab)

            switch tab {
            case .usage:
                usage
            case .tokens:
                TokensTabView(odometer: odometer, appearance: model.appearance)
                    .onAppear { odometer.displayOrder = model.appearance.displayOrder }
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

    /// The Usage tab: one section per Coding Agent in the user's display
    /// order. Usage Window gauges and nothing else.
    @ViewBuilder private var usage: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(model.appearance.displayOrder.enumerated()), id: \.element) { index, id in
                if index > 0 { Divider() }
                AgentSection(model: model, id: id)
            }
        }
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
                model.refreshAllManually()
                // The Tokens tab keeps itself current from a file watch, so
                // this is belt and braces — but "Refresh all" should reach
                // everything on screen. Only while that tab is the visible
                // one: re-reading transcripts for an off-screen figure is the
                // thing ADR-0003 exists to prevent.
                if tab == .tokens { Task { await odometer.refresh() } }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            // ⌘R refreshes every Coding Agent while the popover is up.
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh all (⌘R)")
        }
    }
}
