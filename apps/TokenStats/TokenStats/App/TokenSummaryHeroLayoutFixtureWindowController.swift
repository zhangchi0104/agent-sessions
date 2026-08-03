//
//  TokenSummaryHeroLayoutFixtureWindowController.swift
//  TokenStats
//
//  A Debug-only live window for XCUI layout regression coverage. It renders
//  production TokenSummaryHero views through the ordinary AppKit layout loop;
//  the default unit runner never constructs this controller.
//

#if DEBUG
import AppKit
import SwiftUI

@MainActor
final class TokenSummaryHeroLayoutFixtureWindowController {
    static let launchArgument = "--ui-testing-token-summary-layout"

    private var window: NSWindow?

    func show() {
        if let window {
            present(window)
            return
        }

        let root = TokenSummaryHeroLayoutFixtureView()
            .environment(\.locale, Locale(identifier: "en-US"))
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: TokenSummaryHeroLayoutFixtureView.contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        // i18n-ignore: Debug-only XCUI fixture title, never shown in production.
        window.title = "Token Summary Layout Fixture"
        window.animationBehavior = .none
        window.setContentSize(TokenSummaryHeroLayoutFixtureView.contentSize)
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window

        present(window)
    }

    private func present(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private struct TokenSummaryHeroLayoutFixtureView: View {
    static let heroWidth: CGFloat = 300
    static let spacing: CGFloat = 16
    static let padding: CGFloat = 24
    static let contentSize = NSSize(
        width: heroWidth + (padding * 2),
        height: (TokenSummaryHero.fixedHeight * 3) + (spacing * 2) + (padding * 2)
    )

    private struct Fixture: Identifiable {
        let id: String
        let range: TokenRange
        let inputTokens: Int
    }

    private let fixtures = [
        Fixture(
            id: "tokens.summary.hero.today-short",
            range: .today,
            inputTokens: 60
        ),
        Fixture(
            id: "tokens.summary.hero.seven-days-large",
            range: .sevenDays,
            inputTokens: 999_999_999
        ),
        Fixture(
            id: "tokens.summary.hero.thirty-days-very-large",
            range: .thirtyDays,
            inputTokens: 12_345_678_901
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            ForEach(fixtures) { fixture in
                TokenSummaryHero(
                    perAgent: [agent(inputTokens: fixture.inputTokens)],
                    metric: .billingTokens,
                    range: fixture.range,
                    hasLoaded: true,
                    accessibilityIdentifier: "\(fixture.id).content"
                )
                // Keep the production view's accessibility node nested under a
                // fixed-size fixture node. XCUI can otherwise report the
                // inner SwiftUI accessibility element before the outer frame
                // has propagated through the AppKit hosting boundary.
                .frame(width: Self.heroWidth, height: TokenSummaryHero.fixedHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(fixture.id)
                .accessibilityIdentifier(fixture.id)
            }
        }
        .padding(Self.padding)
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
    }

    private func agent(inputTokens: Int) -> TokenOdometerModel.AgentTokens {
        let usage = TokenUsage(
            inputTokens: inputTokens,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            responseCount: 1
        )
        return TokenOdometerModel.AgentTokens(
            id: .claudeCode,
            label: "Claude Code",
            usage: usage,
            byModel: [.init(model: .named("claude-opus-5"), usage: usage)]
        )
    }
}
#endif
