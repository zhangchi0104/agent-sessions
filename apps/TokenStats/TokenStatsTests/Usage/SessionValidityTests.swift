//
//  SessionValidityTests.swift
//  TokenStatsTests
//

import Foundation
import SwiftUI
import Testing

@MainActor
struct SessionValidityTests {
    private func snapshot(percent: Double = 24) -> UsageSnapshot {
        UsageSnapshot(
            windows: [UsageWindow(
                label: "5-hour",
                percentConsumed: percent,
                resetAt: Date(timeIntervalSince1970: 1_716_800_000)
            )],
            fetchedAt: Date(timeIntervalSince1970: 1_716_700_000)
        )
    }

    private func reading(percent: Double = 12) -> UsageReading {
        UsageReading(windows: [UsageWindow(
            label: "5-hour",
            percentConsumed: percent,
            resetAt: Date(timeIntervalSince1970: 1_716_800_000)
        )])
    }

    private func makeModel(
        auth: SessionTestAuthSession,
        provider: SessionTestProvider,
        defaults: UserDefaults,
        signInStyle: SignInStyle = .selfCompleting
    ) -> UsageModel {
        let signedOutAuth = SessionTestAuthSession(signedIn: false)
        return UsageModel(
            appearance: AppearanceSettings(defaults: defaults),
            localizer: AppLocalizer(locale: Locale(identifier: "en")),
            lastKnown: LastKnownUsageStore(defaults: defaults),
            integrations: [
                SessionTestIntegration(
                    id: .claudeCode,
                    auth: signedOutAuth,
                    provider: SessionTestProvider([])
                ),
                SessionTestIntegration(
                    id: .codex,
                    auth: auth,
                    provider: provider,
                    signInStyle: signInStyle
                ),
                SessionTestIntegration(
                    id: .cursor,
                    auth: signedOutAuth,
                    provider: SessionTestProvider([])
                ),
            ]
        )
    }

    @Test func startupInvalidGrantQuarantinesCredentialsAndPreservesStaleUsage() async {
        let defaults = InMemoryUserDefaults()
        let stale = snapshot()
        LastKnownUsageStore(defaults: defaults).save(stale, for: .codex)
        let auth = SessionTestAuthSession(
            forceResults: [.failure(OAuthRefreshError(
                status: 400,
                code: "invalid_grant",
                reauthenticationReason: .invalidGrant
            ))]
        )
        let provider = SessionTestProvider([.success(reading())])
        let model = makeModel(auth: auth, provider: provider, defaults: defaults)

        model.start()

        #expect(await waitUntil {
            model.sessionStates[.codex]
                == .reauthenticationRequired(reason: .invalidGrant)
        })
        #expect(auth.isSignedIn) // quarantined, not deleted
        #expect(auth.forceRefreshCount == 1)
        #expect(provider.fetchCount == 0)
        guard case .staleDisclosed(let displayed) = model.agentStates[.codex] else {
            Issue.record("Expected stale usage to remain visible")
            return
        }
        #expect(displayed == stale)

        let terminalRefresh = model.refreshManually(.codex)
        await terminalRefresh.value
        #expect(auth.forceRefreshCount == 1)
        #expect(provider.fetchCount == 0)
    }

    @Test func transientStartupValidationCanBeRetriedManually() async {
        let defaults = InMemoryUserDefaults()
        let auth = SessionTestAuthSession(forceResults: [
            .failure(OAuthRefreshError(
                status: 503,
                code: "temporarily_unavailable",
                reauthenticationReason: nil
            )),
            .success("rotated-access"),
        ])
        let provider = SessionTestProvider([.success(reading())])
        let model = makeModel(auth: auth, provider: provider, defaults: defaults)

        model.start()

        #expect(await waitUntil {
            model.sessionStates[.codex] == .temporarilyUnverifiable(lastVerifiedAt: nil)
        })
        #expect(provider.fetchCount == 0)

        model.refreshManually(.codex)

        #expect(await waitUntil {
            if case .valid = model.sessionStates[.codex] { return true }
            return false
        })
        #expect(auth.forceRefreshCount == 2)
        #expect(provider.fetchCount == 1)
        guard case .fresh = model.agentStates[.codex] else {
            Issue.record("Expected successful retry to publish fresh usage")
            return
        }
    }

    @Test func ordinaryUsageSuccessDoesNotUpgradeAProactiveSessionAfterTransientValidation() async {
        let defaults = InMemoryUserDefaults()
        let auth = SessionTestAuthSession(forceResults: [
            .failure(OAuthRefreshError(
                status: 503,
                code: "temporarily_unavailable",
                reauthenticationReason: nil
            )),
        ])
        let provider = SessionTestProvider([.success(reading())])
        let model = makeModel(auth: auth, provider: provider, defaults: defaults)

        model.start()

        #expect(await waitUntil {
            model.sessionStates[.codex] == .temporarilyUnverifiable(lastVerifiedAt: nil)
        })
        let validationDiagnostic = model.diagnostics[.codex]

        model.refreshAfterWake()

        #expect(await waitUntil {
            if case .fresh = model.agentStates[.codex] { return provider.fetchCount == 1 }
            return false
        })
        #expect(model.sessionStates[.codex] == .temporarilyUnverifiable(lastVerifiedAt: nil))
        #expect(model.diagnostics[.codex] == validationDiagnostic)
        #expect(auth.forceRefreshCount == 1)
    }

    @Test func naturalExpiryRefreshRestoresValidityAfterTransientValidation() async {
        let defaults = InMemoryUserDefaults()
        let auth = SessionTestAuthSession(forceResults: [
            .failure(OAuthRefreshError(
                status: 503,
                code: "temporarily_unavailable",
                reauthenticationReason: nil
            )),
        ])
        let provider = SessionTestProvider(
            [.success(reading())],
            onFetch: { _ in auth.recordNaturalRefresh() }
        )
        let model = makeModel(auth: auth, provider: provider, defaults: defaults)

        model.start()
        #expect(await waitUntil {
            model.sessionStates[.codex] == .temporarilyUnverifiable(lastVerifiedAt: nil)
        })

        model.refreshAfterWake()

        #expect(await waitUntil {
            if case .valid = model.sessionStates[.codex] {
                return provider.fetchCount == 1
            }
            return false
        })
        #expect(auth.forceRefreshCount == 1)
    }

    @Test(arguments: [
        OAuthRefreshError.Kind.http,
        OAuthRefreshError.Kind.transport,
        OAuthRefreshError.Kind.malformedResponse,
    ])
    func naturalRefreshTransientFailureDowngradesAValidSession(
        kind: OAuthRefreshError.Kind
    ) async {
        let defaults = InMemoryUserDefaults()
        let auth = SessionTestAuthSession(forceResults: [.success("startup-access")])
        let provider = SessionTestProvider([
            .success(reading(percent: 10)),
            .failure(OAuthRefreshError(
                status: kind == .http ? 503 : -1,
                code: kind == .http ? "temporarily_unavailable" : nil,
                reauthenticationReason: nil,
                kind: kind
            )),
        ])
        let model = makeModel(auth: auth, provider: provider, defaults: defaults)

        model.start()
        #expect(await waitUntil {
            if case .valid = model.sessionStates[.codex] {
                return provider.fetchCount == 1
            }
            return false
        })
        let verifiedAt = model.sessionStates[.codex].lastVerifiedAt

        model.refreshAfterWake()

        #expect(await waitUntil {
            model.sessionStates[.codex]
                == .temporarilyUnverifiable(lastVerifiedAt: verifiedAt)
        })
        #expect(provider.fetchCount == 2)
    }

    @Test func ordinaryUsageNetworkFailureDoesNotDowngradeAValidatedSession() async {
        let defaults = InMemoryUserDefaults()
        let auth = SessionTestAuthSession(forceResults: [.success("startup-access")])
        let provider = SessionTestProvider([
            .success(reading(percent: 10)),
            .failure(URLError(.notConnectedToInternet)),
        ])
        let model = makeModel(auth: auth, provider: provider, defaults: defaults)

        model.start()
        #expect(await waitUntil {
            if case .valid = model.sessionStates[.codex] {
                return provider.fetchCount == 1
            }
            return false
        })

        model.refreshAfterWake()
        #expect(await waitUntil { provider.fetchCount == 2 && !model.isRefreshing(.codex) })

        if case .valid = model.sessionStates[.codex] {
            // Usage transport failure only makes the usage snapshot stale.
        } else {
            Issue.record("A Usage network failure must not invalidate refresh proof")
        }
    }

    @Test func temporarilyUnavailableCredentialStoreRecoversWithoutHidingSubscription() async {
        let defaults = InMemoryUserDefaults()
        let stale = snapshot()
        LastKnownUsageStore(defaults: defaults).save(stale, for: .codex)
        let auth = SessionTestAuthSession(
            credentialPresenceResults: [
                .temporarilyUnavailable,
                .temporarilyUnavailable,
                .present,
            ],
            forceResults: [.success("rotated-access")]
        )
        let provider = SessionTestProvider([.success(reading(percent: 33))])
        let model = makeModel(auth: auth, provider: provider, defaults: defaults)

        model.start()
        #expect(await waitUntil {
            model.sessionStates[.codex]
                == .temporarilyUnverifiable(lastVerifiedAt: nil)
                && !model.isRefreshing(.codex)
        })
        #expect(model.sessionStates.isPresent(.codex))
        guard case .staleDisclosed(let displayed) = model.agentStates[.codex] else {
            Issue.record("Credential-store failure must preserve stale usage")
            return
        }
        #expect(displayed == stale)

        model.refreshManually(.codex)
        #expect(await waitUntil {
            guard case .fresh(let updated) = model.agentStates[.codex] else { return false }
            return updated.windows.first?.percentConsumed == 33
                && model.sessionStates[.codex].lastVerifiedAt != nil
        })
        #expect(auth.forceRefreshCount == 1)
        #expect(provider.fetchCount == 1)
    }

    @Test func successfulRefreshWithPersistenceWarningStillFetchesUsageAndVerifiesSession() async {
        let defaults = InMemoryUserDefaults()
        let auth = SessionTestAuthSession(
            forceResults: [.failure(RefreshedTokenPersistenceError())],
            hasPendingTokenPersistence: true
        )
        let provider = SessionTestProvider([
            .success(reading()),
            .success(reading(percent: 33)),
        ])
        let model = makeModel(auth: auth, provider: provider, defaults: defaults)

        model.start()

        #expect(await waitUntil {
            if case .fresh = model.agentStates[.codex] { return provider.fetchCount == 1 }
            return false
        })
        if case .valid = model.sessionStates[.codex] {
            // The server accepted the rotation; only durable storage failed.
        } else {
            Issue.record("Expected the in-memory refreshed session to remain valid")
        }
        #expect(model.diagnostics[.codex] == AppLocalizer(
            locale: Locale(identifier: "en")
        ).localized(
            LocalizedStringResource.usageSessionCredentialsPersistenceWarning
        ))
        #expect(auth.forceRefreshCount == 1)

        auth.hasPendingTokenPersistence = false
        model.refreshAfterWake()

        #expect(await waitUntil {
            guard case .fresh(let snapshot) = model.agentStates[.codex] else { return false }
            return provider.fetchCount == 2
                && snapshot.windows.first?.percentConsumed == 33
        })
        #expect(model.diagnostics[.codex] == nil)
    }

    @Test func acceptedRefreshWithoutUsableAccessKeepsUsageStaleButVerifiesSession() async {
        let defaults = InMemoryUserDefaults()
        let stale = snapshot()
        LastKnownUsageStore(defaults: defaults).save(stale, for: .codex)
        let auth = SessionTestAuthSession(forceResults: [
            .failure(RefreshedAccessTokenUnavailableError(credentialsPersisted: true)),
        ])
        let provider = SessionTestProvider([.success(reading())])
        let model = makeModel(auth: auth, provider: provider, defaults: defaults)

        model.start()

        #expect(await waitUntil {
            auth.forceRefreshCount == 1 && !model.isRefreshing(.codex)
        })
        if case .valid = model.sessionStates[.codex] {
            // The refresh grant was accepted even though no bearer is usable.
        } else {
            Issue.record("Accepted refresh must remain verified")
        }
        #expect(provider.fetchCount == 0)
        guard case .staleDisclosed(let retained) = model.agentStates[.codex] else {
            Issue.record("Usage must remain stale until a usable access token arrives")
            return
        }
        #expect(retained == stale)
    }

    @Test func usage401ForcesOneRefreshAndRetriesOnce() async {
        let defaults = InMemoryUserDefaults()
        let auth = SessionTestAuthSession(
            forceResults: [.success("startup-access"), .success("rotated-access")]
        )
        let provider = SessionTestProvider([
            .success(reading(percent: 10)),
            .failure(UsageError.unauthorized(body: #"{"detail":"unauthorized"}"#)),
            .success(reading(percent: 20)),
        ])
        let model = makeModel(auth: auth, provider: provider, defaults: defaults)

        model.start()

        #expect(await waitUntil {
            if case .fresh = model.agentStates[.codex] { return provider.fetchCount == 1 }
            return false
        })
        model.refreshAfterWake()

        #expect(await waitUntil {
            guard case .fresh(let snapshot) = model.agentStates[.codex] else { return false }
            return provider.fetchCount == 3 && snapshot.windows.first?.percentConsumed == 20
        })
        #expect(auth.forceRefreshCount == 2)
        #expect(provider.fetchCount == 3)
        if case .valid = model.sessionStates[.codex] {
            // Expected.
        } else {
            Issue.record("Expected the successful retry to verify the session")
        }
    }

    @Test func nonProactiveUsage401DoesNotQuarantineOrAttemptAForcedRefresh() async {
        let defaults = InMemoryUserDefaults()
        let auth = SessionTestAuthSession(
            supportsProactiveSessionValidation: false,
            forceResults: []
        )
        let provider = SessionTestProvider([
            .failure(UsageError.unauthorized(body: #"{"detail":"unauthorized"}"#)),
        ])
        let model = makeModel(auth: auth, provider: provider, defaults: defaults)

        model.start()

        #expect(await waitUntil {
            model.sessionStates[.codex] == .temporarilyUnverifiable(lastVerifiedAt: nil)
                && !model.isRefreshing(.codex)
        })
        #expect(auth.forceRefreshCount == 0)
        #expect(provider.fetchCount == 1)
        if case .reauthenticationRequired = model.sessionStates[.codex] {
            Issue.record("A non-proactive provider 401 must not quarantine credentials")
        }
    }

    @Test func repeated401AfterRecoveryQuarantinesWithoutClearingCredentials() async {
        let defaults = InMemoryUserDefaults()
        let auth = SessionTestAuthSession(
            forceResults: [.success("startup-access"), .success("rotated-access")]
        )
        let unauthorized = UsageError.unauthorized(body: #"{"detail":"unauthorized"}"#)
        let provider = SessionTestProvider([
            .success(reading()),
            .failure(unauthorized),
            .failure(unauthorized),
        ])
        let model = makeModel(auth: auth, provider: provider, defaults: defaults)

        model.start()
        #expect(await waitUntil {
            if case .fresh = model.agentStates[.codex] { return provider.fetchCount == 1 }
            return false
        })
        model.refreshAfterWake()

        #expect(await waitUntil {
            model.sessionStates[.codex]
                == .reauthenticationRequired(reason: .unauthorized)
        })
        #expect(auth.isSignedIn)
        #expect(auth.forceRefreshCount == 2)
        #expect(provider.fetchCount == 3)
    }

    @Test func manualRefreshBehindWakeReplaysOneForcedValidation() async {
        let defaults = InMemoryUserDefaults()
        let auth = SessionTestAuthSession(forceResults: [
            .success("startup-access"),
            .success("manual-access"),
        ])
        let provider = SessionTestProvider([
            .success(reading(percent: 10)),
            .success(reading(percent: 15)),
            .success(reading(percent: 20)),
        ], suspendAtFetch: 2)
        let model = makeModel(auth: auth, provider: provider, defaults: defaults)

        model.start()
        #expect(await waitUntil {
            if case .fresh = model.agentStates[.codex] { return provider.fetchCount == 1 }
            return false
        })

        model.refreshAfterWake()
        #expect(await waitUntil { provider.hasSuspendedFetch })
        model.refreshManually(.codex)
        #expect(auth.forceRefreshCount == 1)

        provider.resumeSuspendedFetch()

        #expect(await waitUntil {
            guard case .fresh(let snapshot) = model.agentStates[.codex] else { return false }
            return provider.fetchCount == 3 && snapshot.windows.first?.percentConsumed == 20
        })
        #expect(auth.forceRefreshCount == 2)
        #expect(provider.fetchCount == 3)
    }

    @Test func forbiddenAfterSuccessfulForceRefreshLeavesSessionValid() async {
        let defaults = InMemoryUserDefaults()
        let stale = snapshot()
        LastKnownUsageStore(defaults: defaults).save(stale, for: .codex)
        let auth = SessionTestAuthSession(forceResults: [.success("rotated-access")])
        let provider = SessionTestProvider([
            .failure(UsageError.forbidden(body: #"{"detail":"forbidden"}"#)),
        ])
        let model = makeModel(auth: auth, provider: provider, defaults: defaults)

        model.start()

        #expect(await waitUntil { !model.isRefreshing(.codex) && provider.fetchCount == 1 })
        if case .valid = model.sessionStates[.codex] {
            // Expected: refresh-token rotation proved the session.
        } else {
            Issue.record("403 must not invalidate a successfully refreshed session")
        }
        guard case .staleDisclosed(let displayed) = model.agentStates[.codex] else {
            Issue.record("Expected usage failure to retain the stale snapshot")
            return
        }
        #expect(displayed == stale)
    }

    @Test func userSignOutDuringValidationWinsOverTheLateResult() async {
        let defaults = InMemoryUserDefaults()
        let auth = SessionTestAuthSession(suspendsForceRefresh: true)
        let provider = SessionTestProvider([.success(reading())])
        let model = makeModel(auth: auth, provider: provider, defaults: defaults)

        model.start()
        #expect(await waitUntil { auth.hasPendingForceRefresh })

        model.signOut(.codex)
        auth.completeForceRefresh(with: .success("late-access"))

        #expect(await waitUntil {
            !model.isSigningOut(.codex)
                && !model.isRefreshing(.codex)
                && model.sessionStates[.codex] == .signedOut
        })
        #expect(model.sessionStates[.codex] == .signedOut)
        #expect(model.agentStates[.codex] == .signedOut)
        #expect(provider.fetchCount == 0)
    }

    @Test func failedCredentialDeletionDoesNotEraseUsageOrClaimSignedOut() async {
        let defaults = InMemoryUserDefaults()
        let auth = SessionTestAuthSession(
            forceResults: [.success("startup-access")],
            signOutFailure: CredentialStoreUnavailableError()
        )
        let provider = SessionTestProvider([.success(reading(percent: 17))])
        let model = makeModel(auth: auth, provider: provider, defaults: defaults)

        model.start()
        #expect(await waitUntil {
            if case .fresh = model.agentStates[.codex] { return provider.fetchCount == 1 }
            return false
        })

        model.signOut(.codex)

        #expect(await waitUntil {
            !model.isSigningOut(.codex) && model.loginError[.codex] != nil
        })
        #expect(auth.isSignedIn)
        #expect(model.sessionStates[.codex] != .signedOut)
        guard case .staleDisclosed(let retained) = model.agentStates[.codex] else {
            Issue.record("Failed sign-out must retain the last usage snapshot")
            return
        }
        #expect(retained.windows.first?.percentConsumed == 17)
        #expect(model.loginError[.codex] != nil)
    }

    @Test func failedCredentialDeletionDuringValidationDoesNotLeaveCheckingStuck() async {
        let defaults = InMemoryUserDefaults()
        let auth = SessionTestAuthSession(
            suspendsForceRefresh: true,
            signOutFailure: CredentialStoreUnavailableError()
        )
        let provider = SessionTestProvider([.success(reading())])
        let model = makeModel(auth: auth, provider: provider, defaults: defaults)

        let startupRefreshes = model.start()
        guard let startupRefresh = startupRefreshes[.codex] else {
            Issue.record("Missing Codex startup refresh task")
            return
        }
        #expect(await waitUntil {
            auth.hasPendingForceRefresh && model.sessionStates[.codex] == .checking
        })

        model.signOut(.codex)
        #expect(await waitUntil {
            !model.isSigningOut(.codex)
                && model.sessionStates[.codex]
                    == .temporarilyUnverifiable(lastVerifiedAt: nil)
        })
        #expect(
            model.sessionStates[.codex]
                == .temporarilyUnverifiable(lastVerifiedAt: nil)
        )
        #expect(!model.isRefreshing(.codex))

        auth.completeForceRefresh(with: .success("late-access"))
        await startupRefresh.value
        #expect(
            model.sessionStates[.codex]
                == .temporarilyUnverifiable(lastVerifiedAt: nil)
        )
        #expect(provider.fetchCount == 0)
    }

    @Test func pastedCodeCanOnlyBeExchangedOnceWhileCompletionIsInFlight() async {
        let defaults = InMemoryUserDefaults()
        let auth = SessionTestAuthSession(
            signedIn: false,
            supportsProactiveSessionValidation: false,
            suspendsCodeCompletion: true
        )
        let provider = SessionTestProvider([.success(reading())])
        let model = makeModel(
            auth: auth,
            provider: provider,
            defaults: defaults,
            signInStyle: .pasteCode
        )

        model.signIn(.codex)
        #expect(await waitUntil {
            model.isAwaitingCode(.codex) && !model.isSigningIn(.codex)
        })

        model.submitPastedCode("single-use-code", for: .codex)
        model.submitPastedCode("single-use-code", for: .codex)
        #expect(await waitUntil {
            auth.codeCompletionCount == 1 && model.isCompletingSignIn(.codex)
        })

        auth.completeCodeSignIn(with: .success(()))
        #expect(await waitUntil {
            if case .fresh = model.agentStates[.codex] {
                return !model.isCompletingSignIn(.codex) && provider.fetchCount == 1
            }
            return false
        })
        #expect(auth.codeCompletionCount == 1)
    }

    @Test func reopeningBrowserIsIgnoredWhilePastedCodeCompletionIsInFlight() async {
        let defaults = InMemoryUserDefaults()
        let auth = SessionTestAuthSession(
            signedIn: false,
            supportsProactiveSessionValidation: false,
            suspendsCodeCompletion: true
        )
        let provider = SessionTestProvider([.success(reading())])
        let model = makeModel(
            auth: auth,
            provider: provider,
            defaults: defaults,
            signInStyle: .pasteCode
        )

        model.signIn(.codex)
        #expect(await waitUntil {
            model.isAwaitingCode(.codex) && !model.isSigningIn(.codex)
        })
        #expect(auth.beginSignInCount == 1)

        model.submitPastedCode("single-use-code", for: .codex)
        #expect(await waitUntil {
            auth.codeCompletionCount == 1 && model.isCompletingSignIn(.codex)
        })

        model.signIn(.codex)
        #expect(auth.beginSignInCount == 1)
        #expect(model.isCompletingSignIn(.codex))

        auth.completeCodeSignIn(with: .success(()))
        #expect(await waitUntil {
            guard case .fresh = model.agentStates[.codex] else { return false }
            return !model.isCompletingSignIn(.codex) && provider.fetchCount == 1
        })
    }

    @Test func reconnectIgnoresThePreviousSessionsLateValidationFailure() async {
        let defaults = InMemoryUserDefaults()
        let auth = SessionTestAuthSession(suspendsForceRefresh: true)
        let provider = SessionTestProvider([.success(reading())])
        let model = makeModel(auth: auth, provider: provider, defaults: defaults)

        let startupRefreshes = model.start()
        guard let startupRefresh = startupRefreshes[.codex] else {
            Issue.record("Missing Codex startup refresh task")
            return
        }
        #expect(await waitUntil { auth.hasPendingForceRefresh })

        model.signOut(.codex)
        #expect(await waitUntil {
            !model.isSigningOut(.codex) && model.sessionStates[.codex] == .signedOut
        })
        model.signIn(.codex)

        #expect(await waitUntil {
            if case .fresh = model.agentStates[.codex] {
                return !model.isSigningIn(.codex) && provider.fetchCount == 1
            }
            return false
        })

        auth.completeForceRefresh(with: .failure(OAuthRefreshError(
            status: 400,
            code: "invalid_grant",
            reauthenticationReason: .invalidGrant
        )))
        await startupRefresh.value

        if case .valid = model.sessionStates[.codex] {
            // The late result belonged to the signed-out generation.
        } else {
            Issue.record("A previous session must not quarantine the replacement login")
        }
        #expect(auth.isSignedIn)
        #expect(provider.fetchCount == 1)
    }

    @Test func reconnectDoesNotValidatePreviousCredentialsWhileBrowserFlowIsPending() async {
        let defaults = InMemoryUserDefaults()
        let auth = SessionTestAuthSession(
            forceResults: [.failure(OAuthRefreshError(
                status: 400,
                code: "invalid_grant",
                reauthenticationReason: .invalidGrant
            ))],
            suspendsSignIn: true
        )
        let provider = SessionTestProvider([.success(reading())])
        let model = makeModel(auth: auth, provider: provider, defaults: defaults)

        model.signIn(.codex)
        #expect(await waitUntil { auth.hasPendingSignIn })

        let refreshWhileSigningIn = model.refreshManually(.codex)
        await refreshWhileSigningIn.value
        #expect(auth.forceRefreshCount == 0)
        #expect(provider.fetchCount == 0)

        auth.completeSuspendedSignIn(with: .success(()))
        #expect(await waitUntil {
            guard case .fresh = model.agentStates[.codex] else { return false }
            return !model.isSigningIn(.codex) && provider.fetchCount == 1
        })

        if case .valid = model.sessionStates[.codex] {
            // The code exchange, not the retained old token, proved validity.
        } else {
            Issue.record("A reconnect was overwritten by old-token validation")
        }
        #expect(auth.forceRefreshCount == 0)
        #expect(provider.fetchCount == 1)
    }
}

private final class SessionTestAuthSession: AgentAuthSession {
    var isSignedIn: Bool
    let supportsProactiveSessionValidation: Bool
    private var credentialPresenceResults: [CredentialPresence]
    private var forceResults: [Result<String, any Error>]
    private let suspendsForceRefresh: Bool
    private let suspendsSignIn: Bool
    private let suspendsCodeCompletion: Bool
    private let signOutFailure: (any Error)?
    private var forceContinuation: CheckedContinuation<String, any Error>?
    private var signInContinuation: CheckedContinuation<Void, any Error>?
    private var codeContinuation: CheckedContinuation<Void, any Error>?
    private(set) var forceRefreshCount = 0
    private(set) var refreshValidationRevision = 0
    private(set) var codeCompletionCount = 0
    private(set) var beginSignInCount = 0
    var hasPendingTokenPersistence: Bool

    init(
        signedIn: Bool = true,
        supportsProactiveSessionValidation: Bool = true,
        credentialPresenceResults: [CredentialPresence] = [],
        forceResults: [Result<String, any Error>] = [.success("access")],
        suspendsForceRefresh: Bool = false,
        suspendsSignIn: Bool = false,
        suspendsCodeCompletion: Bool = false,
        signOutFailure: (any Error)? = nil,
        hasPendingTokenPersistence: Bool = false
    ) {
        self.isSignedIn = signedIn
        self.supportsProactiveSessionValidation = supportsProactiveSessionValidation
        self.credentialPresenceResults = credentialPresenceResults
        self.forceResults = forceResults
        self.suspendsForceRefresh = suspendsForceRefresh
        self.suspendsSignIn = suspendsSignIn
        self.suspendsCodeCompletion = suspendsCodeCompletion
        self.signOutFailure = signOutFailure
        self.hasPendingTokenPersistence = hasPendingTokenPersistence
    }

    var credentialPresence: CredentialPresence {
        if !credentialPresenceResults.isEmpty {
            return credentialPresenceResults.removeFirst()
        }
        return isSignedIn ? .present : .absent
    }

    var hasPendingForceRefresh: Bool { forceContinuation != nil }

    var hasPendingSignIn: Bool { signInContinuation != nil }

    func validAccessToken() async throws -> String {
        guard isSignedIn else { throw UsageError.notSignedIn }
        return "access"
    }

    func forceRefreshAccessToken() async throws -> String {
        forceRefreshCount += 1
        if suspendsForceRefresh {
            return try await withCheckedThrowingContinuation { continuation in
                forceContinuation = continuation
            }
        }
        guard !forceResults.isEmpty else {
            Issue.record("Unexpected force refresh")
            return "access"
        }
        return try forceResults.removeFirst().get()
    }

    func completeForceRefresh(with result: Result<String, any Error>) {
        switch result {
        case .success(let token): forceContinuation?.resume(returning: token)
        case .failure(let error): forceContinuation?.resume(throwing: error)
        }
        forceContinuation = nil
    }

    func completeSuspendedSignIn(with result: Result<Void, any Error>) {
        switch result {
        case .success: signInContinuation?.resume()
        case .failure(let error): signInContinuation?.resume(throwing: error)
        }
        signInContinuation = nil
    }

    func completeCodeSignIn(with result: Result<Void, any Error>) {
        switch result {
        case .success: codeContinuation?.resume()
        case .failure(let error): codeContinuation?.resume(throwing: error)
        }
        codeContinuation = nil
    }

    func recordNaturalRefresh() { refreshValidationRevision &+= 1 }

    func signOut() async throws {
        if let signOutFailure { throw signOutFailure }
        isSignedIn = false
    }

    func beginSignIn() async throws {
        beginSignInCount += 1
        if suspendsSignIn {
            try await withCheckedThrowingContinuation { continuation in
                signInContinuation = continuation
            }
        }
        if !suspendsCodeCompletion { isSignedIn = true }
    }

    func completeSignIn(pastedCode: String, localizer: AppLocalizer) async throws {
        codeCompletionCount += 1
        if suspendsCodeCompletion {
            try await withCheckedThrowingContinuation { continuation in
                codeContinuation = continuation
            }
        }
        isSignedIn = true
    }
}

private final class SessionTestProvider: UsageProvider {
    enum Step {
        case success(UsageReading)
        case failure(any Error)
    }

    private var steps: [Step]
    private let suspendAtFetch: Int?
    private let onFetch: ((Int) -> Void)?
    private var fetchContinuation: CheckedContinuation<Void, Never>?
    private(set) var fetchCount = 0

    init(
        _ steps: [Step],
        suspendAtFetch: Int? = nil,
        onFetch: ((Int) -> Void)? = nil
    ) {
        self.steps = steps
        self.suspendAtFetch = suspendAtFetch
        self.onFetch = onFetch
    }

    var hasSuspendedFetch: Bool { fetchContinuation != nil }

    func resumeSuspendedFetch() {
        let continuation = fetchContinuation
        fetchContinuation = nil
        continuation?.resume()
    }

    func fetchUsage() async throws -> UsageReading {
        fetchCount += 1
        onFetch?(fetchCount)
        if fetchCount == suspendAtFetch {
            await withCheckedContinuation { continuation in
                fetchContinuation = continuation
            }
        }
        guard !steps.isEmpty else {
            throw UsageError.badResponse(status: -1, body: "Unexpected usage fetch")
        }
        switch steps.removeFirst() {
        case .success(let reading): return reading
        case .failure(let error): throw error
        }
    }
}

private struct SessionTestIntegration: CodingAgentIntegration {
    let id: CodingAgentID
    let auth: any AgentAuthSession
    let provider: UsageProvider
    let displayName = "Test"
    let shortLabel = "T"
    let brand = AgentBrand(assetName: "", tint: .clear)
    let signInStyle: SignInStyle
    let gaugeLayout = GaugeLayout(slots: [])
    let transcriptRoot: String? = nil

    init(
        id: CodingAgentID,
        auth: any AgentAuthSession,
        provider: UsageProvider,
        signInStyle: SignInStyle = .selfCompleting
    ) {
        self.id = id
        self.auth = auth
        self.provider = provider
        self.signInStyle = signInStyle
    }

    func makeProvider() -> UsageProvider { provider }
}
