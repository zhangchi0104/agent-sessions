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
