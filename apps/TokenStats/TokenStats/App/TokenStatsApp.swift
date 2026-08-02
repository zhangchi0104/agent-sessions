//
//  TokenStatsApp.swift
//  TokenStats
//
//  Menu-bar-only app (LSUIElement, set in the generated Info.plist — no Dock
//  icon). The label shows each signed-in Coding Agent's primary (5-hour) Usage
//  Window percent — a single percent when only one is available, or compact
//  side-by-side readings (e.g. "C: 24% X: 12%") when both are. Clicking opens
//  the popover anchored to it.
//
//  The app's long-lived models live on an AppDelegate rather than the App struct
//  so the same instances can be shared with the AppKit-hosted onboarding window
//  and presented on first launch (see OnboardingWindowController).
//

import SwiftUI
import AppKit

enum TokenStatsWindowID {
    static let settings = "settings"
}

@main
struct TokenStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: appDelegate.model,
                        odometer: appDelegate.odometer,
                        currencyModel: appDelegate.currencyModel)
                .environment(\.locale, appDelegate.localization.effectiveLocale)
        } label: {
            // Monochrome icon + per-agent percent — no threshold colors (PRD).
            Group {
                Image(systemName: "gauge.with.dots.needle.33percent")
                Text(MenuBarSummary.text(
                    for: appDelegate.model.menuBarSummaries,
                    locale: appDelegate.localization.effectiveLocale
                ))
            }
            .environment(\.locale, appDelegate.localization.effectiveLocale)
        }
        .menuBarExtraStyle(.window)

        // The dedicated settings window for managing accounts. It uses a named
        // Window so the menu-bar popover and Command-comma can target the same
        // native Settings surface.
        Window(appDelegate.localization.localizer.localized(Self.settingsWindowTitle),
               id: TokenStatsWindowID.settings) {
            SettingsView(model: appDelegate.model,
                         currencyModel: appDelegate.currencyModel,
                         localization: appDelegate.localization,
                         relauncher: appDelegate.relauncher,
                         onRunSetupAgain: { appDelegate.showOnboarding() })
                .environment(\.locale, appDelegate.localization.effectiveLocale)
        }
        .defaultSize(width: 720, height: 460)
        .windowResizability(.contentMinSize)
        // Full-size content with no opaque title strip, so the sidebar runs to
        // the top of the window and the traffic lights float over it.
        .windowStyle(.hiddenTitleBar)
        .commands {
            TokenStatsCommands(localizer: appDelegate.localization.localizer)
        }
    }

    private static let settingsWindowTitle = LocalizedStringResource.windowSettingsTitle
}

/// Owns the app's long-lived models and the onboarding window. As an
/// `@NSApplicationDelegateAdaptor`, it's created before the scenes, so the App
/// struct reads its models when building them.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: UsageModel
    let odometer: TokenOdometerModel
    let currencyModel: CurrencyModel
    let onboarding: OnboardingSettings
    let localization: LocalizationSettings
    let relauncher: AppRelauncher
    private var onboardingController: OnboardingWindowController?

    override init() {
        // Both models are driven by the registered Coding Agents: the usage
        // model refreshes one per agent, and the Token Odometer scans one
        // transcript root per agent.
        let uiTesting = Self.isRunningUITests
        let usesIsolatedPersistence = uiTesting || Self.isRunningUnitTests
        // NSArgumentDomain is part of every UserDefaults search list, so the UI
        // test language launch argument still overrides this isolated PID suite.
        // Unit-test hosting is isolated too because CurrencyModel repairs its
        // cache envelope during initialization, before the launch guard runs.
        let persistenceDefaults = usesIsolatedPersistence
            ? UserDefaults(
                suiteName: "dev.otakuma.TokenStats.test-persistence."
                    + String(ProcessInfo.processInfo.processIdentifier)
            )!
            : .standard
        let appearance = AppearanceSettings(defaults: persistenceDefaults)
        localization = LocalizationSettings(defaults: persistenceDefaults)
        relauncher = uiTesting ? AppRelauncher.disabledForUITesting() : AppRelauncher()
        onboarding = OnboardingSettings(defaults: persistenceDefaults)
        let integrations: [any CodingAgentIntegration] = uiTesting
            ? CodingAgentRegistry.all.map(UITestingCodingAgentIntegration.init(wrapping:))
            : CodingAgentRegistry.all
        let exchangeRateProvider: any ExchangeRateProviding
        if uiTesting {
            exchangeRateProvider = UITestingExchangeRateProvider()
        } else {
            exchangeRateProvider = ExchangeRateProviderRouter()
        }
        model = UsageModel(
            appearance: appearance,
            localizer: localization.localizer,
            lastKnown: LastKnownUsageStore(defaults: persistenceDefaults),
            integrations: integrations
        )
        odometer = TokenOdometerModel(
            reader: TranscriptTokenReader(
                checkpointStore: TranscriptCheckpointStore()
            ),
            roots: uiTesting ? [] : CodingAgentRegistry.transcriptRoots,
            initialRange: appearance.selectedTokenRange
        )
        currencyModel = CurrencyModel(
            provider: exchangeRateProvider,
            store: ExchangeRateStore(defaults: persistenceDefaults),
            schedulesAutomaticRefresh: !usesIsolatedPersistence
        )
        super.init()
    }

    /// True when this process is hosting the unit-test bundle rather than
    /// serving a user.
    static var isRunningUnitTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    static var isRunningUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // UI tests use a deterministic onboarding window and do not start the
        // Keychain-, network-, or transcript-backed models.
        if Self.isRunningUITests {
            showOnboarding()
            return
        }
        // The test bundle is hosted by this app under the shipped bundle id, so
        // starting up for a test run would read the developer's real Keychain
        // accounts, call both usage endpoints, and overwrite their persisted
        // snapshot — and on a fresh CI runner, where the onboarding flag is
        // unset, it would also present the onboarding window and steal focus.
        // Tests construct the models they need directly.
        guard !Self.isRunningUnitTests else { return }
        model.start()
        if onboarding.completed {
            currencyModel.start()
        } else {
            // The selected public exchange-rate source is the only connection
            // that does not require an account first. Let a new user read (or
            // skip) the disclosure before its first automatic request leaves
            // the Mac.
            showOnboarding()
        }
    }

    /// Present (or re-present) the first-run onboarding flow. Reused for both the
    /// automatic first-launch prompt and the "Run setup again" action in Settings.
    func showOnboarding() {
        if onboardingController == nil {
            onboardingController = OnboardingWindowController(
                model: model,
                onboarding: onboarding,
                locale: localization.effectiveLocale,
                onComplete: { [weak self] in
                    guard let self, !Self.isRunningUITests else { return }
                    self.currencyModel.start()
                }
            )
        }
        onboardingController?.show()
    }
}

/// UI-test dependencies deliberately retain the production presentation
/// metadata while replacing every I/O boundary. This keeps future interaction
/// tests safe even if they navigate beyond the deterministic welcome screen.
private struct UITestingCodingAgentIntegration: CodingAgentIntegration {
    private let wrapped: any CodingAgentIntegration
    let auth: any AgentAuthSession = UITestingAuthSession()

    init(wrapping integration: any CodingAgentIntegration) {
        wrapped = integration
    }

    var id: CodingAgentID { wrapped.id }
    var displayName: String { wrapped.displayName }
    var shortLabel: String { wrapped.shortLabel }
    var brand: AgentBrand { wrapped.brand }
    var signInStyle: SignInStyle { wrapped.signInStyle }
    var gaugeLayout: GaugeLayout { wrapped.gaugeLayout }
    var transcriptRoot: String { wrapped.transcriptRoot }

    func makeProvider() -> UsageProvider { UITestingUsageProvider() }
}

private final class UITestingAuthSession: AgentAuthSession {
    let isSignedIn = false

    func validAccessToken() async throws -> String { "ui-testing" }
    func signOut() {}
    func beginSignIn() async throws {}
}

private struct UITestingUsageProvider: UsageProvider {
    func fetchUsage() async throws -> UsageReading { UsageReading(windows: []) }
}

private struct UITestingExchangeRateProvider: ExchangeRateProviding {
    func fetchRates(from _: ExchangeRateSource) async throws -> [ExchangeRateQuote] {
        [
            ExchangeRateQuote(
                quoteCode: CurrencyCode("CNY")!,
                rate: 7,
                rateDate: Date(timeIntervalSince1970: 0)
            ),
        ]
    }
}

struct TokenStatsCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let localizer: AppLocalizer

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(localizer.localized(Self.settingsCommandTitle)) {
                PopoverView.openSettingsWindow(openWindow)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }

    private static let settingsCommandTitle = LocalizedStringResource.commandSettingsTitle
}
