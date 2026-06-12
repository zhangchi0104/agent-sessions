//
//  SessionsView.swift
//  TokenStats
//
//  The Sessions tab body: a compact, scrollable list of the user's Coding Agent
//  Sessions, surfaced needs-you → running → idle, newest-updated first. Reads
//  the shared agent-sessions database via SessionsModel; the list polls while
//  visible so statuses stay live without any push channel.
//

import SwiftUI

struct SessionsView: View {
    let model: SessionsModel

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                placeholder("Loading sessions…")
            case .unavailable:
                placeholder("No sessions yet.\nInstall the session-event hook to track Coding Agent sessions.")
            case .failed(let message):
                placeholder("Couldn't read sessions.\n\(message)")
            case .loaded(let sessions):
                if sessions.isEmpty {
                    placeholder("No sessions yet.")
                } else {
                    list(sessions)
                }
            }
        }
        // Polls on appear and stops when the tab/popover goes away (SwiftUI
        // cancels the `.task` on disappear).
        .task { await model.pollWhileVisible() }
    }

    private func list(_ sessions: [Session]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sessions) { session in
                    if session.id != sessions.first?.id { Divider() }
                    SessionRow(session: session)
                }
            }
        }
        .frame(maxHeight: 340)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }
}

/// One Session: a status dot, the name and status, then agent · directory.
private struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(session.status.color)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
                .help(session.status.helpText)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    // displayName hides UUID fallback names; the tooltip keeps
                    // the raw name (and so the session id) discoverable.
                    Text(session.displayName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .truncationMode(.tail)
                        .help(session.name)
                    Spacer(minLength: 8)
                    Text(session.status.displayName)
                        .font(.callout)
                        .foregroundStyle(session.status.color)
                        .fixedSize()
                        .help(session.status.helpText)
                }
                HStack(spacing: 8) {
                    // Concatenated Texts stay one truncating line; the agent
                    // name is slightly heavier so it reads first.
                    (Text(session.agent).fontWeight(.medium)
                        + Text(" · ")
                        + Text(session.displayDirectory))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    // Relative age disambiguates same-directory rows and keeps
                    // staleness visible; when tokens exist the breakdown
                    // tooltip covers the whole trailing text so the hover
                    // target doesn't shrink. Set in the app's number language
                    // (rounded, monospaced digits), same as the hero counter.
                    Group {
                        if let usage = session.tokenUsage {
                            Text("\(usage.compactTotal) tokens · \(updatedAge)")
                                .help("\(usage.totalTokens.formatted()) tokens — \(usage.breakdownDescription)")
                        } else {
                            Text(updatedAge)
                        }
                    }
                    .font(.system(.callout, design: .rounded).weight(.medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize()
                }
                .font(.callout)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// Same relative-age wording as the "Updated X ago" status lines.
    private var updatedAge: String {
        UsageFormatting.relativeAge(of: session.updatedAt)
    }

    private var accessibilityText: String {
        var label = "\(session.displayName), \(session.status.displayName), \(session.agent), \(session.displayDirectory)"
        if let usage = session.tokenUsage {
            label += ", \(usage.totalTokens) tokens"
        }
        label += ", updated \(updatedAge)"
        return label
    }

}
