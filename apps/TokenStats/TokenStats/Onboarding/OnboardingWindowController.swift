//
//  OnboardingWindowController.swift
//  TokenStats
//
//  Hosts OnboardingView in a standalone window. TokenStats is a menu-bar-only
//  (LSUIElement) app with no main window, so onboarding gets its own AppKit
//  window we can present on first launch and re-present from Settings. Any
//  dismissal — Finish, Skip, or the close button — records onboarding as done,
//  so it never auto-appears again ("skippable, dismiss forever").
//

import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let model: UsageModel
    private let onboarding: OnboardingSettings
    private let onComplete: () -> Void
    private var window: NSWindow?

    init(
        model: UsageModel,
        onboarding: OnboardingSettings,
        onComplete: @escaping () -> Void = {}
    ) {
        self.model = model
        self.onboarding = onboarding
        self.onComplete = onComplete
        super.init()
    }

    /// Present the onboarding window, building it on first use and bringing it
    /// (and the app) to the front. The extra `activate` is needed because an
    /// LSUIElement app's windows don't come forward — or take focus — on their own.
    func show() {
        if let window {
            present(window)
            return
        }

        let root = OnboardingView(model: model) { [weak self] in
            self?.window?.close()
        }
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        // Full-size content with a transparent, hidden title strip — the same
        // chrome the Settings window uses, with the traffic lights floating over
        // the content. Only the close button stays (no minimize/zoom on a dialog).
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.center()
        // We own the lifetime: keep it across the close so `windowWillClose` can
        // run, then drop our reference there to let it (and its SwiftUI view's
        // file-watch task) deallocate.
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        present(window)
    }

    /// Bring the window and the (menu-bar-only) app to the front. The extra
    /// `activate` is needed because an LSUIElement app's windows don't come
    /// forward — or take focus — on their own.
    private func present(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Reaching here means the user finished, skipped, or closed the window —
        // all of which dismiss onboarding for good.
        onboarding.completed = true
        onComplete()
        // Release the window so its SwiftUI view (and the view's polling task)
        // tear down now; a later "Run setup again" rebuilds a fresh one.
        window?.delegate = nil
        window = nil
    }
}
