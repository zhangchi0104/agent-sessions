//
//  ErrorDiagnosticsDisclosure.swift
//  TokenStats
//
//  Keeps a localized, actionable error summary visible while placing raw
//  provider and transport details behind an explicit disclosure. Settings and
//  onboarding share this so neither surface leaks diagnostics into primary UI.
//

import SwiftUI

struct ErrorDiagnosticsDisclosure: View {
    let summary: String
    let diagnostics: String?
    var font: Font = .callout

    @Environment(\.locale) private var locale
    @State private var isExpanded = false

    var body: some View {
        if let diagnostics, diagnostics.isEmpty == false {
            DisclosureGroup(isExpanded: $isExpanded) {
                ScrollView {
                    Text(verbatim: diagnostics)
                        .font(font.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .scrollIndicators(.visible)
            } label: {
                errorLabel
            }
            .help(disclosureHelp)
            .accessibilityLabel(disclosureAccessibilityLabel)
        } else {
            errorLabel
        }
    }

    private var errorLabel: some View {
        Label {
            Text(verbatim: summary)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(font)
        .foregroundStyle(.red)
    }

    private var localizer: AppLocalizer {
        AppLocalizer(locale: locale)
    }

    private var disclosureHelp: String {
        localizer.localized(
            isExpanded
                ? LocalizedStringResource.usageDiagnosticsHideHelp
                : LocalizedStringResource.usageDiagnosticsShowHelp
        )
    }

    private var disclosureAccessibilityLabel: String {
        localizer.localized(
            isExpanded
                ? LocalizedStringResource.usageDiagnosticsHideAccessibility(summary)
                : LocalizedStringResource.usageDiagnosticsShowAccessibility(summary)
        )
    }
}
