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

    private var agent: any CodingAgentIntegration { id.integration }

    @ViewBuilder var body: some View {
        switch agent.signInStyle {
        case .pasteCode:
            Button(model.isAwaitingCode(id) ? "Re-open browser" : "Sign in to \(agent.displayName)") {
                model.signIn(id)
            }
            if model.isAwaitingCode(id) {
                Text("Approve TokenStats in your browser, then paste the code here:")
                    .font(font)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("Paste code", text: $pastedCode)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(submit)
                    Button("Submit", action: submit)
                        .disabled(pastedCode.isEmpty)
                }
            }
        case .selfCompleting:
            Button("Sign in to \(agent.displayName)") { model.signIn(id) }
            Text("Approve in your browser; TokenStats finishes automatically.")
                .font(font)
                .foregroundStyle(.secondary)
        }
    }

    private func submit() {
        guard !pastedCode.isEmpty else { return }
        model.submitPastedCode(pastedCode, for: id)
        pastedCode = ""
    }
}
