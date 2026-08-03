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

@main
struct TokenStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var isMenuBarExtraInserted = AppRuntimeMode.current.insertsMenuBarExtra

    var body: some Scene {
        MenuBarExtra(isInserted: $isMenuBarExtraInserted) {
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
    private let runtimeMode: AppRuntimeMode
    private let testingDefaults: InMemoryUserDefaults?
    private var onboardingController: OnboardingWindowController?
#if DEBUG
    private var tokenSummaryHeroLayoutFixtureController: TokenSummaryHeroLayoutFixtureWindowController?
#endif

    override init() {
        // Both models are driven by the registered Coding Agents: the usage
        // model refreshes one per agent, and the Token Odometer scans one
        // transcript root per agent.
        let runtimeMode = AppRuntimeMode.current
        self.runtimeMode = runtimeMode
        let testingDefaults: InMemoryUserDefaults?
        if runtimeMode.usesIsolatedPersistence {
            // Keep explicit `-key value` UI-test launch overrides while never
            // consulting or mutating the user's persistent defaults domain.
            let argumentValues = UserDefaults.standard.volatileDomain(
                forName: UserDefaults.argumentDomain
            )
            testingDefaults = InMemoryUserDefaults(initialValues: argumentValues)
        } else {
            testingDefaults = nil
        }
        self.testingDefaults = testingDefaults
        // Test processes use a process-only store. This remains safe even if a
        // future Xcode configuration accidentally hosts unit tests in the app:
        // CurrencyModel may repair its cache during initialization, but the
        // write cannot reach CFPreferences or the user's production domain.
        let persistenceDefaults: UserDefaults = testingDefaults ?? .standard
        let appearance = AppearanceSettings(defaults: persistenceDefaults)
        localization = LocalizationSettings(defaults: persistenceDefaults)
        relauncher = runtimeMode.usesInertDependencies
            ? AppRelauncher.disabledForTesting()
            : AppRelauncher()
        onboarding = OnboardingSettings(defaults: persistenceDefaults)
        let integrations: [any CodingAgentIntegration] = runtimeMode.usesInertDependencies
            ? CodingAgentRegistry.all.map(TestingCodingAgentIntegration.init(wrapping:))
            : CodingAgentRegistry.all
        let exchangeRateProvider: any ExchangeRateProviding
        if runtimeMode.usesInertDependencies {
            exchangeRateProvider = TestingExchangeRateProvider()
        } else {
            exchangeRateProvider = ExchangeRateProviderRouter()
        }
        model = UsageModel(
            appearance: appearance,
            localizer: localization.localizer,
            lastKnown: LastKnownUsageStore(defaults: persistenceDefaults),
            integrations: integrations
        )
        let transcriptRoots = runtimeMode.usesInertDependencies
            ? []
            : CodingAgentRegistry.transcriptRoots
        let transcriptChangeSource: any TranscriptChangeSource = runtimeMode.usesInertDependencies
            ? InactiveTranscriptChangeSource()
            : FSEventsTranscriptChangeSource(paths: transcriptRoots.map(\.path))
        odometer = TokenOdometerModel(
            reader: TranscriptTokenReader(
                checkpointStore: TranscriptCheckpointStore()
            ),
            roots: transcriptRoots,
            initialRange: appearance.selectedTokenRange,
            changeSource: transcriptChangeSource
        )
        currencyModel = CurrencyModel(
            provider: exchangeRateProvider,
            store: ExchangeRateStore(defaults: persistenceDefaults),
            schedulesAutomaticRefresh: !runtimeMode.usesIsolatedPersistence
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // UI tests use a deterministic onboarding window and do not start the
        // Keychain-, network-, or transcript-backed models.
        if runtimeMode == .uiTesting {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains(
                TokenSummaryHeroLayoutFixtureWindowController.launchArgument
            ) {
                let controller = TokenSummaryHeroLayoutFixtureWindowController()
                tokenSummaryHeroLayoutFixtureController = controller
                controller.show()
                return
            }
#endif
            showOnboarding()
            return
        }
        // The unit suite is unhosted, but fail closed if a future Xcode change
        // starts this app under XCTest: never read real Keychain accounts,
        // contact usage endpoints, overwrite persisted snapshots, or present
        // first-run UI. Tests construct the models they need directly.
        guard runtimeMode == .production else { return }
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
                    guard let self, self.runtimeMode == .production else { return }
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
private struct TestingCodingAgentIntegration: CodingAgentIntegration {
    private let wrapped: any CodingAgentIntegration
    let auth: any AgentAuthSession = TestingAuthSession()

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

    func makeProvider() -> UsageProvider { TestingUsageProvider() }
}

private final class TestingAuthSession: AgentAuthSession {
    let isSignedIn = false

    func validAccessToken() async throws -> String { "ui-testing" }
    func signOut() {}
    func beginSignIn() async throws {}
}

private struct TestingUsageProvider: UsageProvider {
    func fetchUsage() async throws -> UsageReading { UsageReading(windows: []) }
}

private struct TestingExchangeRateProvider: ExchangeRateProviding {
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
