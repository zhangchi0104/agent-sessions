//
//  SettingsView.swift
//  TokenStats
//
//  The dedicated Settings page (the native ⌘, window). Its one job today is
//  Account management: connect or disconnect each Coding Agent and run the
//  sign-in flows that used to live inline in the popover. Tokens are stored in
//  TokenStats' own Keychain item (see docs/claude-code-integration.md).
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

/// The sidebar sections. Add a case here (plus a detail pane) to grow Settings.
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case accounts
    case appearance
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .accounts: return "Accounts"
        case .appearance: return "Appearance"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .accounts: return "person.crop.circle.fill"
        case .appearance: return "paintbrush.fill"
        case .about: return "info"
        }
    }

    /// The icon badge color, echoing System Settings' per-row tints.
    var tint: Color {
        switch self {
        case .accounts: return .blue
        case .appearance: return .purple
        case .about: return .gray
        }
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

/// Account management: connect or disconnect each Coding Agent.
private struct AccountsPane: View {
    let model: UsageModel

    var body: some View {
        Form {
            ForEach(model.appearance.displayOrder, id: \.self) { id in
                AccountSection(model: model, id: id)
            }

            // Descriptive copy reads as a caption below the account tiles
            // (a footer renders as plain secondary text), so it no longer
            // competes with the tappable account cards above it.
            Section {} footer: {
                Text("TokenStats stores each account's tokens in your Keychain "
                     + "and never sends them anywhere else.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Accounts")
    }
}

/// Appearance: pick the primary subscription, reorder agents, and choose how
/// each Usage Window is drawn. Edits write straight through to the persisted,
/// observable `AppearanceSettings`, so the popover updates live.
private struct AppearancePane: View {
    @Bindable var appearance: AppearanceSettings

    /// Reordering only changes anything with at least two *non-primary* agents
    /// to shuffle, since the primary is always hoisted first. With two agents
    /// total there's a single follower, so dragging is a no-op — we disable it
    /// and explain why rather than offer a control that does nothing.
    private var canReorder: Bool { appearance.order.count > 2 }

    var body: some View {
        Form {
            Section {
                Picker("Primary subscription", selection: $appearance.primaryAgent) {
                    ForEach(CodingAgentID.allCases, id: \.self) { id in
                        Text(id.displayName).tag(id)
                    }
                }
            } header: {
                Text("Primary")
            } footer: {
                Text("Your primary subscription is shown first and badged in the "
                     + "popover and menu bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                ForEach(appearance.order, id: \.self) { id in
                    OrderRow(appearance: appearance, id: id, draggable: canReorder)
                }
                .onMove(perform: canReorder ? { source, destination in
                    appearance.move(fromOffsets: source, toOffset: destination)
                } : nil)
            } header: {
                Text("Order")
            } footer: {
                Text(canReorder
                     ? "Drag to arrange how subscriptions are listed. The primary "
                       + "subscription always leads."
                     : "Nothing to arrange yet — your primary leads and the only "
                       + "other subscription follows. Drag-to-reorder unlocks once "
                       + "you track a third.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Picker("Display mode", selection: $appearance.gaugeStyle) {
                    ForEach(GaugeStyle.allCases) { style in
                        Label(style.title, systemImage: style.icon).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                GaugeStylePreview(style: appearance.gaugeStyle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            } header: {
                Text("Display mode")
            } footer: {
                Text("Choose how each Usage Window is drawn.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
    }
}

/// One agent row: icon, name, and (for the primary) a badge. When the list is
/// reorderable it carries a trailing drag handle — the affordance hinting the
/// row can be dragged via the enclosing `ForEach`'s native `.onMove`. When only
/// one follower exists the handle is hidden, since dragging does nothing.
private struct OrderRow: View {
    @Bindable var appearance: AppearanceSettings
    let id: CodingAgentID
    let draggable: Bool

    var body: some View {
        LabeledContent {
            if draggable {
                Image(systemName: "line.3.horizontal")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        } label: {
            HStack(spacing: 10) {
                AgentIconBadge(id: id)
                Text(id.displayName)
                if appearance.primaryAgent == id {
                    Text("Primary")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(appearance.primaryAgent == id
                            ? "\(id.displayName), primary" : id.displayName)
        .accessibilityHint(draggable ? "Draggable. Drag to reorder." : "")
    }
}

/// A small live sample of the selected gauge style for the Appearance picker.
private struct GaugeStylePreview: View {
    let style: GaugeStyle

    private var sample: [GaugeContent] {
        [
            GaugeContent(title: "5-hour",
                         subtitle: .reset(display: "3h 20m", spoken: "resets in 3h 20m"),
                         percentRemaining: 72, progress: 0.72, centerText: "72%",
                         emphasized: true),
            GaugeContent(title: "Weekly",
                         subtitle: .reset(display: "4d", spoken: "resets in 4d"),
                         percentRemaining: 28, progress: 0.28, centerText: "28%"),
        ]
    }

    var body: some View {
        GaugeCluster(items: sample, style: style,
                     sideDiameter: 60, centerDiameter: 78,
                     sideLineWidth: 5, centerLineWidth: 6, circularSpacing: 16)
            .frame(maxWidth: style == .bar ? 260 : .infinity)
    }
}

/// App identity: icon, version, a one-line description, and a source link.
private struct AboutPane: View {
    let onRunSetupAgain: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .padding(.bottom, 2)

            Text("TokenStats").font(.title.weight(.semibold))
            Text(versionLine).font(.callout).foregroundStyle(.secondary)

            Text("A menu-bar gauge for your Coding Agents — see how much of each "
                 + "Usage Window is left and when it resets.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)

            Link("View on GitHub",
                 destination: URL(string: "https://github.com/zhangchi0104/TokenStats")!)
                .font(.callout)
                .padding(.top, 2)

            Button("Run setup again", action: onRunSetupAgain)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("About")
    }

    private var versionLine: String {
        func value(_ key: String) -> String {
            Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "—"
        }
        return "Version \(value("CFBundleShortVersionString")) (\(value("CFBundleVersion")))"
    }
}

/// One Coding Agent's account block: a status row plus the state-dependent
/// connect / disconnect controls and any sign-in error.
private struct AccountSection: View {
    let model: UsageModel
    let id: CodingAgentID
    @State private var pastedCode = ""

    var body: some View {
        Section {
            // Header row: agent name on the left; status + (when connected)
            // the Sign-out control share the trailing edge so a connected
            // account reads as one compact row instead of a status line with
            // a button stranded on a near-empty row beneath it.
            LabeledContent {
                HStack(spacing: 10) {
                    if model.isRefreshing(id) {
                        ProgressView().controlSize(.small)
                    }
                    StatusBadge(status: status)
                    if isConnected {
                        Button("Sign out", role: .destructive) { model.signOut(id) }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    AgentIconBadge(id: id)
                    Text(id.displayName).font(.headline)
                }
            }

            if !isConnected {
                signInControls
            }

            if let error = model.loginError[id] {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    private var isConnected: Bool { model.agentStates[id] != .signedOut }

    private var status: ConnectionStatus {
        if isConnected { return .connected }
        if id == .claudeCode && model.isAwaitingCode { return .awaitingCode }
        return .signedOut
    }

    @ViewBuilder private var signInControls: some View {
        switch id {
        case .claudeCode:
            Button(model.isAwaitingCode ? "Re-open browser" : "Sign in to Claude Code") {
                model.signInClaude()
            }
            if model.isAwaitingCode {
                Text("Approve TokenStats in your browser, then paste the code here:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("Paste code", text: $pastedCode)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(submitClaudeCode)
                    Button("Submit", action: submitClaudeCode)
                        .disabled(pastedCode.isEmpty)
                }
            }
        case .codex:
            Button("Sign in to Codex") { model.signInCodex() }
            Text("Approve in your browser; TokenStats finishes automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func submitClaudeCode() {
        guard !pastedCode.isEmpty else { return }
        model.submitPastedCode(pastedCode)
        pastedCode = ""
    }
}

/// The connection state shown for one account: a colored dot + label.
private enum ConnectionStatus {
    case connected
    case awaitingCode
    case signedOut

    var label: String {
        switch self {
        case .connected: return "Connected"
        case .awaitingCode: return "Awaiting code"
        case .signedOut: return "Not signed in"
        }
    }

    var dotColor: Color {
        switch self {
        case .connected: return .green
        case .awaitingCode: return .orange
        case .signedOut: return .gray
        }
    }
}

/// A small rounded-tile glyph that anchors each account row — the macOS
/// System Settings convention of a colored icon leading the row label. Shared
/// with the onboarding flow's account tiles.
struct AgentIconBadge: View {
    let id: CodingAgentID

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint)
            .frame(width: 26, height: 26)
            .overlay(
                Image(logo)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 15, height: 15)
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }

    /// The brand mark in the asset catalog (template SVGs that tint white).
    private var logo: String {
        switch id {
        case .claudeCode: return "BrandClaude" // Anthropic / Claude spark
        case .codex: return "BrandCodex"       // OpenAI mark
        }
    }

    private var tint: Color {
        switch id {
        case .claudeCode: return Color(red: 0.85, green: 0.47, blue: 0.34) // Claude clay
        case .codex: return Color(red: 0.04, green: 0.64, blue: 0.50)      // OpenAI green
        }
    }
}

private struct StatusBadge: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.dotColor)
                .frame(width: 8, height: 8)
            Text(status.label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(status.label)
    }
}
