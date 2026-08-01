//
//  SettingsSection.swift
//  TokenStats
//
//  The Settings sidebar's sections and how each is presented there.
//

import SwiftUI

/// The sidebar sections. Add a case here (plus a detail pane) to grow Settings.
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case accounts
    case appearance
    case about

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .general:
            return LocalizedStringResource.settingsGeneralTitle
        case .accounts:
            return LocalizedStringResource.settingsAccountsTitle
        case .appearance:
            return LocalizedStringResource.settingsAppearanceTitle
        case .about:
            return LocalizedStringResource.settingsAboutTitle
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .accounts: return "person.crop.circle.fill"
        case .appearance: return "paintbrush.fill"
        case .about: return "info"
        }
    }

    /// The icon badge color, echoing System Settings' per-row tints.
    var tint: Color {
        switch self {
        case .general: return .gray
        case .accounts: return .blue
        case .appearance: return .purple
        case .about: return .gray
        }
    }
}
