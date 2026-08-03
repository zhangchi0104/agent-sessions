//
//  AppRuntimeMode.swift
//  TokenStats
//
//  Keeps test-process detection and its safety policy in one place. The
//  default unit suite is unhosted, but these rules remain a fail-closed guard
//  if a future Xcode change accidentally hosts it in TokenStats.app again.
//

import Foundation

enum AppRuntimeMode: Equatable {
    case production
    case unitTesting
    case uiTesting

    static var current: AppRuntimeMode {
        detect()
    }

    static func detect(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        xctestIsLoaded: Bool = NSClassFromString("XCTestCase") != nil
    ) -> AppRuntimeMode {
        // The application launched by XCUI does not host the UI-test bundle,
        // but XCTest-related environment may still be inherited. Its explicit
        // launch argument therefore has precedence over unit-test detection.
        if arguments.contains("--ui-testing") {
            return .uiTesting
        }
        if environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || xctestIsLoaded
        {
            return .unitTesting
        }
        return .production
    }

    var insertsMenuBarExtra: Bool {
        self == .production
    }

    var usesInertDependencies: Bool {
        self != .production
    }

    var usesIsolatedPersistence: Bool {
        self != .production
    }
}
