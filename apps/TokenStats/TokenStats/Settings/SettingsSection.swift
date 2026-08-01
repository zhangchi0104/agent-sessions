//
//  SettingsSection.swift
//  TokenStats
//
//  The Settings sidebar's sections and how each is presented there.
//

import SwiftUI

/// The sidebar sections. Add a case here (plus a detail pane) to grow Settings.
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case accounts
    case display
    case tokens
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .accounts: return "Accounts"
        case .display: return "Display"
        case .tokens: return "Tokens"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .accounts: return "person.crop.circle.fill"
        case .display: return "rectangle.grid.1x2.fill"
        case .tokens: return "dollarsign.circle.fill"
        case .about: return "info"
        }
    }

    /// The icon badge color, echoing System Settings' per-row tints.
    var tint: Color {
        switch self {
        case .accounts: return .blue
        case .display: return .purple
        case .tokens: return .green
        case .about: return .gray
        }
    }
}
