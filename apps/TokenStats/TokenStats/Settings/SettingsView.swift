//
//  SettingsView.swift
//  TokenStats
//
//  The dedicated Settings page (the native ⌘, window): a sidebar of sections
//  with a detail pane, drawn in the System Settings idiom. This file is the
//  shell only — each section's pane lives beside it in its own file.
//

import SwiftUI
import AppKit

/// The top-level Settings window: a sidebar of sections with a detail pane.
struct SettingsView: View {
    let model: UsageModel
    /// Re-presents the first-run onboarding flow (the About pane's "Run setup
    /// again"). Defaults to a no-op so previews and tests can omit it.
    var onRunSetupAgain: () -> Void = {}
    @State private var selection: SettingsSection? = .accounts
    private static let sidebarWidth: CGFloat = 218

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: Self.sidebarWidth, max: 240)
                // The collapse toggle (and its trailing toolbar divider) sits to
                // the right of the sidebar edge and reads as a misaligned
                // separator; a Settings sidebar never needs to collapse, so drop it.
                .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch selection ?? .accounts {
                case .accounts: AccountsPane(model: model)
                case .appearance: AppearancePane(appearance: model.appearance)
                case .about: AboutPane(onRunSetupAgain: onRunSetupAgain)
                }
            }
            // Pin the detail column's size so a greedy detail pane (e.g. the
            // centered About content) can't starve the sidebar column at
            // render time — which previously blanked the sidebar labels.
            .frame(minWidth: 462, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .background(SettingsWindowChrome())
        // A minimum keeps the two columns legible; a flexible maximum lets the
        // user resize the window freely (an exact width/height would pin it).
        .frame(minWidth: 700, idealWidth: 700, maxWidth: .infinity,
               minHeight: 380, idealHeight: 380, maxHeight: .infinity)
    }

    // The native System Settings sidebar: a standard `.sidebar` list whose rows
    // pair a colored rounded-square icon badge with the section title, and whose
    // selection uses the system's own accent highlight. Letting the platform
    // draw it keeps us in lock-step with whatever treatment the OS applies
    // (including macOS 26 Liquid Glass) — no bespoke selection to maintain.
    private var sidebar: some View {
        List(SettingsSection.allCases, selection: $selection) { section in
            Label {
                Text(section.title)
            } icon: {
                SettingsRowIcon(systemName: section.icon, tint: section.tint)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.bar)
    }
}

/// Forces the Settings window into the full-size-content chrome that native
/// System Settings uses: the title strip disappears and the traffic lights sit
/// over the sidebar material.
private struct SettingsWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
    }
}

/// The colored rounded-square icon badge that fronts each sidebar row, matching
/// System Settings: a white SF Symbol centered on a tinted, continuous-corner
/// rounded rectangle.
private struct SettingsRowIcon: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
