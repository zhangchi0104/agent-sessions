//
//  GeneralPane.swift
//  TokenStats
//
//  Settings → General: choose TokenStats' UI language. The selected language is
//  saved immediately but intentionally remains pending until a process restart.
//

import SwiftUI

struct GeneralPane: View {
    @Bindable var localization: LocalizationSettings
    @Bindable var relauncher: AppRelauncher
    @State private var restartDeferred = false

    var body: some View {
        Form {
            Section {
                Picker(selection: $localization.preferredLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.pickerTitle).tag(language)
                    }
                } label: {
                    Text(Self.languagePickerTitle)
                }
                .disabled(relauncher.isRelaunching)
                .accessibilityIdentifier("settings.general.language")
            } header: {
                Text(Self.languageSectionTitle)
            } footer: {
                Text(Self.languageFooter)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if localization.needsRestart {
                restartSection
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Self.navigationTitle)
        .onChange(of: localization.preferredLanguage) {
            restartDeferred = false
            relauncher.clearFailure()
        }
    }

    private var restartSection: some View {
        Section {
            Label {
                Text(restartDeferred ? Self.restartDeferredMessage : Self.restartRequiredMessage)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: restartDeferred ? "clock" : "arrow.clockwise.circle.fill")
                    .foregroundStyle(restartDeferred ? Color.secondary : Color.accentColor)
            }

            if !restartDeferred {
                HStack {
                    Spacer()
                    Button {
                        restartDeferred = true
                        relauncher.clearFailure()
                    } label: {
                        Text(Self.laterButtonTitle)
                    }
                    .disabled(relauncher.isRelaunching)

                    Button {
                        relauncher.relaunch()
                    } label: {
                        if relauncher.isRelaunching {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel(Self.restartingAccessibilityLabel)
                        } else {
                            Text(Self.restartNowButtonTitle)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(relauncher.isRelaunching)
                    .accessibilityIdentifier("settings.general.restart-now")
                }
            }

            if let failure = relauncher.failure {
                Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.general.restart-error")
            }
        } header: {
            Text(Self.restartSectionTitle)
        }
    }

    private static let navigationTitle = LocalizedStringResource.settingsGeneralTitle
    private static let languageSectionTitle = LocalizedStringResource.settingsGeneralLanguageSection
    private static let languagePickerTitle = LocalizedStringResource.settingsGeneralLanguageTitle
    private static let languageFooter = LocalizedStringResource.settingsGeneralLanguageFooter
    private static let restartSectionTitle = LocalizedStringResource.settingsGeneralLanguageRestartSection
    private static let restartRequiredMessage = LocalizedStringResource.settingsGeneralLanguageRestartMessage
    private static let restartDeferredMessage = LocalizedStringResource.settingsGeneralLanguageRestartDeferred
    private static let laterButtonTitle = LocalizedStringResource.settingsGeneralLanguageRestartLater
    private static let restartNowButtonTitle = LocalizedStringResource.settingsGeneralLanguageRestartNow
    private static let restartingAccessibilityLabel = LocalizedStringResource.settingsGeneralLanguageRestartInProgress
}
