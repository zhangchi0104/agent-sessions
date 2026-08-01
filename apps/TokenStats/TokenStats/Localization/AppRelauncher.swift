//
//  AppRelauncher.swift
//  TokenStats
//
//  Relaunches with NSWorkspace's public new-instance API. The old instance is
//  terminated only after Launch Services reports the replacement as running.
//

import AppKit
import Observation

nonisolated enum AppRelaunchFailure: Error, Equatable, Sendable {
    case applicationURLUnavailable
    case newInstanceLaunchFailed

    var message: LocalizedStringResource {
        switch self {
        case .applicationURLUnavailable:
            LocalizedStringResource.settingsGeneralLanguageRestartErrorApplicationUnavailable
        case .newInstanceLaunchFailed:
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

    private(set) var isRelaunching = false
    private(set) var failure: AppRelaunchFailure?

    @ObservationIgnored private let applicationURL: () -> URL?
    @ObservationIgnored private let launchNewInstance: LaunchNewInstance
    @ObservationIgnored private let terminateCurrentInstance: () -> Void

    convenience init() {
        self.init(
            applicationURL: { Bundle.main.bundleURL },
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

    /// UI tests may navigate into Settings, but must never escape their inert
    /// dependency graph by launching a replacement process without the
    /// `--ui-testing` argument. Failing through the normal completion path also
    /// lets UI tests exercise the localized restart error without opening an app.
    static func disabledForUITesting() -> AppRelauncher {
        AppRelauncher(
            applicationURL: { Bundle.main.bundleURL },
            launchNewInstance: { _, _, completion in completion(false) },
            terminateCurrentInstance: {}
        )
    }

    init(applicationURL: @escaping () -> URL?,
         launchNewInstance: @escaping LaunchNewInstance,
         terminateCurrentInstance: @escaping () -> Void) {
        self.applicationURL = applicationURL
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

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        isRelaunching = true

        launchNewInstance(applicationURL, configuration) { [weak self] didLaunch in
            guard let self else { return }
            guard isRelaunching else { return }
            isRelaunching = false
            guard didLaunch else {
                failure = .newInstanceLaunchFailed
                return
            }

            // The replacement is confirmed alive. Only now is it safe to end
            // the instance the user is currently interacting with.
            terminateCurrentInstance()
        }
    }

    func clearFailure() {
        failure = nil
    }
}
