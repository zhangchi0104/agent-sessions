//
//  AgentSignInControls.swift
//  TokenStats
//
//  The state-dependent controls that connect one Coding Agent. Settings and
//  onboarding both offer them and held identical copies differing only in font;
//  this is the single copy, so a change to a sign-in flow lands on both.
//

import SwiftUI

/// One Coding Agent's sign-in controls: the button that opens the browser, plus
/// whatever that agent's flow still needs from the user afterwards — a
/// paste-the-code field, or a line reassuring them there is nothing left to do.
///
/// Emits sibling views rather than a container, so a `Form` still lays each one
/// out as its own row exactly as it did before this was extracted.
struct AgentSignInControls: View {
    let model: UsageModel
    let id: CodingAgentID
    /// The host's body font — `.callout` in Settings, `.caption` in the tighter
    /// onboarding tile. The only thing that ever differed between the two.
    var font: Font

    @State private var pastedCode = ""
    @Environment(\.locale) private var locale

    private var agent: any CodingAgentIntegration { id.integration }
    private var localizer: AppLocalizer { AppLocalizer(locale: locale) }

    @ViewBuilder var body: some View {
        switch agent.signInStyle {
        case .pasteCode:
            Button(signInButtonTitle) {
                model.signIn(id)
            }
            .disabled(model.isSigningIn(id))
            if model.isAwaitingCode(id) {
                Text(
                    LocalizedStringResource.accountSignInPasteCodeInstruction
                )
                    .font(font)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField(
                        localizer.localized(LocalizedStringResource.accountSignInPasteCodeField),
                        text: $pastedCode
                    )
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(submit)
                    Button(
                        LocalizedStringResource.accountSignInSubmitButton,
                        action: submit
                    )
                        .disabled(pastedCode.isEmpty)
                }
            }
        case .selfCompleting:
            Button(signInButtonTitle) { model.signIn(id) }
                .disabled(model.isSigningIn(id))
            Text(
                LocalizedStringResource.accountSignInAutomaticInstruction
            )
                .font(font)
                .foregroundStyle(.secondary)
        }
    }

    private var signInButtonTitle: String {
        if model.isAwaitingCode(id) {
            return localizer.localized(
                LocalizedStringResource.accountSignInReopenBrowserButton
            )
        }
        return localizer.localized(
            LocalizedStringResource.accountSignInAgentButton(agent.displayName)
        )
    }

    private func submit() {
        guard !pastedCode.isEmpty else { return }
        model.submitPastedCode(pastedCode, for: id)
        pastedCode = ""
    }
}
