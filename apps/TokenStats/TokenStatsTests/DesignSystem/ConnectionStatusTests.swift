//
//  ConnectionStatusTests.swift
//  TokenStatsTests
//
//  The account status shown in Settings and onboarding is a join of two
//  independent axes — what server verification says, and whether a sign-in is
//  mid-flight. Usage freshness is deliberately not one of those axes.
//

import Testing
import Foundation

@MainActor
struct ConnectionStatusTests {
    private let verifiedAt = Date(timeIntervalSince1970: 1_716_700_000)

    @Test func signedOutWithNoSignInUnderwayReadsAsSignedOut() {
        #expect(ConnectionStatus(sessionState: .signedOut, awaitingCode: false) == .signedOut)
    }

    @Test func savedSessionBeingCheckedDoesNotReadAsConnected() {
        #expect(ConnectionStatus(sessionState: .checking, awaitingCode: false) == .checking)
    }

    @Test func onlyServerVerifiedSessionReadsAsConnected() {
        #expect(
            ConnectionStatus(
                sessionState: .valid(verifiedAt: verifiedAt),
                awaitingCode: false
            ) == .connected
        )
    }

    @Test func rejectedSessionRequiresAnotherSignIn() {
        #expect(
            ConnectionStatus(
                sessionState: .reauthenticationRequired(reason: .invalidated),
                awaitingCode: false
            ) == .reauthenticationRequired
        )
    }

    @Test func transientVerificationFailureDoesNotReadAsSignedOutOrConnected() {
        #expect(
            ConnectionStatus(
                sessionState: .temporarilyUnverifiable(lastVerifiedAt: verifiedAt),
                awaitingCode: false
            ) == .temporarilyUnverifiable
        )
    }

    @Test func signedOutWhileAwaitingACodeReadsAsAwaiting() {
        #expect(ConnectionStatus(sessionState: .signedOut, awaitingCode: true) == .awaitingCode)
    }

    @Test func selfCompletingBrowserFlowReadsAsSigningIn() {
        #expect(
            ConnectionStatus(
                sessionState: .signedOut,
                awaitingCode: false,
                signingIn: true
            ) == .signingIn
        )
    }

    @Test func awaitingCodeWinsOverTheBriefBrowserLaunchState() {
        #expect(
            ConnectionStatus(
                sessionState: .signedOut,
                awaitingCode: true,
                signingIn: true
            ) == .awaitingCode
        )
    }

    @Test func verifiedSessionWinsOverALingeringAwaitingFlag() {
        #expect(
            ConnectionStatus(
                sessionState: .valid(verifiedAt: verifiedAt),
                awaitingCode: true
            ) == .connected
        )
    }

    @Test func reconnectInProgressWinsOverThePriorRejection() {
        #expect(
            ConnectionStatus(
                sessionState: .reauthenticationRequired(reason: .unauthorized),
                awaitingCode: false,
                signingIn: true
            ) == .signingIn
        )
    }

    @Test func awaitingCodeIsPerAgentAndNeverLeaksToTheOtherAgent() {
        // The regression this join replaced: the status was derived from a
        // single app-wide flag, so it needed to name Claude Code to keep
        // "Awaiting code" off Codex. Asking per agent removes the need.
        let claude = ConnectionStatus(sessionState: .signedOut, awaitingCode: true)
        let codex = ConnectionStatus(sessionState: .signedOut, awaitingCode: false)

        #expect(claude == .awaitingCode)
        #expect(codex == .signedOut)
    }

    @Test func visibilityAndActionsFollowSessionPresenceRatherThanUsageFreshness() {
        let needsSignIn = SessionState.reauthenticationRequired(reason: .expired)
        let unknown = SessionState.temporarilyUnverifiable(lastVerifiedAt: nil)

        #expect(!SessionPresentation.keepsSubscriptionVisible(.signedOut))
        #expect(SessionPresentation.keepsSubscriptionVisible(needsSignIn))
        #expect(SessionPresentation.requiresSignIn(needsSignIn))
        #expect(SessionPresentation.keepsSubscriptionVisible(unknown))
        #expect(!SessionPresentation.requiresSignIn(unknown))
        #expect(!SessionPresentation.isVerified(unknown))
    }

    @Test func pasteCodeControlsRemainVisibleWhileSessionIsChecking() {
        #expect(SessionPresentation.showsSignInControls(
            .checking,
            awaitingCode: true
        ))
        #expect(!SessionPresentation.showsSignInControls(
            .checking,
            awaitingCode: false
        ))
    }

    @Test func englishLabelsDistinguishEveryVerificationOutcome() {
        let localizer = AppLocalizer(locale: Locale(identifier: "en-US"))
        let cases: [(ConnectionStatus, String)] = [
            (.connected, "Connected"),
            (.checking, "Checking…"),
            (.reauthenticationRequired, "Sign in again"),
            (.temporarilyUnverifiable, "Can’t verify right now"),
            (.signedOut, "Not signed in"),
        ]

        for (status, expected) in cases {
            #expect(localizer.localized(status.label) == expected)
        }
    }
}
