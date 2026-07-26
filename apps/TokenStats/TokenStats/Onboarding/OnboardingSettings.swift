//
//  OnboardingSettings.swift
//  TokenStats
//
//  Tracks whether the first-run onboarding has been dismissed. The flow walks a
//  new user through what TokenStats accesses, connecting their Coding Agents,
//  and a wrap-up screen — and is skippable. "Skip" and "Finish" both flip
//  `completed`, so the window never auto-presents again; the user can still
//  re-run it from Settings. Persisted to UserDefaults so the choice survives
//  relaunch, mirroring `AppearanceSettings`.
//

import Foundation
import Observation

@MainActor
@Observable
final class OnboardingSettings {
    /// True once the user has finished or dismissed onboarding. While false, the
    /// app auto-presents the onboarding window on launch.
    var completed: Bool { didSet { defaults.set(completed, forKey: Self.key) } }

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "onboarding.completed"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.completed = defaults.bool(forKey: Self.key)
    }
}
