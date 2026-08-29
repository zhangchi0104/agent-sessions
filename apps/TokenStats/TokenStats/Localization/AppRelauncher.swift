//
//  AppRelauncher.swift
//  TokenStats
//
//  Relaunches with NSWorkspace's public new-instance API. The old instance is
//  terminated only after its credential refreshes are durably quiesced and
//  Launch Services reports the replacement as running.
//

import AppKit
import Observation

nonisolated enum AppRelaunchFailure: Error, Equatable, Sendable {
    case applicationURLUnavailable
    case credentialHandoffFailed
    case newInstanceLaunchFailed

    var message: LocalizedStringResource {
        switch self {
        case .applicationURLUnavailable:
            LocalizedStringResource.settingsGeneralLanguageRestartErrorApplicationUnavailable
        case .credentialHandoffFailed, .newInstanceLaunchFailed:
            LocalizedStringResource.settingsGeneralLanguageRestartErrorLaunchFailed
        }
    }
}

@MainActor
@Observable
final class AppRelauncher {
    /// Injected boundary around NSWorkspace. Its Boolean is true only after a
    /// replacement NSRunningApplication has been returned without an error.
    typealias LaunchNewInstance = (
        URL,
        NSWorkspace.OpenConfiguration,
        @escaping @MainActor (Bool) -> Void
    ) -> Void
    typealias PrepareCredentialHandoff = @MainActor () async throws
        -> [any RefreshCoordinationLease]

    private(set) var isRelaunching = false
    private(set) var failure: AppRelaunchFailure?

    @ObservationIgnored private let applicationURL: () -> URL?
    @ObservationIgnored private let prepareCredentialHandoff: PrepareCredentialHandoff
    @ObservationIgnored private let launchNewInstance: LaunchNewInstance
    @ObservationIgnored private let terminateCurrentInstance: () -> Void
    /// Successful relaunch keeps these descriptors open until process exit.
    /// The replacement may already be running, but cannot refresh any account
    /// until the predecessor has actually terminated rather than merely called
    /// `NSApplication.terminate`.
    @ObservationIgnored private var retainedCredentialLeases: [any RefreshCoordinationLease] = []

    convenience init() {
        self.init(
            applicationURL: { Bundle.main.bundleURL },
            prepareCredentialHandoff: {
                var leases: [any RefreshCoordinationLease] = []
                do {
                    for integration in CodingAgentRegistry.all {
                        leases.append(
                            try await integration.auth.acquireRelaunchCoordination()
                        )
                    }
                    return leases
                } catch {
                    leases.forEach { $0.release() }
                    throw error
                }
            },
            launchNewInstance: { url, configuration, completion in
                NSWorkspace.shared.openApplication(at: url, configuration: configuration) {
                    runningApplication, error in
                    let didLaunch = error == nil && runningApplication != nil
                    Task { @MainActor in completion(didLaunch) }
                }
            },
            terminateCurrentInstance: { NSApp.terminate(nil) }
        )
    }

    /// Tests may navigate into Settings, but must never escape their inert
    /// dependency graph by launching a replacement process without the
    /// `--ui-testing` argument. Failing through the normal completion path also
    /// lets UI tests exercise the localized restart error without opening an app.
    static func disabledForTesting() -> AppRelauncher {
        AppRelauncher(
            applicationURL: { Bundle.main.bundleURL },
            prepareCredentialHandoff: { [] },
            launchNewInstance: { _, _, completion in completion(false) },
            terminateCurrentInstance: {}
        )
    }

    init(applicationURL: @escaping () -> URL?,
         prepareCredentialHandoff: @escaping PrepareCredentialHandoff = { [] },
         launchNewInstance: @escaping LaunchNewInstance,
         terminateCurrentInstance: @escaping () -> Void) {
        self.applicationURL = applicationURL
        self.prepareCredentialHandoff = prepareCredentialHandoff
        self.launchNewInstance = launchNewInstance
        self.terminateCurrentInstance = terminateCurrentInstance
    }

    func relaunch() {
        guard !isRelaunching else { return }

        failure = nil
        guard let applicationURL = applicationURL() else {
            failure = .applicationURLUnavailable
            return
        }

        isRelaunching = true

        Task { [weak self] in
            guard let self else { return }
            let leases: [any RefreshCoordinationLease]
            do {
                leases = try await prepareCredentialHandoff()
            } catch {
                guard isRelaunching else { return }
                isRelaunching = false
                failure = .credentialHandoffFailed
                return
            }
            guard isRelaunching else {
                leases.forEach { $0.release() }
                return
            }

            retainedCredentialLeases = leases
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            launchNewInstance(applicationURL, configuration) { [weak self] didLaunch in
                guard let self else {
                    leases.forEach { $0.release() }
                    return
                }
                guard isRelaunching else {
                    releaseCredentialHandoff()
                    return
                }
                isRelaunching = false
                guard didLaunch else {
                    failure = .newInstanceLaunchFailed
                    releaseCredentialHandoff()
                    return
                }

                // The replacement is confirmed alive and will wait on these
                // leases. Keep them retained through actual process exit so no
                // old-instance timer can start a final uncertain refresh.
                terminateCurrentInstance()
            }
        }
    }

    private func releaseCredentialHandoff() {
        retainedCredentialLeases.forEach { $0.release() }
        retainedCredentialLeases.removeAll()
    }

    func clearFailure() {
        failure = nil
    }
}
