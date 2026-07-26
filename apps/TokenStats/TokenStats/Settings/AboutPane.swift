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
