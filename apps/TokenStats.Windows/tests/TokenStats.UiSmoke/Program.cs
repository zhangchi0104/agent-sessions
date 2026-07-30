using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using System.Text.Json;
using TokenStats.App.Controls;
using TokenStats.App.Infrastructure;
using TokenStats.App.Services;
using TokenStats.App.Views;
using TokenStats.Core;

namespace TokenStats.UiSmoke;

internal static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        var temporary = Path.Combine(
            Path.GetTempPath(),
            $"TokenStats.UiSmoke-{Guid.NewGuid():N}");
        Directory.CreateDirectory(temporary);
        try
        {
            var application = new System.Windows.Application
            {
                ShutdownMode = ShutdownMode.OnExplicitShutdown,
            };
            application.Resources.MergedDictionaries.Add(new ResourceDictionary
            {
                Source = new Uri(
                    "pack://application:,,,/TokenStats;component/Themes/Styles.xaml",
                    UriKind.Absolute),
            });
            VerifyThemePalettes(application.Resources);

            var settings = new AppSettingsStore(
                Path.Combine(temporary, "settings.json"));
            settings.SaveAppearance(
                settings.Appearance with
                {
                    GaugeStyle = GaugeStyle.Ring,
                    TodayMetric = TodayMetricMode.Usage,
                    SelectedTokenKinds =
                        TokenKindSelection.DirectInput |
                        TokenKindSelection.CacheRead,
                    TokenValueDisplay =
                        TokenValueDisplayMode.ValueAndPercentage,
                    SelectedTokenRange = TokenRange.ThirtyDays,
                    AlwaysOnTop = true,
                });
            var reloadedSettings = new AppSettingsStore(settings.SettingsPath);
            if (reloadedSettings.Appearance.GaugeStyle != GaugeStyle.Ring ||
                reloadedSettings.Appearance.TodayMetric != TodayMetricMode.Usage ||
                reloadedSettings.Appearance.SelectedTokenKinds !=
                    (TokenKindSelection.DirectInput |
                     TokenKindSelection.CacheRead) ||
                reloadedSettings.Appearance.TokenValueDisplay !=
                    TokenValueDisplayMode.ValueAndPercentage ||
                reloadedSettings.Appearance.SelectedTokenRange !=
                    TokenRange.ThirtyDays ||
                !reloadedSettings.Appearance.AlwaysOnTop ||
                reloadedSettings.Current.Version != AppSettings.CurrentVersion)
            {
                throw new InvalidOperationException(
                    "Windows v3 display settings did not survive an ISO-JSON round trip.");
            }

            var malformedSettingsPath = Path.Combine(
                temporary,
                "malformed-settings.json");
            File.WriteAllText(
                malformedSettingsPath,
                JsonSerializer.Serialize(new
                {
                    version = 2,
                    appearance = new
                    {
                        primaryAgent = "claudeCode",
                        order = new[] { "claudeCode", "codex" },
                        gaugeStyle = "dial",
                    },
                    onboarding = new { completed = true },
                    lastSnapshots = new Dictionary<string, object?>
                    {
                        ["claudeCode"] = new
                        {
                            windows = (object?)null,
                            fetchedAt = DateTimeOffset.Now,
                        },
                    },
                }));
            var sanitizedSettings = new AppSettingsStore(malformedSettingsPath);
            if (sanitizedSettings.LoadLastSnapshot(AgentId.ClaudeCode) is not null)
            {
                throw new InvalidOperationException(
                    "Semantically corrupt cached usage was not discarded.");
            }
            if (sanitizedSettings.Appearance.TodayMetric != TodayMetricMode.Token)
            {
                throw new InvalidOperationException(
                    "Legacy settings did not migrate to the Token counter.");
            }
            if (sanitizedSettings.Current.Version != AppSettings.CurrentVersion ||
                sanitizedSettings.Appearance.SelectedTokenKinds !=
                    TokenKindSelection.All ||
                sanitizedSettings.Appearance.TokenValueDisplay !=
                    TokenValueDisplayMode.Value ||
                sanitizedSettings.Appearance.SelectedTokenRange !=
                    TokenRange.Today ||
                sanitizedSettings.Appearance.AlwaysOnTop)
            {
                throw new InvalidOperationException(
                    "Legacy settings did not receive safe v3 display defaults.");
            }

            settings.SaveAppearance(
                AppearancePreferences.Default with { GaugeStyle = GaugeStyle.Dial });
            var callback = LoopbackAuthListener.ParseRequest(
                "GET /auth/callback?code=abc123&state=state-123 HTTP/1.1\r\n" +
                "Host: localhost:1455\r\n\r\n");
            if (callback.Callback is not { Code: "abc123", State: "state-123" })
            {
                throw new InvalidOperationException(
                    "The loopback OAuth callback parser rejected a valid request.");
            }

            if (LoopbackAuthListener.FallbackPort != 1457 ||
                CodexOAuthFlow.RedirectUri(LoopbackAuthListener.FallbackPort) !=
                "http://localhost:1457/auth/callback")
            {
                throw new InvalidOperationException(
                    "Codex OAuth must use its registered fallback callback port.");
            }

            VerifySmallWorkAreaConstraints();
            VerifyFlyoutPlacement();
            VerifyMissingTranscriptRootRecovery(temporary);
            VerifyWatcherDebounceDrainsWithoutCanceling(temporary);
            VerifyWatcherScanFailureRetries(temporary);
            VerifyDirectoryChangesForceReconciliation(temporary);
            VerifySignOutWinsInFlightRefresh(temporary);

            var auth = AgentRegistry.All.ToDictionary(
                definition => definition.Id,
                _ => (IAgentAuthSession)new ConnectedAuth());
            var providers = AgentRegistry.All.ToDictionary(
                definition => definition.Id,
                definition => (IUsageProvider)new StaticProvider(definition.Id));
            var coordinator = new UsageCoordinator(settings, auth, providers);
            coordinator.StartAsync().GetAwaiter().GetResult();
            var roots = AgentRegistry.All
                .Select(definition => (
                    definition.DisplayName,
                    Path.Combine(temporary, definition.Id.ToString())))
                .ToArray();
            var watcherNow = DateTimeOffset.Now;
            Directory.CreateDirectory(roots[0].Item2);
            var transcript = Path.Combine(roots[0].Item2, "smoke.jsonl");
            File.WriteAllText(
                transcript,
                JsonSerializer.Serialize(new
                {
                    timestamp = watcherNow.ToString("O"),
                    message = new
                    {
                        id = "smoke",
                        model = "claude-sonnet-4-6",
                        usage = new
                        {
                            input_tokens = 100,
                            output_tokens = 50,
                            cache_creation_input_tokens = 0,
                            cache_read_input_tokens = 0,
                        },
                    },
                }) + Environment.NewLine);
            var olderTranscript = Path.Combine(
                roots[0].Item2,
                "smoke-older.jsonl");
            File.WriteAllText(
                olderTranscript,
                JsonSerializer.Serialize(new
                {
                    timestamp = watcherNow.AddDays(-3).ToString("O"),
                    message = new
                    {
                        id = "smoke-older",
                        model = "claude-sonnet-4-6",
                        usage = new
                        {
                            input_tokens = 200,
                            output_tokens = 0,
                            cache_creation_input_tokens = 0,
                            cache_read_input_tokens = 0,
                        },
                    },
                }) + Environment.NewLine);
            File.SetLastWriteTimeUtc(
                olderTranscript,
                watcherNow.UtcDateTime);
            var thirtyDayTranscript = Path.Combine(
                roots[0].Item2,
                "smoke-thirty-day.jsonl");
            File.WriteAllText(
                thirtyDayTranscript,
                JsonSerializer.Serialize(new
                {
                    timestamp = watcherNow.AddDays(-10).ToString("O"),
                    message = new
                    {
                        id = "smoke-thirty-day",
                        model = "claude-opus-4-6",
                        usage = new
                        {
                            input_tokens = 0,
                            output_tokens = 0,
                            cache_creation_input_tokens = 0,
                            cache_read_input_tokens = 900,
                        },
                    },
                }) + Environment.NewLine);
            File.SetLastWriteTimeUtc(
                thirtyDayTranscript,
                watcherNow.UtcDateTime);
            var tokens = new TokenOdometerWatcher(
                new TranscriptTokenReader(),
                roots,
                () => watcherNow);
            tokens.SetVisibleAsync(true).GetAwaiter().GetResult();
            if (tokens.Usage?.TotalTokens != 150)
            {
                throw new InvalidOperationException(
                    "The transcript watcher did not seed the Token Odometer.");
            }
            if (!tokens.HasLoaded ||
                tokens.IsScanning ||
                tokens.SelectedRange != TokenRange.Today ||
                tokens.DisplayedRange != TokenRange.Today ||
                tokens.PendingRange is not null ||
                tokens.PerAgent.Count != roots.Length ||
                tokens.PerAgent[1].Usage is not null)
            {
                throw new InvalidOperationException(
                    "The Token Odometer did not publish a complete, ordered Today state.");
            }

            tokens.SelectRangeAsync(TokenRange.SevenDays)
                .GetAwaiter()
                .GetResult();
            if (tokens.Usage?.OdometerTokens != 350 ||
                tokens.SelectedRange != TokenRange.SevenDays ||
                tokens.DisplayedRange != TokenRange.SevenDays ||
                tokens.PendingRange is not null)
            {
                throw new InvalidOperationException(
                    "The Token Odometer did not land its seven-day range atomically.");
            }

            tokens.SetVisibleAsync(false).GetAwaiter().GetResult();
            tokens.SetVisibleAsync(true).GetAwaiter().GetResult();
            if (tokens.SelectedRange != TokenRange.SevenDays ||
                tokens.DisplayedRange != TokenRange.SevenDays ||
                tokens.Usage?.OdometerTokens != 350)
            {
                throw new InvalidOperationException(
                    "The Token Odometer did not preserve its range after hide/show.");
            }

            tokens.SelectRangeAsync(TokenRange.Today)
                .GetAwaiter()
                .GetResult();
            watcherNow = watcherNow.AddDays(1);
            tokens.SetVisibleAsync(true).GetAwaiter().GetResult();
            if (tokens.SelectedRange != TokenRange.Today ||
                tokens.Usage is not null)
            {
                throw new InvalidOperationException(
                    "The Token Odometer retained the previous local day after midnight.");
            }

            watcherNow = watcherNow.AddDays(-1);
            tokens.SetVisibleAsync(true).GetAwaiter().GetResult();
            VerifyFlyoutDisplayInteractions(coordinator, settings, tokens);

            VerifyRuntimeThemeSwitch(
                coordinator,
                settings,
                tokens,
                application.Resources);
            CaptureThemeMatrix(
                coordinator,
                settings,
                tokens,
                application.Resources,
                args.FirstOrDefault(),
                [WindowsAppTheme.Light, WindowsAppTheme.Dark]);

            tokens.DisposeAsync().AsTask().GetAwaiter().GetResult();
            coordinator.DisposeAsync().AsTask().GetAwaiter().GetResult();
            application.Shutdown();
            Console.WriteLine(
                "PASS WPF windows loaded, switched themes at runtime, " +
                "and completed Light/Dark layout.");
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine("FAIL WPF UI smoke test.");
            Console.Error.WriteLine(exception);
            return 1;
        }
        finally
        {
            if (Directory.Exists(temporary))
            {
                Directory.Delete(temporary, recursive: true);
            }
        }
    }

    private static void VerifyThemePalettes(ResourceDictionary resources)
    {
        var notifications = new List<WindowsAppTheme>();
        EventHandler handler = (_, _) =>
            notifications.Add(WindowsThemeService.CurrentTheme);
        WindowsThemeService.ThemeChanged += handler;
        try
        {
            VerifyThemePalette(
                resources,
                WindowsAppTheme.Light,
                new Dictionary<string, Color>
                {
                    ["WindowBackgroundBrush"] = Rgb(0xF9, 0xFA, 0xFB),
                    ["CardBackgroundBrush"] = Rgb(0xFF, 0xFF, 0xFF),
                    ["SubtleBackgroundBrush"] = Rgb(0xF1, 0xF3, 0xF5),
                    ["ControlBackgroundBrush"] = Rgb(0xFF, 0xFF, 0xFF),
                    ["ControlHoverBrush"] = Rgb(0xEA, 0xED, 0xF0),
                    ["ControlPressedBrush"] = Rgb(0xDD, 0xE2, 0xE7),
                    ["PrimaryTextBrush"] = Rgb(0x17, 0x19, 0x1C),
                    ["SecondaryTextBrush"] = Rgb(0x62, 0x67, 0x6F),
                    ["DisabledTextBrush"] = Rgb(0x98, 0x9D, 0xA4),
                    ["BorderBrush"] = Rgb(0xD9, 0xDC, 0xE1),
                    ["AccentBrush"] = Rgb(0x08, 0x86, 0x6D),
                    ["AccentForegroundBrush"] = Rgb(0xFF, 0xFF, 0xFF),
                    ["AccentSoftBrush"] = Argb(0x1F, 0x08, 0x86, 0x6D),
                    ["SelectionBrush"] = Rgb(0x08, 0x86, 0x6D),
                    ["SelectionTextBrush"] = Rgb(0xFF, 0xFF, 0xFF),
                    ["SelectedItemBackgroundBrush"] =
                        Argb(0x1F, 0x08, 0x86, 0x6D),
                    ["SelectedItemTextBrush"] = Rgb(0x08, 0x86, 0x6D),
                    ["DangerBrush"] = Rgb(0xC9, 0x37, 0x37),
                    ["WarningBrush"] = Rgb(0xA6, 0x68, 0x00),
                    ["TokenInputBrush"] = Rgb(0x21, 0x6B, 0xC7),
                    ["TokenOutputBrush"] = Rgb(0x17, 0x78, 0x59),
                    ["TokenCacheWriteBrush"] = Rgb(0x9E, 0x6B, 0x0F),
                    ["TokenCacheReadBrush"] = Rgb(0x66, 0x5C, 0x9E),
                    ["TooltipBackgroundBrush"] = Rgb(0xFF, 0xFF, 0xFF),
                });
            VerifyThemePalette(
                resources,
                WindowsAppTheme.Dark,
                new Dictionary<string, Color>
                {
                    ["WindowBackgroundBrush"] = Rgb(0x20, 0x22, 0x25),
                    ["CardBackgroundBrush"] = Rgb(0x2B, 0x2E, 0x32),
                    ["SubtleBackgroundBrush"] = Rgb(0x25, 0x28, 0x2C),
                    ["ControlBackgroundBrush"] = Rgb(0x30, 0x34, 0x39),
                    ["ControlHoverBrush"] = Rgb(0x39, 0x3E, 0x44),
                    ["ControlPressedBrush"] = Rgb(0x43, 0x49, 0x50),
                    ["PrimaryTextBrush"] = Rgb(0xF3, 0xF4, 0xF5),
                    ["SecondaryTextBrush"] = Rgb(0xB3, 0xB8, 0xC0),
                    ["DisabledTextBrush"] = Rgb(0x7D, 0x83, 0x8B),
                    ["BorderBrush"] = Rgb(0x46, 0x4A, 0x50),
                    ["AccentBrush"] = Rgb(0x45, 0xD0, 0xAD),
                    ["AccentForegroundBrush"] = Rgb(0x0B, 0x25, 0x1E),
                    ["AccentSoftBrush"] = Argb(0x30, 0x45, 0xD0, 0xAD),
                    ["SelectionBrush"] = Rgb(0x36, 0xA9, 0x8D),
                    ["SelectionTextBrush"] = Rgb(0x08, 0x1F, 0x19),
                    ["SelectedItemBackgroundBrush"] =
                        Argb(0x30, 0x45, 0xD0, 0xAD),
                    ["SelectedItemTextBrush"] = Rgb(0x45, 0xD0, 0xAD),
                    ["DangerBrush"] = Rgb(0xFF, 0x7B, 0x72),
                    ["WarningBrush"] = Rgb(0xF1, 0xC7, 0x5B),
                    ["TokenInputBrush"] = Rgb(0x4A, 0x99, 0xF0),
                    ["TokenOutputBrush"] = Rgb(0x38, 0xAD, 0x87),
                    ["TokenCacheWriteBrush"] = Rgb(0xD9, 0x9E, 0x38),
                    ["TokenCacheReadBrush"] = Rgb(0x8F, 0x85, 0xBF),
                    ["TooltipBackgroundBrush"] = Rgb(0x38, 0x3C, 0x42),
                });
            VerifyThemePalette(
                resources,
                WindowsAppTheme.HighContrast,
                new Dictionary<string, Color>
                {
                    ["WindowBackgroundBrush"] = SystemColors.WindowColor,
                    ["CardBackgroundBrush"] = SystemColors.WindowColor,
                    ["SubtleBackgroundBrush"] = SystemColors.ControlColor,
                    ["ControlBackgroundBrush"] = SystemColors.WindowColor,
                    ["ControlHoverBrush"] = SystemColors.HighlightColor,
                    ["ControlPressedBrush"] = SystemColors.HotTrackColor,
                    ["PrimaryTextBrush"] = SystemColors.WindowTextColor,
                    ["SecondaryTextBrush"] = SystemColors.GrayTextColor,
                    ["DisabledTextBrush"] = SystemColors.GrayTextColor,
                    ["BorderBrush"] = SystemColors.WindowTextColor,
                    ["AccentBrush"] = SystemColors.HighlightColor,
                    ["AccentForegroundBrush"] = SystemColors.HighlightTextColor,
                    ["AccentSoftBrush"] = SystemColors.ControlColor,
                    ["SelectionBrush"] = SystemColors.HighlightColor,
                    ["SelectionTextBrush"] = SystemColors.HighlightTextColor,
                    ["SelectedItemBackgroundBrush"] =
                        SystemColors.HighlightColor,
                    ["SelectedItemTextBrush"] =
                        SystemColors.HighlightTextColor,
                    ["DangerBrush"] = SystemColors.HotTrackColor,
                    ["WarningBrush"] = SystemColors.HotTrackColor,
                    ["TokenInputBrush"] = SystemColors.HighlightColor,
                    ["TokenOutputBrush"] = SystemColors.HotTrackColor,
                    ["TokenCacheWriteBrush"] = SystemColors.WindowTextColor,
                    ["TokenCacheReadBrush"] = SystemColors.GrayTextColor,
                    ["TooltipBackgroundBrush"] = SystemColors.InfoColor,
                });
        }
        finally
        {
            WindowsThemeService.ThemeChanged -= handler;
        }

        if (!notifications.SequenceEqual(
                new[]
                {
                    WindowsAppTheme.Light,
                    WindowsAppTheme.Dark,
                    WindowsAppTheme.HighContrast,
                }))
        {
            throw new InvalidOperationException(
                "ThemeChanged did not report every explicitly applied theme.");
        }

        WindowsThemeService.Apply(resources, WindowsAppTheme.Light);
    }

    private static void VerifyThemePalette(
        ResourceDictionary resources,
        WindowsAppTheme theme,
        IReadOnlyDictionary<string, Color> expected)
    {
        WindowsThemeService.Apply(resources, theme);
        if (WindowsThemeService.CurrentTheme != theme)
        {
            throw new InvalidOperationException(
                $"The active Windows theme was not updated to {theme}.");
        }

        foreach (var (key, expectedColor) in expected)
        {
            if (resources[key] is not SolidColorBrush brush)
            {
                throw new InvalidOperationException(
                    $"{theme} theme resource '{key}' is not a solid brush.");
            }

            if (brush.Color != expectedColor)
            {
                throw new InvalidOperationException(
                    $"{theme} theme resource '{key}' was {brush.Color}, " +
                    $"expected {expectedColor}.");
            }

        }
    }

    private static void VerifyFlyoutDisplayInteractions(
        UsageCoordinator coordinator,
        AppSettingsStore settings,
        TokenOdometerWatcher tokens)
    {
        settings.SaveAppearance(
            settings.Appearance with
            {
                TodayMetric = TodayMetricMode.Token,
                SelectedTokenKinds = TokenKindSelection.All,
                TokenValueDisplay = TokenValueDisplayMode.Value,
                SelectedTokenRange = TokenRange.Today,
                AlwaysOnTop = false,
            });
        tokens.SelectRangeAsync(TokenRange.Today).GetAwaiter().GetResult();
        tokens.SetVisibleAsync(true).GetAwaiter().GetResult();

        var flyout = new FlyoutWindow(
            coordinator,
            settings,
            tokens,
            () => { },
            () => { })
        {
            ShowActivated = false,
        };
        try
        {
            flyout.ShowFlyout();
            PumpDispatcher(flyout.Dispatcher);
            flyout.UpdateLayout();
            var tokensTab = FindNamed<RadioButton>(flyout, "TokensTabButton");
            var apiMetric = FindNamed<RadioButton>(flyout, "ApiMetricButton");
            var billingMetric =
                FindNamed<RadioButton>(flyout, "BillingMetricButton");
            var sevenDays =
                FindNamed<RadioButton>(flyout, "SevenDaysRangeButton");
            var pin = FindNamed<ToggleButton>(flyout, "PinButton");
            var summaryValue =
                FindNamed<RollingNumberText>(flyout, "TokenSummaryValue");
            var summaryPeer =
                UIElementAutomationPeer.CreatePeerForElement(summaryValue) ??
                throw new InvalidOperationException(
                    "The rolling token summary did not create an automation peer.");
            if (summaryPeer.GetAutomationControlType() !=
                    AutomationControlType.Text ||
                summaryPeer.GetName() != summaryValue.Text ||
                summaryValue.Focusable ||
                summaryValue.IsTabStop)
            {
                throw new InvalidOperationException(
                    "The rolling token summary automation peer did not expose " +
                    "its final text as a non-focusable Text control.");
            }

            var tableTotal =
                FindNamed<TextBlock>(flyout, "TokenTableTotal");
            var kindButtons = new[]
            {
                FindNamed<ToggleButton>(flyout, "DirectInputKindButton"),
                FindNamed<ToggleButton>(flyout, "OutputKindButton"),
                FindNamed<ToggleButton>(flyout, "CacheWriteKindButton"),
                FindNamed<ToggleButton>(flyout, "CacheReadKindButton"),
            };

            tokensTab.IsChecked = true;
            PumpDispatcher(flyout.Dispatcher);
            if (kindButtons.Any(button =>
                    button.IsChecked != true ||
                    !button.Focusable ||
                    string.IsNullOrWhiteSpace(
                        AutomationProperties.GetName(button))))
            {
                throw new InvalidOperationException(
                    "Token Kind filters must start selected and expose keyboard/UIA controls.");
            }

            if (FindTokenCell(flyout, "Direct input").Text != "100" ||
                FindTokenCell(flyout, "Output").Text != "50" ||
                FindTokenCell(flyout, "Cache write").Text != "–" ||
                FindTokenCell(flyout, "Cache read").Text != "–")
            {
                throw new InvalidOperationException(
                    "Value mode did not render the four Token Kind cells.");
            }
            if (EnumerateVisualDescendants<TextBlock>(flyout).Any(text =>
                    text.Text ==
                    "IN direct input · OUT output · C·W cache write · C·R cache read"))
            {
                throw new InvalidOperationException(
                    "The redundant Token Kind explanation row is still visible.");
            }

            var billingRevisionBeforeApi =
                summaryValue.TransitionRevision;
            apiMetric.IsChecked = true;
            PumpDispatcher(flyout.Dispatcher);
            var apiSummaryBeforeFilter = summaryValue.Text;
            var apiRevision = summaryValue.TransitionRevision;
            if (apiRevision <= billingRevisionBeforeApi ||
                settings.Appearance.TodayMetric != TodayMetricMode.Usage ||
                !apiSummaryBeforeFilter.StartsWith("$", StringComparison.Ordinal) ||
                summaryPeer.GetName() != apiSummaryBeforeFilter ||
                summaryValue.IsRolling ||
                new AppSettingsStore(settings.SettingsPath)
                    .Appearance.TodayMetric != TodayMetricMode.Usage)
            {
                throw new InvalidOperationException(
                    "The API-equivalent metric switch did not revise and " +
                    "settle the summary without rolling before persisting.");
            }

            billingMetric.IsChecked = true;
            PumpDispatcher(flyout.Dispatcher);
            var billingRevision = summaryValue.TransitionRevision;
            if (billingRevision <= apiRevision ||
                settings.Appearance.TodayMetric != TodayMetricMode.Token ||
                summaryValue.Text != "150" ||
                summaryValue.IsRolling)
            {
                throw new InvalidOperationException(
                    "The Billing metric switch did not revise and settle the " +
                    "summary at 150 without rolling.");
            }

            apiMetric.IsChecked = true;
            PumpDispatcher(flyout.Dispatcher);
            var filteredApiRevision = summaryValue.TransitionRevision;
            if (filteredApiRevision <= billingRevision ||
                summaryValue.IsRolling)
            {
                throw new InvalidOperationException(
                    "Switching back to API equivalent did not revise and " +
                    "settle the summary without rolling.");
            }

            kindButtons[1].IsChecked = false;
            PumpDispatcher(flyout.Dispatcher);
            var excludedOutput = FindTokenCell(flyout, "Output");
            if (settings.Appearance.SelectedTokenKinds !=
                    (TokenKindSelection.All & ~TokenKindSelection.Output) ||
                kindButtons[1].IsChecked != false ||
                summaryValue.Text != apiSummaryBeforeFilter ||
                excludedOutput.Text != "50" ||
                Math.Abs(excludedOutput.Opacity - 0.32) > 0.01 ||
                !tableTotal.Text.Contains("3 selected kinds", StringComparison.Ordinal) ||
                tokens.Usage?.OdometerTokens != 150)
            {
                throw new InvalidOperationException(
                    "Filtering Output did not preserve its dimmed raw value, " +
                    "API equivalent, and the raw Token Odometer.");
            }

            var filteredRevisionBeforeBilling =
                summaryValue.TransitionRevision;
            billingMetric.IsChecked = true;
            PumpDispatcher(flyout.Dispatcher);
            if (settings.Appearance.TodayMetric != TodayMetricMode.Token ||
                summaryValue.Text != "150" ||
                summaryValue.TransitionRevision <=
                    filteredRevisionBeforeBilling ||
                summaryValue.IsRolling ||
                new AppSettingsStore(settings.SettingsPath)
                    .Appearance.TodayMetric != TodayMetricMode.Token)
            {
                throw new InvalidOperationException(
                    "Token Kind filtering changed Billing tokens, or the " +
                    "metric switch rolled instead of settling immediately.");
            }

            settings.SaveAppearance(
                settings.Appearance with
                {
                    TokenValueDisplay = TokenValueDisplayMode.Percentage,
                });
            PumpDispatcher(flyout.Dispatcher);
            excludedOutput = FindTokenCell(flyout, "Output");
            if (FindTokenCell(flyout, "Direct input").Text != "100%" ||
                excludedOutput.Text != "50" ||
                Math.Abs(excludedOutput.Opacity - 0.32) > 0.01)
            {
                throw new InvalidOperationException(
                    "Percentage mode did not keep excluded Output as a dimmed raw value.");
            }

            settings.SaveAppearance(
                settings.Appearance with
                {
                    TokenValueDisplay =
                        TokenValueDisplayMode.ValueAndPercentage,
                });
            PumpDispatcher(flyout.Dispatcher);
            excludedOutput = FindTokenCell(flyout, "Output");
            if (FindTokenCell(flyout, "Direct input").Text !=
                    "100\n(100%)" ||
                excludedOutput.Text != "50" ||
                Math.Abs(excludedOutput.Opacity - 0.32) > 0.01)
            {
                throw new InvalidOperationException(
                    "Value-and-percentage mode added a percentage to excluded Output.");
            }

            settings.SaveAppearance(
                settings.Appearance with
                {
                    TokenValueDisplay = TokenValueDisplayMode.Value,
                });
            PumpDispatcher(flyout.Dispatcher);
            excludedOutput = FindTokenCell(flyout, "Output");
            if (excludedOutput.Text != "50" ||
                Math.Abs(excludedOutput.Opacity - 0.32) > 0.01 ||
                summaryValue.Text != "150" ||
                tokens.Usage?.OdometerTokens != 150)
            {
                throw new InvalidOperationException(
                    "Value mode or Billing summary lost the excluded raw Output.");
            }

            if (flyout.Topmost || pin.IsChecked == true || !pin.Focusable)
            {
                throw new InvalidOperationException(
                    "The flyout did not start in an accessible, unpinned state.");
            }

            pin.IsChecked = true;
            PumpDispatcher(flyout.Dispatcher);
            if (!flyout.Topmost ||
                !settings.Appearance.AlwaysOnTop ||
                AutomationProperties.GetName(pin) != "Unpin flyout" ||
                !new AppSettingsStore(settings.SettingsPath)
                    .Appearance.AlwaysOnTop)
            {
                throw new InvalidOperationException(
                    "Pinning did not enable and persist always-on-top behavior.");
            }

            pin.IsChecked = false;
            PumpDispatcher(flyout.Dispatcher);
            if (flyout.Topmost || settings.Appearance.AlwaysOnTop)
            {
                throw new InvalidOperationException(
                    "Unpinning did not restore notification-area flyout behavior.");
            }

            sevenDays.IsChecked = true;
            WaitForUi(
                flyout.Dispatcher,
                () =>
                    tokens.SelectedRange == TokenRange.SevenDays &&
                    tokens.DisplayedRange == TokenRange.SevenDays &&
                    tokens.PendingRange is null,
                "The seven-day flyout range did not finish scanning.");
            if (settings.Appearance.SelectedTokenRange != TokenRange.SevenDays ||
                new AppSettingsStore(settings.SettingsPath)
                    .Appearance.SelectedTokenRange != TokenRange.SevenDays)
            {
                throw new InvalidOperationException(
                    "The flyout range choice was not persisted.");
            }

            VerifyThirtyDayTokenTableGrowthAndFallback(
                flyout,
                settings,
                tokens,
                summaryValue);
        }
        finally
        {
            settings.SaveAppearance(
                settings.Appearance with
                {
                    TodayMetric = TodayMetricMode.Token,
                    SelectedTokenKinds = TokenKindSelection.All,
                    TokenValueDisplay = TokenValueDisplayMode.Value,
                    SelectedTokenRange = TokenRange.Today,
                    AlwaysOnTop = false,
                });
            tokens.SelectRangeAsync(TokenRange.Today).GetAwaiter().GetResult();
            flyout.AllowClose();
            flyout.Close();
        }
    }

    private static void VerifyThirtyDayTokenTableGrowthAndFallback(
        FlyoutWindow flyout,
        AppSettingsStore settings,
        TokenOdometerWatcher tokens,
        RollingNumberText summaryValue)
    {
        settings.SaveAppearance(
            settings.Appearance with
            {
                SelectedTokenKinds = TokenKindSelection.All,
                TokenValueDisplay =
                    TokenValueDisplayMode.ValueAndPercentage,
            });
        PumpDispatcher(flyout.Dispatcher);

        var tokensScroll =
            FindNamed<ScrollViewer>(flyout, "TokensContentScroll");
        flyout.UpdateLayout();
        PumpDispatcher(flyout.Dispatcher);
        flyout.UpdateLayout();
        var sevenDayHeight = flyout.ActualHeight;
        var sevenDayExtentHeight = tokensScroll.ExtentHeight;
        if (tokens.SelectedRange != TokenRange.SevenDays ||
            tokensScroll.ComputedVerticalScrollBarVisibility ==
                Visibility.Visible)
        {
            throw new InvalidOperationException(
                "The seven-day Value (percentage) growth baseline was " +
                "unexpectedly constrained.");
        }

        var sevenDaySummaryText = summaryValue.Text;
        var sevenDaySummaryRevision =
            summaryValue.TransitionRevision;
        var thirtyDays =
            FindNamed<RadioButton>(flyout, "ThirtyDaysRangeButton");
        var sawThirtyDayRolling = false;
        thirtyDays.IsChecked = true;
        WaitForUi(
            flyout.Dispatcher,
            () =>
            {
                sawThirtyDayRolling |=
                    summaryValue.TransitionRevision >
                        sevenDaySummaryRevision &&
                    summaryValue.IsRolling;
                return
                    tokens.SelectedRange == TokenRange.ThirtyDays &&
                    tokens.DisplayedRange == TokenRange.ThirtyDays &&
                    tokens.PendingRange is null &&
                    tokens.Usage?.CacheReadTokens == 900 &&
                    summaryValue.TransitionRevision >
                        sevenDaySummaryRevision;
            },
            "The 30-day viewport fixture did not finish scanning.");
        if (sevenDaySummaryText != "350" ||
            summaryValue.Text != sevenDaySummaryText ||
            summaryValue.TransitionRevision <= sevenDaySummaryRevision ||
            SystemParameters.ClientAreaAnimation &&
                !sawThirtyDayRolling)
        {
            throw new InvalidOperationException(
                "Landing the 30-day range did not roll the unchanged 350 " +
                "Billing text when client-area animations were enabled.");
        }

        WaitForUi(
            flyout.Dispatcher,
            () =>
            {
                flyout.UpdateLayout();
                return
                    tokensScroll.ExtentHeight >
                        sevenDayExtentHeight + 0.5 &&
                    flyout.ActualHeight > sevenDayHeight + 0.5;
            },
            "The flyout did not grow to show the larger 30-day token table.");
        flyout.UpdateLayout();

        if (settings.Appearance.TokenValueDisplay !=
                TokenValueDisplayMode.ValueAndPercentage ||
            settings.Appearance.SelectedTokenRange != TokenRange.ThirtyDays ||
            tokensScroll.ComputedVerticalScrollBarVisibility ==
                Visibility.Visible ||
            tokensScroll.ExtentHeight > tokensScroll.ViewportHeight + 0.5)
        {
            throw new InvalidOperationException(
                "The 30-day Value (percentage) flyout did not prefer window " +
                $"growth: seven-day window={sevenDayHeight:0.###}, " +
                $"30-day window={flyout.ActualHeight:0.###}, " +
                $"extent={tokensScroll.ExtentHeight:0.###}, " +
                $"viewport={tokensScroll.ViewportHeight:0.###}, " +
                "vertical scrollbar=" +
                $"{tokensScroll.ComputedVerticalScrollBarVisibility}.");
        }

        VerifyStableTokenSummaryRefresh(
            flyout.Dispatcher,
            tokens,
            summaryValue);

        var cacheReadCell = EnumerateVisualDescendants<TextBlock>(flyout)
            .FirstOrDefault(text =>
                text.ToolTip is string tooltip &&
                tooltip.StartsWith(
                    "Cache read: 900 ",
                    StringComparison.Ordinal) &&
                text.Text.Contains('\n')) ??
            throw new InvalidOperationException(
                "The 30-day Cache Read value-and-percentage cell was not rendered.");

        VerifyConstrainedTokenTableFallback(
            flyout,
            tokensScroll,
            cacheReadCell);
    }

    private static void VerifyStableTokenSummaryRefresh(
        Dispatcher dispatcher,
        TokenOdometerWatcher tokens,
        RollingNumberText summaryValue)
    {
        var expectedText = summaryValue.Text;
        var expectedRevision = summaryValue.TransitionRevision;
        for (var refresh = 0; refresh < 2; refresh++)
        {
            tokens.RefreshAsync().GetAwaiter().GetResult();
            PumpDispatcher(dispatcher);
            if (tokens.IsScanning ||
                summaryValue.Text != expectedText ||
                summaryValue.TransitionRevision != expectedRevision)
            {
                throw new InvalidOperationException(
                    "Refreshing an unchanged token summary revised its " +
                    $"transition on pass {refresh + 1}: " +
                    $"text='{summaryValue.Text}', expected='{expectedText}', " +
                    $"revision={summaryValue.TransitionRevision}, " +
                    $"expected revision={expectedRevision}.");
            }
        }
    }

    private static void VerifyConstrainedTokenTableFallback(
        FlyoutWindow flyout,
        ScrollViewer tokensScroll,
        TextBlock cacheReadCell)
    {
        tokensScroll.Height = 180;
        try
        {
            flyout.UpdateLayout();
            WaitForUi(
                flyout.Dispatcher,
                () =>
                    tokensScroll.ComputedVerticalScrollBarVisibility ==
                        Visibility.Visible,
                "The extremely constrained token table did not fall back " +
                "to a vertical scrollbar.");
            flyout.UpdateLayout();

            cacheReadCell.BringIntoView();
            PumpDispatcher(flyout.Dispatcher);
            flyout.UpdateLayout();

            var viewport = FindVisualDescendant<ScrollContentPresenter>(
                tokensScroll,
                _ => true);
            var verticalScrollBar = FindVisualDescendant<ScrollBar>(
                tokensScroll,
                scrollBar =>
                    scrollBar.Orientation == Orientation.Vertical &&
                    scrollBar.Visibility == Visibility.Visible &&
                    scrollBar.ActualWidth > 0);
            var cellBounds = cacheReadCell
                .TransformToAncestor(tokensScroll)
                .TransformBounds(new Rect(cacheReadCell.RenderSize));
            var viewportBounds = viewport
                .TransformToAncestor(tokensScroll)
                .TransformBounds(new Rect(viewport.RenderSize));
            var scrollBarBounds = verticalScrollBar
                .TransformToAncestor(tokensScroll)
                .TransformBounds(new Rect(verticalScrollBar.RenderSize));
            const double layoutTolerance = 0.5;
            if (cellBounds.Left < viewportBounds.Left - layoutTolerance ||
                cellBounds.Right > viewportBounds.Right + layoutTolerance ||
                cellBounds.Right > scrollBarBounds.Left + layoutTolerance ||
                tokensScroll.ScrollableWidth > layoutTolerance)
            {
                throw new InvalidOperationException(
                    "The constrained fallback allowed the 30-day Cache Read " +
                    $"cell to escape its visible viewport: cell={cellBounds}, " +
                    $"viewport={viewportBounds}, vertical scrollbar=" +
                    $"{scrollBarBounds}, scrollable width=" +
                    $"{tokensScroll.ScrollableWidth:0.###}.");
            }
        }
        finally
        {
            tokensScroll.ClearValue(FrameworkElement.HeightProperty);
            flyout.UpdateLayout();
            PumpDispatcher(flyout.Dispatcher);
        }
    }

    private static void VerifyRuntimeThemeSwitch(
        UsageCoordinator coordinator,
        AppSettingsStore settings,
        TokenOdometerWatcher tokens,
        ResourceDictionary resources)
    {
        WindowsThemeService.Apply(resources, WindowsAppTheme.Light);
        tokens.SetVisibleAsync(true).GetAwaiter().GetResult();
        var flyout = new FlyoutWindow(
            coordinator,
            settings,
            tokens,
            () => { },
            () => { })
        {
            ShowActivated = false,
        };
        try
        {
            ShowAndCompleteLayout(flyout);
            var usageTab =
                flyout.FindName("UsageTabButton") as RadioButton ??
                throw new InvalidOperationException(
                    "Usage tab button could not be found.");
            var tokensTab =
                flyout.FindName("TokensTabButton") as RadioButton ??
                throw new InvalidOperationException(
                    "Tokens tab button could not be found.");
            var rangeButton =
                flyout.FindName("SevenDaysRangeButton") as RadioButton ??
                throw new InvalidOperationException(
                    "Token range button could not be found.");
            if (!usageTab.Focusable ||
                !tokensTab.Focusable ||
                !rangeButton.Focusable)
            {
                throw new InvalidOperationException(
                    "Flyout navigation must use keyboard-focusable controls.");
            }

            var status = FindVisualDescendant<TextBlock>(
                flyout,
                text => text.Text.StartsWith(
                    "Updated ",
                    StringComparison.Ordinal));
            var separator = FindVisualDescendant<Border>(
                flyout,
                border =>
                    Math.Abs(border.Height - 1) < 0.01 &&
                    border.Margin.Top >= 14);
            var gauge = FindVisualDescendant<UsageGauge>(flyout, _ => true);
            var summaryLabel =
                flyout.FindName("TokenSummaryLabel") as TextBlock ??
                throw new InvalidOperationException(
                    "Token summary label could not be found.");

            AssertBrushColor(
                status.Foreground,
                Rgb(0x62, 0x67, 0x6F),
                "Light dynamic status text");
            AssertBrushColor(
                separator.Background,
                Rgb(0xD9, 0xDC, 0xE1),
                "Light generated separator");
            AssertBrushColor(
                summaryLabel.Foreground,
                Rgb(0x62, 0x67, 0x6F),
                "Light DynamicResource text");
            var lightGauge = RenderVisual(gauge);

            tokensTab.IsChecked = true;
            FlushThemeChange(flyout);
            var usageScroll =
                flyout.FindName("UsageContentScroll") as ScrollViewer ??
                throw new InvalidOperationException(
                    "Usage scroll view could not be found.");
            var tokensScroll =
                flyout.FindName("TokensContentScroll") as ScrollViewer ??
                throw new InvalidOperationException(
                    "Tokens scroll view could not be found.");
            if (usageScroll.Visibility != Visibility.Collapsed ||
                tokensScroll.Visibility != Visibility.Visible)
            {
                throw new InvalidOperationException(
                    "Tokens tab did not replace the Usage gauge content.");
            }

            AssertTokenColumnColors(
                flyout,
                [
                    Rgb(0x21, 0x6B, 0xC7),
                    Rgb(0x17, 0x78, 0x59),
                    Rgb(0x9E, 0x6B, 0x0F),
                    Rgb(0x66, 0x5C, 0x9E),
                ],
                "Light");
            _ = FindVisualDescendant<TextBlock>(
                flyout,
                text => text.Text == "–" && Grid.GetColumn(text) == 3);

            WindowsThemeService.Apply(resources, WindowsAppTheme.Dark);
            FlushThemeChange(flyout);
            status = FindVisualDescendant<TextBlock>(
                flyout,
                text => text.Text.StartsWith(
                    "Updated ",
                    StringComparison.Ordinal));
            separator = FindVisualDescendant<Border>(
                flyout,
                border =>
                    Math.Abs(border.Height - 1) < 0.01 &&
                    border.Margin.Top >= 14);
            gauge = FindVisualDescendant<UsageGauge>(flyout, _ => true);
            AssertBrushColor(
                status.Foreground,
                Rgb(0xB3, 0xB8, 0xC0),
                "Dark dynamic status text");
            AssertBrushColor(
                separator.Background,
                Rgb(0x46, 0x4A, 0x50),
                "Dark generated separator");
            AssertBrushColor(
                summaryLabel.Foreground,
                Rgb(0xB3, 0xB8, 0xC0),
                "Dark DynamicResource text");
            AssertTokenColumnColors(
                flyout,
                [
                    Rgb(0x4A, 0x99, 0xF0),
                    Rgb(0x38, 0xAD, 0x87),
                    Rgb(0xD9, 0x9E, 0x38),
                    Rgb(0x8F, 0x85, 0xBF),
                ],
                "Dark");
            usageTab.IsChecked = true;
            FlushThemeChange(flyout);
            gauge = FindVisualDescendant<UsageGauge>(flyout, _ => true);
            var darkGauge = RenderVisual(gauge);
            AssertSnapshotsDiffer(
                "UsageGauge runtime Light/Dark switch",
                lightGauge,
                darkGauge);

            WindowsThemeService.Apply(resources, WindowsAppTheme.Light);
            FlushThemeChange(flyout);
            status = FindVisualDescendant<TextBlock>(
                flyout,
                text => text.Text.StartsWith(
                    "Updated ",
                    StringComparison.Ordinal));
            separator = FindVisualDescendant<Border>(
                flyout,
                border =>
                    Math.Abs(border.Height - 1) < 0.01 &&
                    border.Margin.Top >= 14);
            AssertBrushColor(
                status.Foreground,
                Rgb(0x62, 0x67, 0x6F),
                "Restored Light dynamic status text");
            AssertBrushColor(
                separator.Background,
                Rgb(0xD9, 0xDC, 0xE1),
                "Restored Light generated separator");
        }
        finally
        {
            tokens.SetVisibleAsync(false).GetAwaiter().GetResult();
            flyout.AllowClose();
            flyout.Close();
            WindowsThemeService.Apply(resources, WindowsAppTheme.Light);
        }
    }

    private static void AssertTokenColumnColors(
        DependencyObject root,
        IReadOnlyList<Color> expected,
        string theme)
    {
        var labels = new[] { "IN", "OUT", "C·W", "C·R" };
        for (var index = 0; index < labels.Length; index++)
        {
            var heading = FindVisualDescendant<TextBlock>(
                root,
                text => text.Text == labels[index]);
            AssertBrushColor(
                heading.Foreground,
                expected[index],
                $"{theme} {labels[index]} token column");
        }

        var proportionBar = FindVisualDescendant<Grid>(
            root,
            grid =>
                Math.Abs(grid.Height - 4) < 0.01 &&
                VisualTreeHelper.GetChildrenCount(grid) == 4);
        for (var index = 0; index < expected.Count; index++)
        {
            if (VisualTreeHelper.GetChild(proportionBar, index) is not
                Border segment)
            {
                throw new InvalidOperationException(
                    $"{theme} token proportion segment {index} is missing.");
            }

            AssertBrushColor(
                segment.Background,
                expected[index],
                $"{theme} token proportion segment {labels[index]}");
        }
    }

    private static void CaptureThemeMatrix(
        UsageCoordinator coordinator,
        AppSettingsStore settings,
        TokenOdometerWatcher tokens,
        ResourceDictionary resources,
        string? snapshotDirectory,
        IReadOnlyList<WindowsAppTheme> themes)
    {
        var snapshots = new Dictionary<
            WindowsAppTheme,
            IReadOnlyDictionary<string, RenderedSnapshot>>();
        foreach (var theme in themes)
        {
            WindowsThemeService.Apply(resources, theme);
            snapshots[theme] = CaptureTheme(
                coordinator,
                settings,
                tokens,
                snapshotDirectory,
                theme);
        }

        var light = snapshots[WindowsAppTheme.Light];
        var dark = snapshots[WindowsAppTheme.Dark];
        foreach (var scene in light.Keys)
        {
            AssertSnapshotsDiffer(
                $"{scene} Light/Dark screenshot",
                light[scene],
                dark[scene]);
        }

        settings.SaveAppearance(
            settings.Appearance with
            {
                TodayMetric = TodayMetricMode.Usage,
            });
        WindowsThemeService.Apply(resources, WindowsAppTheme.Light);
    }

    private static IReadOnlyDictionary<string, RenderedSnapshot> CaptureTheme(
        UsageCoordinator coordinator,
        AppSettingsStore settings,
        TokenOdometerWatcher tokens,
        string? snapshotDirectory,
        WindowsAppTheme theme)
    {
        var snapshots = new Dictionary<string, RenderedSnapshot>();
        var background = theme == WindowsAppTheme.Dark
            ? Rgb(0x20, 0x22, 0x25)
            : Rgb(0xF9, 0xFA, 0xFB);
        var suffix = theme.ToString().ToLowerInvariant();

        settings.SaveAppearance(
            settings.Appearance with
            {
                TodayMetric = TodayMetricMode.Usage,
            });
        var flyout = new FlyoutWindow(
            coordinator,
            settings,
            tokens,
            () => { },
            () => { });
        try
        {
            snapshots["flyout"] = ShowAndLayout(
                flyout,
                snapshotDirectory,
                background,
                SnapshotNames("flyout", suffix, theme));
        }
        finally
        {
            flyout.AllowClose();
            flyout.Close();
        }

        settings.SaveAppearance(
            settings.Appearance with
            {
                TodayMetric = TodayMetricMode.Token,
            });
        var tokenFlyout = new FlyoutWindow(
            coordinator,
            settings,
            tokens,
            () => { },
            () => { });
        try
        {
            if (tokenFlyout.FindName("TokensTabButton") is not
                RadioButton tokensTab)
            {
                throw new InvalidOperationException(
                    "Tokens tab button could not be found for snapshot.");
            }

            tokensTab.IsChecked = true;
            snapshots["flyout-token"] = ShowAndLayout(
                tokenFlyout,
                snapshotDirectory,
                background,
                SnapshotNames("flyout-token", suffix, theme));
        }
        finally
        {
            tokenFlyout.AllowClose();
            tokenFlyout.Close();
        }

        settings.SaveAppearance(
            settings.Appearance with
            {
                TodayMetric = TodayMetricMode.Usage,
            });
        var settingsWindow = new SettingsWindow(
            coordinator,
            settings,
            () => { });
        try
        {
            snapshots["settings"] = ShowAndLayout(
                settingsWindow,
                snapshotDirectory,
                background,
                SnapshotNames("settings", suffix, theme));
            if (settingsWindow.FindName("Navigation") is not ListBox navigation)
            {
                throw new InvalidOperationException(
                    "The Settings navigation could not be found.");
            }

            navigation.SelectedIndex = 1;
            snapshots["settings-display"] = ShowAndLayout(
                settingsWindow,
                snapshotDirectory,
                background,
                SnapshotNames("settings-display", suffix, theme));
            VerifyDisplaySettingsPresentation(
                settingsWindow,
                settings,
                navigation);
            VerifyPrimaryAgentComboPresentation(settingsWindow);
            if (settingsWindow.FindName("AppearancePage") is not
                ScrollViewer displayPage)
            {
                throw new InvalidOperationException(
                    "The Display page scroll viewer could not be found.");
            }

            displayPage.ScrollToEnd();
            snapshots["settings-display-options"] = ShowAndLayout(
                settingsWindow,
                snapshotDirectory,
                background,
                SnapshotNames("settings-display-options", suffix, theme));
        }
        finally
        {
            settingsWindow.Close();
        }

        var onboarding = new OnboardingWindow(coordinator, settings);
        try
        {
            snapshots["onboarding"] = ShowAndLayout(
                onboarding,
                snapshotDirectory,
                background,
                SnapshotNames("onboarding", suffix, theme));
        }
        finally
        {
            onboarding.Close();
        }

        return snapshots;
    }

    private static IReadOnlyList<string> SnapshotNames(
        string baseName,
        string suffix,
        WindowsAppTheme theme) =>
        theme == WindowsAppTheme.Light
            ? [$"{baseName}-{suffix}.png", $"{baseName}.png"]
            : [$"{baseName}-{suffix}.png"];

    private static void VerifySmallWorkAreaConstraints()
    {
        var constraints = WindowSizing.CalculateConstraints(
            workingAreaWidthPixels: 800,
            workingAreaHeightPixels: 600,
            dpi: 192,
            preferredMinimumWidth: 480,
            preferredMinimumHeight: 320);
        if (constraints.MinimumWidth > constraints.MaximumWidth ||
            constraints.MinimumHeight > constraints.MaximumHeight ||
            constraints.MaximumWidth != 368 ||
            constraints.MaximumHeight != 268)
        {
            throw new InvalidOperationException(
                "High-DPI work-area constraints can produce an invalid WPF size.");
        }
    }

    private static void VerifyFlyoutPlacement()
    {
        var screen = new System.Drawing.Rectangle(0, 0, 1920, 1080);
        var window = new System.Drawing.Size(400, 500);
        const int margin = 8;
        var cases = new[]
        {
            (
                Name: "bottom taskbar",
                WorkArea: new System.Drawing.Rectangle(0, 0, 1920, 1040),
                Anchor: new System.Drawing.Point(1900, 1060),
                Anchored: (Func<System.Drawing.Rectangle, bool>)(placement =>
                    placement.Bottom == 1040 - margin)),
            (
                Name: "top taskbar",
                WorkArea: new System.Drawing.Rectangle(0, 40, 1920, 1040),
                Anchor: new System.Drawing.Point(1900, 20),
                Anchored: (Func<System.Drawing.Rectangle, bool>)(placement =>
                    placement.Top == 40 + margin)),
            (
                Name: "left taskbar",
                WorkArea: new System.Drawing.Rectangle(40, 0, 1880, 1080),
                Anchor: new System.Drawing.Point(20, 1040),
                Anchored: (Func<System.Drawing.Rectangle, bool>)(placement =>
                    placement.Left == 40 + margin)),
            (
                Name: "right taskbar",
                WorkArea: new System.Drawing.Rectangle(0, 0, 1880, 1080),
                Anchor: new System.Drawing.Point(1900, 1040),
                Anchored: (Func<System.Drawing.Rectangle, bool>)(placement =>
                    placement.Right == 1880 - margin)),
        };

        foreach (var testCase in cases)
        {
            var placement = WindowSizing.CalculateFlyoutPlacement(
                testCase.WorkArea,
                screen,
                testCase.Anchor,
                window,
                margin);
            if (!testCase.Anchored(placement) ||
                placement.Left < testCase.WorkArea.Left + margin ||
                placement.Top < testCase.WorkArea.Top + margin ||
                placement.Right > testCase.WorkArea.Right - margin ||
                placement.Bottom > testCase.WorkArea.Bottom - margin)
            {
                throw new InvalidOperationException(
                    $"Flyout placement escaped or detached from the " +
                    $"{testCase.Name} work area: {placement}.");
            }
        }

        var clamped = WindowSizing.CalculateFlyoutPlacement(
            new System.Drawing.Rectangle(100, 100, 300, 200),
            new System.Drawing.Rectangle(100, 80, 300, 220),
            new System.Drawing.Point(-10_000, 10_000),
            new System.Drawing.Size(1_000, 1_000),
            margin: 16);
        if (clamped != new System.Drawing.Rectangle(116, 116, 268, 168))
        {
            throw new InvalidOperationException(
                $"Oversized flyout placement was not clamped: {clamped}.");
        }
    }

    private static void VerifyMissingTranscriptRootRecovery(string temporary)
    {
        var now = DateTimeOffset.Now;
        var root = Path.Combine(
            temporary,
            "late-transcripts",
            "sessions");
        var watcher = new TokenOdometerWatcher(
            new TranscriptTokenReader(),
            [("Late root", root)],
            () => now);
        try
        {
            watcher.SetVisibleAsync(true).GetAwaiter().GetResult();
            if (!watcher.HasLoaded || watcher.Usage is not null)
            {
                throw new InvalidOperationException(
                    "The missing-root seed scan did not publish an empty state.");
            }

            Directory.CreateDirectory(root);
            File.WriteAllText(
                Path.Combine(root, "late.jsonl"),
                JsonSerializer.Serialize(new
                {
                    timestamp = now.ToString("O"),
                    message = new
                    {
                        id = "late-root",
                        model = "claude-sonnet-4-6",
                        usage = new
                        {
                            input_tokens = 7,
                            output_tokens = 3,
                            cache_creation_input_tokens = 0,
                            cache_read_input_tokens = 0,
                        },
                    },
                }) + Environment.NewLine);

            if (!SpinWait.SpinUntil(
                    () => watcher.Usage?.OdometerTokens == 10,
                    TimeSpan.FromSeconds(5)))
            {
                throw new TimeoutException(
                    "A transcript root created after startup was not discovered.");
            }
        }
        finally
        {
            watcher.DisposeAsync().AsTask().GetAwaiter().GetResult();
        }
    }

    private static void VerifyWatcherDebounceDrainsWithoutCanceling(
        string temporary)
    {
        var now = DateTimeOffset.Now;
        var root = Path.Combine(temporary, "watcher-drain");
        Directory.CreateDirectory(root);
        var transcript = Path.Combine(root, "drain.jsonl");
        File.WriteAllText(
            transcript,
            CreateTranscriptLine(now, "drain-seed", input: 7, output: 3));

        using var firstScanEntered = new ManualResetEventSlim();
        using var releaseFirstScan = new ManualResetEventSlim();
        using var followUpEntered = new ManualResetEventSlim();
        using var releaseFollowUp = new ManualResetEventSlim();
        var nowCallCount = 0;
        DateTimeOffset ControlledNow()
        {
            var call = Interlocked.Increment(ref nowCallCount);
            if (call == 2)
            {
                firstScanEntered.Set();
                if (!releaseFirstScan.Wait(TimeSpan.FromSeconds(5)))
                {
                    throw new TimeoutException(
                        "The controlled seed token scan was not released.");
                }
            }
            else if (call == 3)
            {
                followUpEntered.Set();
                if (!releaseFollowUp.Wait(TimeSpan.FromSeconds(5)))
                {
                    throw new TimeoutException(
                        "The controlled follow-up token scan was not released.");
                }
            }

            return now;
        }

        var watcher = new TokenOdometerWatcher(
            new TranscriptTokenReader(),
            [("Drain root", root)],
            ControlledNow);
        Task? seed = null;
        try
        {
            seed = Task.Run(() => watcher.SetVisibleAsync(true));
            if (!firstScanEntered.Wait(TimeSpan.FromSeconds(5)))
            {
                throw new TimeoutException(
                    "The seed token scan did not enter its controlled read.");
            }

            File.AppendAllText(
                transcript,
                CreateTranscriptLine(
                    now,
                    "drain-append",
                    input: 4,
                    output: 6));
            Thread.Sleep(TimeSpan.FromMilliseconds(1500));
            releaseFirstScan.Set();

            if (!seed.Wait(TimeSpan.FromSeconds(5)))
            {
                throw new TimeoutException(
                    "The seed token scan did not complete after release.");
            }

            if (!watcher.HasLoaded ||
                watcher.Usage?.OdometerTokens != 20)
            {
                throw new InvalidOperationException(
                    "A debounced file event canceled the in-flight seed scan.");
            }

            if (!followUpEntered.Wait(TimeSpan.FromSeconds(5)))
            {
                throw new TimeoutException(
                    "File changes accumulated during the seed scan were not drained.");
            }

            releaseFollowUp.Set();
            if (!SpinWait.SpinUntil(
                    () =>
                        !watcher.IsScanning &&
                        watcher.Usage?.OdometerTokens == 20,
                    TimeSpan.FromSeconds(5)))
            {
                throw new TimeoutException(
                    "The queued targeted refresh did not finish after the seed scan.");
            }
        }
        finally
        {
            releaseFirstScan.Set();
            releaseFollowUp.Set();
            if (seed is not null)
            {
                try
                {
                    seed.GetAwaiter().GetResult();
                }
                catch
                {
                    // Preserve the primary smoke-test failure.
                }
            }
            watcher.DisposeAsync().AsTask().GetAwaiter().GetResult();
        }
    }

    private static void VerifyWatcherScanFailureRetries(string temporary)
    {
        var now = DateTimeOffset.Now;
        var root = Path.Combine(temporary, "watcher-retry");
        Directory.CreateDirectory(root);
        File.WriteAllText(
            Path.Combine(root, "retry.jsonl"),
            CreateTranscriptLine(now, "retry-seed", input: 8, output: 2));

        var nowCallCount = 0;
        DateTimeOffset FailFirstScan()
        {
            var call = Interlocked.Increment(ref nowCallCount);
            if (call == 2)
            {
                throw new IOException("Controlled token scan failure.");
            }

            return now;
        }

        var watcher = new TokenOdometerWatcher(
            new TranscriptTokenReader(),
            [("Retry root", root)],
            FailFirstScan);
        try
        {
            watcher.SetVisibleAsync(true).GetAwaiter().GetResult();
            if (watcher.HasLoaded ||
                watcher.IsScanning ||
                watcher.LastError != "Controlled token scan failure.")
            {
                throw new InvalidOperationException(
                    "The controlled token scan failure was not published.");
            }

            if (!SpinWait.SpinUntil(
                    () =>
                        watcher.HasLoaded &&
                        !watcher.IsScanning &&
                        watcher.LastError is null &&
                        watcher.Usage?.OdometerTokens == 10,
                    TimeSpan.FromSeconds(5)))
            {
                throw new TimeoutException(
                    "A failed token scan was not retried with a full reconciliation.");
            }
        }
        finally
        {
            watcher.DisposeAsync().AsTask().GetAwaiter().GetResult();
        }
    }

    private static void VerifyDirectoryChangesForceReconciliation(
        string temporary)
    {
        var now = DateTimeOffset.Now;
        var root = Path.Combine(temporary, "watcher-directories");
        var oldDirectory = Path.Combine(root, "before");
        var newDirectory = Path.Combine(root, "after");
        Directory.CreateDirectory(oldDirectory);
        var oldTranscript = Path.Combine(oldDirectory, "session.jsonl");
        File.WriteAllText(
            oldTranscript,
            CreateTranscriptLine(now, "directory-seed", input: 6, output: 4));

        var watcher = new TokenOdometerWatcher(
            new TranscriptTokenReader(),
            [("Directory root", root)],
            () => now);
        try
        {
            watcher.SetVisibleAsync(true).GetAwaiter().GetResult();
            if (watcher.Usage?.OdometerTokens != 10)
            {
                throw new InvalidOperationException(
                    "The directory reconciliation seed was not loaded.");
            }

            Directory.Move(oldDirectory, newDirectory);
            var movedTranscript = Path.Combine(newDirectory, "session.jsonl");
            File.AppendAllText(
                movedTranscript,
                CreateTranscriptLine(
                    now,
                    "directory-append",
                    input: 3,
                    output: 2));
            if (!SpinWait.SpinUntil(
                    () =>
                        !watcher.IsScanning &&
                        watcher.Usage?.OdometerTokens == 15,
                    TimeSpan.FromSeconds(7)))
            {
                throw new TimeoutException(
                    "A directory rename did not force full transcript reconciliation.");
            }

            Directory.Delete(newDirectory, recursive: true);
            if (!SpinWait.SpinUntil(
                    () => !watcher.IsScanning && watcher.Usage is null,
                    TimeSpan.FromSeconds(7)))
            {
                throw new TimeoutException(
                    "A directory deletion did not remove stale transcript usage.");
            }
        }
        finally
        {
            watcher.DisposeAsync().AsTask().GetAwaiter().GetResult();
        }
    }

    private static string CreateTranscriptLine(
        DateTimeOffset timestamp,
        string id,
        long input,
        long output) =>
        JsonSerializer.Serialize(new
        {
            timestamp = timestamp.ToString("O"),
            message = new
            {
                id,
                model = "claude-sonnet-4-6",
                usage = new
                {
                    input_tokens = input,
                    output_tokens = output,
                    cache_creation_input_tokens = 0,
                    cache_read_input_tokens = 0,
                },
            },
        }) + Environment.NewLine;

    private static void VerifySignOutWinsInFlightRefresh(string temporary)
    {
        var settings = new AppSettingsStore(
            Path.Combine(temporary, "coordinator-race-settings.json"));
        var auth = AgentRegistry.All.ToDictionary(
            definition => definition.Id,
            _ => (IAgentAuthSession)new ConnectedAuth());
        var blocking = new BlockingProvider();
        var providers = new Dictionary<AgentId, IUsageProvider>
        {
            [AgentId.ClaudeCode] = blocking,
            [AgentId.Codex] = new StaticProvider(AgentId.Codex),
        };
        var coordinator = new UsageCoordinator(settings, auth, providers);
        try
        {
            var start = coordinator.StartAsync();
            if (!blocking.Started.Task.Wait(TimeSpan.FromSeconds(5)))
            {
                throw new TimeoutException(
                    "The controlled usage refresh did not start.");
            }

            coordinator.SignOut(AgentId.ClaudeCode);
            blocking.Release.TrySetResult();
            start.GetAwaiter().GetResult();
            if (coordinator.GetAgent(AgentId.ClaudeCode).State.Kind !=
                    AgentStateKind.SignedOut ||
                settings.LoadLastSnapshot(AgentId.ClaudeCode) is not null)
            {
                throw new InvalidOperationException(
                    "An in-flight usage refresh overwrote sign-out state.");
            }
        }
        finally
        {
            blocking.Release.TrySetResult();
            coordinator.DisposeAsync().AsTask().GetAwaiter().GetResult();
        }
    }

    private static RenderedSnapshot ShowAndLayout(
        Window window,
        string? snapshotDirectory,
        Color expectedBackground,
        IReadOnlyList<string> snapshotNames)
    {
        window.ShowActivated = false;
        ShowAndCompleteLayout(window);
        if (window.ActualWidth <= 0 || window.ActualHeight <= 0)
        {
            throw new InvalidOperationException(
                $"{window.GetType().Name} did not complete layout.");
        }

        var snapshot = RenderVisual(window);
        AssertContainsColor(
            window.GetType().Name,
            snapshot,
            expectedBackground,
            minimumPixels: 256);
        if (!string.IsNullOrWhiteSpace(snapshotDirectory))
        {
            Directory.CreateDirectory(snapshotDirectory);
            foreach (var snapshotName in snapshotNames)
            {
                var path = Path.Combine(snapshotDirectory, snapshotName);
                SavePng(snapshot, path);
                if (!File.Exists(path) || new FileInfo(path).Length == 0)
                {
                    throw new InvalidOperationException(
                        $"The UI snapshot '{snapshotName}' was not written.");
                }
            }
        }

        window.Hide();
        return snapshot;
    }

    private static void ShowAndCompleteLayout(Window window)
    {
        window.Show();
        window.UpdateLayout();
        var width = Math.Max(1, window.ActualWidth);
        var height = Math.Max(1, window.ActualHeight);
        window.Measure(new Size(width, height));
        window.Arrange(new Rect(0, 0, width, height));
        window.UpdateLayout();
    }

    private static T FindNamed<T>(FrameworkElement root, string name)
        where T : FrameworkElement =>
        root.FindName(name) as T ??
        throw new InvalidOperationException(
            $"{typeof(T).Name} '{name}' could not be found.");

    private static TextBlock FindTokenCell(
        DependencyObject root,
        string kindName) =>
        FindVisualDescendant<TextBlock>(
            root,
            text =>
                text.ToolTip is string tooltip &&
                tooltip.StartsWith($"{kindName}:", StringComparison.Ordinal));

    private static void PumpDispatcher(Dispatcher dispatcher)
    {
        var frame = new DispatcherFrame();
        dispatcher.BeginInvoke(
            DispatcherPriority.Background,
            new Action(() => frame.Continue = false));
        Dispatcher.PushFrame(frame);
    }

    private static void WaitForUi(
        Dispatcher dispatcher,
        Func<bool> condition,
        string timeoutMessage)
    {
        var deadline = DateTime.UtcNow.AddSeconds(5);
        while (DateTime.UtcNow < deadline)
        {
            PumpDispatcher(dispatcher);
            if (condition())
            {
                return;
            }

            Thread.Sleep(10);
        }

        throw new TimeoutException(timeoutMessage);
    }

    private static void FlushThemeChange(Window window)
    {
        window.Dispatcher.Invoke(
            () => { },
            DispatcherPriority.Render);
        window.UpdateLayout();
    }

    private static T FindVisualDescendant<T>(
        DependencyObject root,
        Func<T, bool> predicate)
        where T : DependencyObject
    {
        if (root is T match && predicate(match))
        {
            return match;
        }

        var childCount = VisualTreeHelper.GetChildrenCount(root);
        for (var index = 0; index < childCount; index++)
        {
            var child = VisualTreeHelper.GetChild(root, index);
            try
            {
                return FindVisualDescendant(child, predicate);
            }
            catch (InvalidOperationException)
            {
            }
        }

        throw new InvalidOperationException(
            $"A matching {typeof(T).Name} could not be found.");
    }

    private static void VerifyDisplaySettingsPresentation(
        SettingsWindow settingsWindow,
        AppSettingsStore settings,
        ListBox navigation)
    {
        if (navigation.Items.Count < 2 ||
            navigation.Items[1] is not ListBoxItem
            {
                Content: string displayLabel,
            } ||
            displayLabel != "Display" ||
            !EnumerateVisualDescendants<TextBlock>(settingsWindow)
                .Any(text => text.Text == "Display") ||
            EnumerateVisualDescendants<TextBlock>(settingsWindow)
                .Any(text => text.Text == "Appearance"))
        {
            throw new InvalidOperationException(
                "The user-facing Settings pane was not renamed to Display.");
        }

        var value =
            FindNamed<RadioButton>(settingsWindow, "TokenValueMode");
        var percentage =
            FindNamed<RadioButton>(settingsWindow, "TokenPercentageMode");
        var valueAndPercentage =
            FindNamed<RadioButton>(
                settingsWindow,
                "TokenValuePercentageMode");
        var alwaysOnTop =
            FindNamed<CheckBox>(settingsWindow, "AlwaysOnTopCheckBox");
        if (!value.Focusable ||
            !percentage.Focusable ||
            !valueAndPercentage.Focusable ||
            !alwaysOnTop.Focusable ||
            value.Content as string != "Value" ||
            percentage.Content as string != "Percentage" ||
            valueAndPercentage.Content as string != "Value (percentage)" ||
            alwaysOnTop.Content as string != "Keep the flyout pinned on top")
        {
            throw new InvalidOperationException(
                "The Display pane's new controls are not keyboard-readable.");
        }

        percentage.IsChecked = true;
        PumpDispatcher(settingsWindow.Dispatcher);
        if (settings.Appearance.TokenValueDisplay !=
            TokenValueDisplayMode.Percentage)
        {
            throw new InvalidOperationException(
                "The Percentage Display choice was not saved.");
        }

        valueAndPercentage.IsChecked = true;
        PumpDispatcher(settingsWindow.Dispatcher);
        if (settings.Appearance.TokenValueDisplay !=
            TokenValueDisplayMode.ValueAndPercentage)
        {
            throw new InvalidOperationException(
                "The Value (percentage) Display choice was not saved.");
        }

        value.IsChecked = true;
        alwaysOnTop.IsChecked = true;
        PumpDispatcher(settingsWindow.Dispatcher);
        if (settings.Appearance.TokenValueDisplay !=
                TokenValueDisplayMode.Value ||
            !settings.Appearance.AlwaysOnTop)
        {
            throw new InvalidOperationException(
                "The Display pane did not save Value and pin preferences.");
        }

        alwaysOnTop.IsChecked = false;
        PumpDispatcher(settingsWindow.Dispatcher);
        if (settings.Appearance.AlwaysOnTop)
        {
            throw new InvalidOperationException(
                "The Display pane did not save the unpinned preference.");
        }
    }

    private static void VerifyPrimaryAgentComboPresentation(
        SettingsWindow settingsWindow)
    {
        if (settingsWindow.FindName("PrimaryAgentCombo") is not ComboBox combo)
        {
            throw new InvalidOperationException(
                "The primary Agent ComboBox could not be found.");
        }

        var renderedText = EnumerateVisualDescendants<TextBlock>(combo)
            .Select(text => text.Text)
            .Where(text => !string.IsNullOrWhiteSpace(text))
            .ToArray();
        if (renderedText.Any(text => text.Contains(
                "AgentDefinition {",
                StringComparison.Ordinal)))
        {
            throw new InvalidOperationException(
                "The themed ComboBox leaked the AgentDefinition record " +
                "instead of applying DisplayMemberPath.");
        }

        if (!renderedText.Contains(
                AgentRegistry.Get(AgentId.ClaudeCode).DisplayName,
                StringComparer.Ordinal))
        {
            throw new InvalidOperationException(
                "The themed ComboBox did not render the selected Agent name.");
        }
    }

    private static IEnumerable<T> EnumerateVisualDescendants<T>(
        DependencyObject root)
        where T : DependencyObject
    {
        if (root is T match)
        {
            yield return match;
        }

        var childCount = VisualTreeHelper.GetChildrenCount(root);
        for (var index = 0; index < childCount; index++)
        {
            foreach (var descendant in EnumerateVisualDescendants<T>(
                         VisualTreeHelper.GetChild(root, index)))
            {
                yield return descendant;
            }
        }
    }

    private static void AssertBrushColor(
        Brush brush,
        Color expected,
        string description)
    {
        if (brush is not SolidColorBrush solid || solid.Color != expected)
        {
            throw new InvalidOperationException(
                $"{description} was not {expected}.");
        }
    }

    private static RenderedSnapshot RenderVisual(Visual visual)
    {
        if (visual is not FrameworkElement element ||
            element.ActualWidth <= 0 ||
            element.ActualHeight <= 0)
        {
            throw new InvalidOperationException(
                $"{visual.GetType().Name} has no renderable layout.");
        }

        var scale = VisualTreeHelper.GetDpi(visual);
        var pixelWidth = Math.Max(
            1,
            (int)Math.Ceiling(element.ActualWidth * scale.DpiScaleX));
        var pixelHeight = Math.Max(
            1,
            (int)Math.Ceiling(element.ActualHeight * scale.DpiScaleY));
        var bitmap = new RenderTargetBitmap(
            pixelWidth,
            pixelHeight,
            scale.PixelsPerInchX,
            scale.PixelsPerInchY,
            PixelFormats.Pbgra32);
        bitmap.Render(visual);
        var stride = pixelWidth * 4;
        var pixels = new byte[stride * pixelHeight];
        bitmap.CopyPixels(pixels, stride, 0);
        return new RenderedSnapshot(
            pixelWidth,
            pixelHeight,
            scale.PixelsPerInchX,
            scale.PixelsPerInchY,
            pixels);
    }

    private static void SavePng(RenderedSnapshot snapshot, string path)
    {
        var bitmap = BitmapSource.Create(
            snapshot.PixelWidth,
            snapshot.PixelHeight,
            snapshot.DpiX,
            snapshot.DpiY,
            PixelFormats.Pbgra32,
            null,
            snapshot.Pixels,
            snapshot.PixelWidth * 4);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path);
        encoder.Save(stream);
    }

    private static void AssertContainsColor(
        string description,
        RenderedSnapshot snapshot,
        Color expected,
        int minimumPixels)
    {
        var matching = 0;
        for (var offset = 0; offset < snapshot.Pixels.Length; offset += 4)
        {
            if (snapshot.Pixels[offset] == expected.B &&
                snapshot.Pixels[offset + 1] == expected.G &&
                snapshot.Pixels[offset + 2] == expected.R &&
                snapshot.Pixels[offset + 3] == expected.A)
            {
                matching++;
            }
        }

        if (matching < minimumPixels)
        {
            throw new InvalidOperationException(
                $"{description} rendered only {matching} pixels of the " +
                $"expected theme background {expected}.");
        }
    }

    private static void AssertSnapshotsDiffer(
        string description,
        RenderedSnapshot first,
        RenderedSnapshot second)
    {
        if (first.PixelWidth != second.PixelWidth ||
            first.PixelHeight != second.PixelHeight)
        {
            throw new InvalidOperationException(
                $"{description} changed layout dimensions between themes.");
        }

        if (first.Pixels.AsSpan().SequenceEqual(second.Pixels))
        {
            throw new InvalidOperationException(
                $"{description} rendered identical pixels for both themes.");
        }
    }

    private static Color Rgb(int red, int green, int blue) =>
        Color.FromRgb((byte)red, (byte)green, (byte)blue);

    private static Color Argb(int alpha, int red, int green, int blue) =>
        Color.FromArgb((byte)alpha, (byte)red, (byte)green, (byte)blue);

    private sealed record RenderedSnapshot(
        int PixelWidth,
        int PixelHeight,
        double DpiX,
        double DpiY,
        byte[] Pixels);

    private sealed class ConnectedAuth : IAgentAuthSession
    {
        public bool IsSignedIn => true;
        public string? AccountId => "smoke-account";

        public Task<string> ValidAccessTokenAsync(
            CancellationToken cancellationToken = default) =>
            Task.FromResult("smoke-access-token");

        public Task BeginSignInAsync(
            CancellationToken cancellationToken = default) =>
            Task.CompletedTask;

        public Task CompleteSignInAsync(
            string pastedCode,
            CancellationToken cancellationToken = default) =>
            Task.CompletedTask;

        public void SignOut()
        {
        }
    }

    private sealed class StaticProvider : IUsageProvider
    {
        private readonly AgentId _id;

        public StaticProvider(AgentId id)
        {
            _id = id;
        }

        public Task<IReadOnlyList<UsageWindow>> FetchUsageAsync(
            CancellationToken cancellationToken = default)
        {
            var now = DateTimeOffset.Now;
            IReadOnlyList<UsageWindow> windows = _id == AgentId.ClaudeCode
                ?
                [
                    new UsageWindow("5-hour", 24, now.AddHours(3).AddMinutes(20)),
                    new UsageWindow("Weekly", 18, now.AddDays(4)),
                    new UsageWindow("Fable", 61, now.AddDays(2).AddHours(3)),
                ]
                :
                [
                    new UsageWindow(
                        "Weekly",
                        76,
                        now.AddDays(3),
                        UsageWindowKind.Weekly,
                        604_800),
                ];
            return Task.FromResult(windows);
        }
    }

    private sealed class BlockingProvider : IUsageProvider
    {
        public TaskCompletionSource Started { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public TaskCompletionSource Release { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public async Task<IReadOnlyList<UsageWindow>> FetchUsageAsync(
            CancellationToken cancellationToken = default)
        {
            Started.TrySetResult();
            await Release.Task.WaitAsync(cancellationToken).ConfigureAwait(false);
            return
            [
                new UsageWindow(
                    "5-hour",
                    25,
                    DateTimeOffset.Now.AddHours(1)),
            ];
        }
    }
}
