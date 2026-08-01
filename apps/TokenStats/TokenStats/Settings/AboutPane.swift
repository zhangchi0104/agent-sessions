//
//  AboutPane.swift
//  TokenStats
//
//  Settings → About: app identity, version, a source link, and the way back
//  into the first-run onboarding flow.
//

import SwiftUI

/// App identity: icon, version, a one-line description, and a source link.
struct AboutPane: View {
    let onRunSetupAgain: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .padding(.bottom, 2)

            // i18n-ignore: TokenStats is the invariant product brand.
            Text(verbatim: "TokenStats").font(.title.weight(.semibold))
            Text(versionLine).font(.callout).foregroundStyle(.secondary)

            Text(AboutCopy.description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)

            Link(destination: URL(string: "https://github.com/zhangchi0104/TokenStats")!) {
                Text(AboutCopy.githubLink)
            }
                .font(.callout)
                .padding(.top, 2)

            Button(action: onRunSetupAgain) {
                Text(AboutCopy.runSetupAgainButton)
            }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle(Text(AboutCopy.title))
    }

    private var versionLine: LocalizedStringResource {
        func value(_ key: String) -> String {
            // i18n-ignore: Universal missing-value glyph, not natural-language copy.
            Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "—"
        }
        return AboutCopy.version(
            shortVersion: value("CFBundleShortVersionString"),
            buildVersion: value("CFBundleVersion")
        )
    }
}

private enum AboutCopy {
    static let title = LocalizedStringResource.settingsAboutTitle

    static func version(shortVersion: String, buildVersion: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsAboutVersion(shortVersion, buildVersion)
    }

    static let description = LocalizedStringResource.settingsAboutDescription

    static let githubLink = LocalizedStringResource.settingsAboutGithubLink

    static let runSetupAgainButton = LocalizedStringResource.settingsAboutRunSetupAgainButton
}
