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
    case display
    case tokens
    case about

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .general:
            return LocalizedStringResource.settingsGeneralTitle
        case .accounts:
            return LocalizedStringResource.settingsAccountsTitle
        case .display:
            return LocalizedStringResource.settingsDisplayTitle
        case .tokens:
            return LocalizedStringResource.settingsTokensTitle
        case .about:
            return LocalizedStringResource.settingsAboutTitle
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .accounts: return "person.crop.circle.fill"
        case .display: return "rectangle.grid.1x2.fill"
        case .tokens: return "dollarsign.circle.fill"
        case .about: return "info"
        }
    }

    /// The icon badge color, echoing System Settings' per-row tints.
    var tint: Color {
        switch self {
        case .general: return .gray
        case .accounts: return .blue
        case .display: return .purple
        case .tokens: return .green
        case .about: return .gray
        }
    }
}
