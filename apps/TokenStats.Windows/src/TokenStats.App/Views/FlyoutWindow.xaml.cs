using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using TokenStats.App.Controls;
using TokenStats.App.Infrastructure;
using TokenStats.App.Services;
using TokenStats.Core;
using Forms = System.Windows.Forms;

namespace TokenStats.App.Views;

public partial class FlyoutWindow : Window
{
    private readonly UsageCoordinator _coordinator;
    private readonly AppSettingsStore _settings;
    private readonly TokenOdometerWatcher _tokenOdometer;
    private readonly Action _showSettings;
    private readonly Action _quit;
    private readonly HashSet<AgentId> _expandedDiagnostics = [];
    private readonly DispatcherTimer _ageTimer;
    private FlyoutTab _selectedTab = FlyoutTab.Usage;
    private System.Drawing.Point _notificationAreaAnchor;
    private DispatcherOperation? _repositionOperation;
    private bool _allowClose;
    private bool _refreshInFlight;
    private bool _hasNotificationAreaAnchor;
    private bool _isPinned;
    private bool _isPositioning;
    private bool _updatingControls;

    public FlyoutWindow(
        UsageCoordinator coordinator,
        AppSettingsStore settings,
        TokenOdometerWatcher tokenOdometer,
        Action showSettings,
        Action quit)
    {
        _coordinator = coordinator;
        _settings = settings;
        _tokenOdometer = tokenOdometer;
        _showSettings = showSettings;
        _quit = quit;
        InitializeComponent();
        WindowsThemeService.Attach(this);

        _coordinator.Changed += Coordinator_OnChanged;
        _tokenOdometer.Changed += TokenOdometer_OnChanged;
        WindowsThemeService.ThemeChanged += WindowsThemeService_OnThemeChanged;
        Deactivated += FlyoutWindow_OnDeactivated;
        Closing += FlyoutWindow_OnClosing;
        Closed += FlyoutWindow_OnClosed;
        PreviewKeyDown += FlyoutWindow_OnPreviewKeyDown;
        var settingsMenu = new ContextMenu();
        var openSettings = new MenuItem { Header = "Settings…" };
        openSettings.Click += (_, _) =>
        {
            if (!_isPinned)
            {
                HideFlyout();
            }

            _showSettings();
        };
        var quitItem = new MenuItem { Header = "Quit TokenStats" };
        quitItem.Click += (_, _) => _quit();
        settingsMenu.Items.Add(openSettings);
        settingsMenu.Items.Add(new Separator());
        settingsMenu.Items.Add(quitItem);
        settingsMenu.Closed += (_, _) =>
        {
            if (IsVisible && !IsActive && !_isPinned)
            {
                HideFlyout();
            }
        };
        SettingsButton.ContextMenu = settingsMenu;
        _ageTimer = new DispatcherTimer(TimeSpan.FromSeconds(30), DispatcherPriority.Background, (_, _) => Render(), Dispatcher);
        _updatingControls = true;
        UsageTabButton.IsChecked = true;
        _updatingControls = false;
        Render();
    }

    public void ShowFlyout()
    {
        _notificationAreaAnchor = Forms.Cursor.Position;
        _hasNotificationAreaAnchor = true;
        Render();
        Show();
        UpdateLayout();
        PositionNearNotificationArea(settleDpi: true);
        Activate();
        Focus();
        _ageTimer.Start();
        _ = _coordinator.RefreshAllAsync(RefreshTrigger.PopoverOpen);
    }

    public void HideFlyout()
    {
        if (!IsVisible)
        {
            return;
        }

        Hide();
        _ageTimer.Stop();
        _repositionOperation?.Abort();
        _repositionOperation = null;
    }

    public void AllowClose() => _allowClose = true;

    private void UsageTabButton_OnChecked(
        object sender,
        RoutedEventArgs eventArgs)
    {
        if (_updatingControls || !IsInitialized)
        {
            return;
        }

        _selectedTab = FlyoutTab.Usage;
        RenderTabVisibility();
    }

    private void TokensTabButton_OnChecked(
        object sender,
        RoutedEventArgs eventArgs)
    {
        if (_updatingControls || !IsInitialized)
        {
            return;
        }

        _selectedTab = FlyoutTab.Tokens;
        RenderTabVisibility();
        RenderTokenOdometer();
    }

    private void ApiMetricButton_OnChecked(
        object sender,
        RoutedEventArgs eventArgs)
    {
        if (_updatingControls || !IsInitialized)
        {
            return;
        }

        TrySaveDisplayPreferences(
            _settings.Appearance with { TodayMetric = TodayMetricMode.Usage });
    }

    private void BillingMetricButton_OnChecked(
        object sender,
        RoutedEventArgs eventArgs)
    {
        if (_updatingControls || !IsInitialized)
        {
            return;
        }

        TrySaveDisplayPreferences(
            _settings.Appearance with { TodayMetric = TodayMetricMode.Token });
    }

    private async void RangeButton_OnChecked(
        object sender,
        RoutedEventArgs eventArgs)
    {
        if (_updatingControls ||
            !IsInitialized ||
            sender is not RadioButton { Tag: string rangeName } ||
            !Enum.TryParse<TokenRange>(rangeName, out var range))
        {
            return;
        }

        if (TrySaveDisplayPreferences(
                _settings.Appearance with { SelectedTokenRange = range }))
        {
            await _tokenOdometer.SelectRangeAsync(range).ConfigureAwait(true);
        }
    }

    private void PinButton_OnChanged(
        object sender,
        RoutedEventArgs eventArgs)
    {
        if (_updatingControls || !IsInitialized)
        {
            return;
        }

        TrySaveDisplayPreferences(
            _settings.Appearance with
            {
                AlwaysOnTop = PinButton.IsChecked == true,
            });
    }

    private void TokenKindButton_OnChanged(
        object sender,
        RoutedEventArgs eventArgs)
    {
        if (_updatingControls ||
            !IsInitialized ||
            sender is not ToggleButton { Tag: string kindName } button ||
            !Enum.TryParse<TokenKind>(kindName, out var kind))
        {
            return;
        }

        var current = _settings.Appearance.SelectedTokenKinds;
        var flag = kind switch
        {
            TokenKind.DirectInput => TokenKindSelection.DirectInput,
            TokenKind.Output => TokenKindSelection.Output,
            TokenKind.CacheWrite => TokenKindSelection.CacheWrite,
            TokenKind.CacheRead => TokenKindSelection.CacheRead,
            _ => throw new ArgumentOutOfRangeException(nameof(kind), kind, null),
        };
        var next = button.IsChecked == true
            ? current | flag
            : current & ~flag;
        if (next == TokenKindSelection.None)
        {
            _updatingControls = true;
            button.IsChecked = true;
            _updatingControls = false;
            System.Media.SystemSounds.Beep.Play();
            return;
        }

        TrySaveDisplayPreferences(
            _settings.Appearance with { SelectedTokenKinds = next });
    }

    private async void RefreshButton_OnClick(object sender, RoutedEventArgs eventArgs)
    {
        if (_refreshInFlight)
        {
            return;
        }

        _refreshInFlight = true;
        RefreshButton.IsEnabled = false;
        try
        {
            await Task.WhenAll(
                    _coordinator.RefreshAllAsync(RefreshTrigger.Manual),
                    _tokenOdometer.RefreshAsync())
                .ConfigureAwait(true);
        }
        finally
        {
            _refreshInFlight = false;
            RefreshButton.IsEnabled = true;
        }
    }

    private void SettingsButton_OnClick(object sender, RoutedEventArgs eventArgs)
    {
        if (SettingsButton.ContextMenu is { } menu)
        {
            menu.PlacementTarget = SettingsButton;
            menu.IsOpen = true;
        }
    }

    private void Coordinator_OnChanged(object? sender, EventArgs eventArgs) =>
        Dispatcher.BeginInvoke(Render);

    private void TokenOdometer_OnChanged(object? sender, EventArgs eventArgs) =>
        Dispatcher.BeginInvoke(RenderTokenOdometer);

    private void Render()
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.BeginInvoke(Render);
            return;
        }

        RenderTabVisibility();
        RenderTokenOdometer();
        AgentsPanel.Children.Clear();
        var agents = _coordinator.Agents;
        for (var index = 0; index < agents.Count; index++)
        {
            if (index > 0)
            {
                AgentsPanel.Children.Add(new Border
                {
                    Height = 1,
                    Margin = new Thickness(0, 14, 0, 14),
                    Background = FindBrush("BorderBrush"),
                });
            }

            AgentsPanel.Children.Add(BuildAgentSection(agents[index]));
        }
    }

    private void RenderTabVisibility()
    {
        var showUsage = _selectedTab == FlyoutTab.Usage;
        UsageContentScroll.Visibility =
            showUsage ? Visibility.Visible : Visibility.Collapsed;
        TokensContentScroll.Visibility =
            showUsage ? Visibility.Collapsed : Visibility.Visible;
    }

    private void RenderTokenOdometer()
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.BeginInvoke(RenderTokenOdometer);
            return;
        }

        var preferences = _settings.Appearance;
        var selection = preferences.SelectedTokenKinds;
        var selectedRange = _tokenOdometer.SelectedRange;
        _updatingControls = true;
        ApiMetricButton.IsChecked =
            preferences.TodayMetric == TodayMetricMode.Usage;
        BillingMetricButton.IsChecked =
            preferences.TodayMetric == TodayMetricMode.Token;
        TodayRangeButton.IsChecked = selectedRange == TokenRange.Today;
        SevenDaysRangeButton.IsChecked = selectedRange == TokenRange.SevenDays;
        ThirtyDaysRangeButton.IsChecked =
            selectedRange == TokenRange.ThirtyDays;
        DirectInputKindButton.IsChecked =
            selection.Includes(TokenKind.DirectInput);
        OutputKindButton.IsChecked =
            selection.Includes(TokenKind.Output);
        CacheWriteKindButton.IsChecked =
            selection.Includes(TokenKind.CacheWrite);
        CacheReadKindButton.IsChecked =
            selection.Includes(TokenKind.CacheRead);
        PinButton.IsChecked = preferences.AlwaysOnTop;
        _updatingControls = false;
        ApplyPinnedState(preferences.AlwaysOnTop);

        var usage = _tokenOdometer.Usage;
        var displayedRange = _tokenOdometer.DisplayedRange;
        var hasLoaded = _tokenOdometer.HasLoaded;
        var pendingRange = _tokenOdometer.PendingRange;
        var scanError = _tokenOdometer.LastError;
        if (!hasLoaded)
        {
            var readingRange = pendingRange ?? selectedRange;
            if (!_tokenOdometer.IsScanning &&
                !string.IsNullOrWhiteSpace(scanError))
            {
                TokenSummaryValue.Text = "—";
                TokenSummaryLabel.Text =
                    $"Couldn't read {readingRange.Label()}";
                TokenSummaryPanel.ToolTip =
                    $"Token usage could not be read: {scanError}";
                AutomationProperties.SetName(
                    TokenSummaryPanel,
                    $"Token usage could not be read for {readingRange.Label()}");
            }
            else
            {
                TokenSummaryValue.Text = "—";
                TokenSummaryLabel.Text = $"Reading {readingRange.Label()}…";
                TokenSummaryPanel.ToolTip =
                    $"Reading token usage for {readingRange.Label()}.";
                AutomationProperties.SetName(
                    TokenSummaryPanel,
                    $"Reading token usage for {readingRange.Label()}");
            }
        }
        else if (preferences.TodayMetric == TodayMetricMode.Usage)
        {
            RenderApiEquivalent(usage, displayedRange);
        }
        else
        {
            RenderBillingTokens(usage, displayedRange);
        }

        OdometerProgress.Visibility = _tokenOdometer.IsScanning
            ? Visibility.Visible
            : Visibility.Collapsed;
        OdometerStatusText.Text =
            _tokenOdometer.IsScanning
                ? $"Reading {(pendingRange ?? selectedRange).Label()}…"
                : !string.IsNullOrWhiteSpace(scanError)
                    ? "Couldn't read tokens"
                    : hasLoaded
                        ? displayedRange.Label()
                        : $"Reading {selectedRange.Label()}…";
        OdometerStatusText.ToolTip = scanError;
        TokenTablePanel.Visibility =
            hasLoaded ? Visibility.Visible : Visibility.Collapsed;
        TokenTablePanel.Opacity =
            _tokenOdometer.IsScanning && hasLoaded
                ? 0.58
                : 1;
        var selectedCount = Enum.GetValues<TokenKind>()
            .Count(kind => selection.Includes(kind));
        TokenTableTotal.Text =
            $"{displayedRange.Label()} · {selectedCount} selected " +
            $"{(selectedCount == 1 ? "kind" : "kinds")}";

        TokenRowsPanel.Children.Clear();
        if (!hasLoaded)
        {
            return;
        }

        var slices = _tokenOdometer.PerAgent;
        var displayOrder = _coordinator.Appearance.DisplayOrder();
        for (var index = 0; index < displayOrder.Count; index++)
        {
            if (index > 0)
            {
                TokenRowsPanel.Children.Add(new Border
                {
                    Height = 1,
                    Margin = new Thickness(0, 11, 0, 11),
                    Background = FindBrush("BorderBrush"),
                });
            }

            var definition = AgentRegistry.Get(displayOrder[index]);
            var slice = slices.FirstOrDefault(
                item => string.Equals(
                    item.Label,
                    definition.DisplayName,
                    StringComparison.OrdinalIgnoreCase));
            TokenRowsPanel.Children.Add(
                BuildTokenAgentSection(
                    definition.DisplayName,
                    slice?.Usage,
                    selection,
                    preferences.TokenValueDisplay));
        }
    }

    private void RenderBillingTokens(
        TokenUsage? usage,
        TokenRange displayedRange)
    {
        TokenSummaryValue.Text = usage?.BillableTokens.ToString("N0") ?? "—";
        TokenSummaryLabel.Text =
            $"billing tokens · {displayedRange.Label()}";
        TokenSummaryPanel.ToolTip = usage is null
            ? $"No billing token usage for {displayedRange.Label()}."
            : $"{UsageFormatting.TokenBreakdown(usage)}. " +
              "Billing tokens include direct input, cache writes, and output; " +
              "cache reads remain visible in the table but are excluded from this total. " +
              "Token Kind display toggles do not change this objective summary.";
        AutomationProperties.SetName(
            TokenSummaryPanel,
            usage is null
                ? $"No billing token usage for {displayedRange.Label()}"
                : $"{usage.BillableTokens:N0} billing tokens for " +
                  $"{displayedRange.Label()}; cache reads excluded");
    }

    private void RenderApiEquivalent(
        TokenUsage? usage,
        TokenRange displayedRange)
    {
        if (usage is null)
        {
            TokenSummaryValue.Text = "—";
            TokenSummaryLabel.Text =
                $"API-equivalent · {displayedRange.Label()}";
            TokenSummaryPanel.ToolTip =
                $"No API-equivalent usage for {displayedRange.Label()}.";
            AutomationProperties.SetName(
                TokenSummaryPanel,
                $"No API-equivalent usage for {displayedRange.Label()}");
            return;
        }

        var pricingDate = DateOnly.FromDateTime(DateTime.Today);
        var estimate = ApiPricingCatalog.Estimate(
            usage,
            pricingDate);
        TokenSummaryValue.Text = UsageFormatting.ApiEquivalentCost(estimate);
        TokenSummaryLabel.Text =
            $"API-equivalent · {displayedRange.Label()}";
        var unpriced = estimate.IsPartial
            ? $" Unpriced: {string.Join(", ", estimate.UnpricedModels)} " +
              $"({estimate.UnpricedTokens:N0} tokens)."
            : string.Empty;
        var models = string.Join(
            ", ",
            usage.ModelUsage
                .Select(item => item.Model ?? "unknown model")
                .Distinct(StringComparer.OrdinalIgnoreCase));
        TokenSummaryPanel.ToolTip =
            "Standard API-equivalent estimate by recorded model; includes all " +
            "four Token Kinds at list rates regardless of the display toggles. " +
            "Claude cache writes without TTL detail use the default 5-minute rate. " +
            $"Models: {(models.Length > 0 ? models : "unknown")}. " +
            $"Prices reviewed {ApiPricingCatalog.LastReviewed:yyyy-MM-dd}." +
            unpriced;
        AutomationProperties.SetName(
            TokenSummaryPanel,
            estimate.IsAvailable
                ? $"{UsageFormatting.ApiEquivalentCost(estimate)} estimated " +
                  $"API-equivalent usage for {displayedRange.Label()}"
                : "API-equivalent usage unavailable because the transcript " +
                  "model is unknown");
    }

    private FrameworkElement BuildTokenAgentSection(
        string label,
        TokenUsage? usage,
        TokenKindSelection selection,
        TokenValueDisplayMode displayMode)
    {
        var section = new StackPanel();
        var header = new Grid();
        header.ColumnDefinitions.Add(new ColumnDefinition());
        header.ColumnDefinitions.Add(new ColumnDefinition
        {
            Width = GridLength.Auto,
        });
        header.Children.Add(new TextBlock
        {
            Text = label.ToUpperInvariant(),
            FontSize = 12.5,
            FontWeight = FontWeights.SemiBold,
        });
        var total = new TextBlock
        {
            Text = usage is null
                ? "—"
                : UsageFormatting.CompactTokenCount(
                    usage.SelectedTotal(selection)),
            FontFamily = new FontFamily("Cascadia Mono, Consolas"),
            FontSize = 11.5,
            Foreground = FindBrush("SecondaryTextBrush"),
            HorizontalAlignment = HorizontalAlignment.Right,
            ToolTip = usage is null
                ? "No token usage in this range."
                : $"{usage.SelectedTotal(selection):N0} selected tokens " +
                  $"of {usage.OdometerTokens:N0} across all four kinds",
        };
        Grid.SetColumn(total, 1);
        header.Children.Add(total);
        AutomationProperties.SetName(
            header,
            usage is null
                ? $"{label}, no token usage in this range"
                : $"{label}, {usage.SelectedTotal(selection):N0} selected tokens");
        section.Children.Add(header);

        var models = usage?.ModelUsage
            .OrderByDescending(item => item.Breakdown.SelectedTotal(selection))
            .ThenBy(item => item.Model, StringComparer.OrdinalIgnoreCase)
            .ToArray() ?? [];
        if (models.Length == 0)
        {
            section.Children.Add(new TextBlock
            {
                Text = "No token usage in this range.",
                Margin = new Thickness(0, 5, 0, 0),
                FontSize = 11.5,
                Foreground = FindBrush("SecondaryTextBrush"),
            });
            return section;
        }

        foreach (var model in models)
        {
            section.Children.Add(
                BuildTokenModelRow(model, selection, displayMode));
        }

        return section;
    }

    private FrameworkElement BuildTokenModelRow(
        ModelTokenUsage model,
        TokenKindSelection selection,
        TokenValueDisplayMode displayMode)
    {
        var breakdown = model.Breakdown;
        var row = new StackPanel { Margin = new Thickness(0, 6, 0, 0) };
        var values = new[]
        {
            breakdown.Amount(TokenKind.DirectInput),
            breakdown.Amount(TokenKind.Output),
            breakdown.Amount(TokenKind.CacheWrite),
            breakdown.Amount(TokenKind.CacheRead),
        };
        var modelName = string.IsNullOrWhiteSpace(model.Model)
            ? "unknown"
            : model.Model;
        var selectedTotal = breakdown.SelectedTotal(selection);

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition
        {
            Width = new GridLength(1, GridUnitType.Star),
        });
        for (var index = 0; index < values.Length; index++)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = new GridLength(64),
            });
        }

        grid.Children.Add(new TextBlock
        {
            Text = modelName,
            FontSize = 11.5,
            TextTrimming = TextTrimming.CharacterEllipsis,
            ToolTip = modelName,
            VerticalAlignment = VerticalAlignment.Center,
        });
        for (var index = 0; index < values.Length; index++)
        {
            var kind = TokenKindAt(index);
            var included = selection.Includes(kind);
            var percentage = selectedTotal > 0
                ? (decimal)values[index] / selectedTotal * 100m
                : 0m;
            var value = new TextBlock
            {
                Text = included
                    ? UsageFormatting.TokenCell(
                        values[index],
                        selectedTotal,
                        displayMode)
                    : values[index] == 0
                        ? "–"
                        : UsageFormatting.CompactTokenCount(values[index]),
                FontFamily = new FontFamily("Cascadia Mono, Consolas"),
                FontSize = included &&
                           displayMode ==
                           TokenValueDisplayMode.ValueAndPercentage
                    ? 9.5
                    : 10.5,
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Center,
                TextAlignment = TextAlignment.Right,
                LineHeight = 12,
                Opacity = included ? 1 : 0.32,
                ToolTip = included
                    ? $"{TokenKindName(index)}: {values[index]:N0} " +
                      $"({percentage:0.#}% of selected kinds)"
                    : $"{TokenKindName(index)}: {values[index]:N0}; " +
                      "dimmed and excluded from composition percentages",
            };
            Grid.SetColumn(value, index + 1);
            grid.Children.Add(value);
        }

        AutomationProperties.SetName(
            grid,
            $"{modelName}; direct input {values[0]:N0}; output {values[1]:N0}; " +
            $"cache write {values[2]:N0}; cache read {values[3]:N0}");
        row.Children.Add(grid);
        row.Children.Add(BuildTokenProportionBar(values, selection));
        return row;
    }

    private static FrameworkElement BuildTokenProportionBar(
        long[] values,
        TokenKindSelection selection)
    {
        var total = values
            .Where((_, index) => selection.Includes(TokenKindAt(index)))
            .Sum();
        var bar = new Grid
        {
            Height = 4,
            Margin = new Thickness(0, 4, 0, 0),
            Background = FindBrush("SubtleBackgroundBrush"),
            ClipToBounds = true,
            ToolTip =
                $"IN {values[0]:N0} · OUT {values[1]:N0} · " +
                $"C·W {values[2]:N0} · C·R {values[3]:N0}",
        };
        AutomationProperties.SetName(
            bar,
            "Token proportions: " +
            $"direct input {values[0]:N0}, output {values[1]:N0}, " +
            $"cache write {values[2]:N0}, cache read {values[3]:N0}");
        for (var index = 0; index < values.Length; index++)
        {
            var included = selection.Includes(TokenKindAt(index));
            var weight = total == 0 || !included
                ? 0
                : (double)values[index] / total;
            bar.ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = new GridLength(weight, GridUnitType.Star),
                MinWidth = included && values[index] > 0 ? 1.5 : 0,
            });
            var segment = new Border
            {
                Background = TokenKindBrush(index),
                Opacity = included ? 0.9 : 0,
            };
            Grid.SetColumn(segment, index);
            bar.Children.Add(segment);
        }

        return bar;
    }

    private static Brush TokenKindBrush(int index) =>
        FindBrush(
            index switch
            {
                0 => "TokenInputBrush",
                1 => "TokenOutputBrush",
                2 => "TokenCacheWriteBrush",
                _ => "TokenCacheReadBrush",
            });

    private static string TokenKindName(int index) =>
        index switch
        {
            0 => "Direct input",
            1 => "Output",
            2 => "Cache write",
            _ => "Cache read",
        };

    private static TokenKind TokenKindAt(int index) =>
        index switch
        {
            0 => TokenKind.DirectInput,
            1 => TokenKind.Output,
            2 => TokenKind.CacheWrite,
            3 => TokenKind.CacheRead,
            _ => throw new ArgumentOutOfRangeException(nameof(index), index, null),
        };

    private FrameworkElement BuildAgentSection(AgentPresentation agent)
    {
        var section = new StackPanel();
        var header = new Grid();
        header.ColumnDefinitions.Add(new ColumnDefinition());
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var heading = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            VerticalAlignment = VerticalAlignment.Center,
        };
        heading.Children.Add(new TextBlock
        {
            Text = agent.Definition.DisplayName,
            FontSize = 14,
            FontWeight = FontWeights.SemiBold,
            VerticalAlignment = VerticalAlignment.Center,
        });
        if (_coordinator.Appearance.PrimaryAgent == agent.Definition.Id)
        {
            heading.Children.Add(new Border
            {
                Margin = new Thickness(7, 0, 0, 0),
                Padding = new Thickness(6, 2, 6, 2),
                CornerRadius = new CornerRadius(8),
                Background = FindBrush("AccentSoftBrush"),
                Child = new TextBlock
                {
                    Text = "PRIMARY",
                    FontSize = 9,
                    FontWeight = FontWeights.SemiBold,
                    Foreground = FindBrush("AccentBrush"),
                },
            });
        }

        header.Children.Add(heading);
        if (agent.IsRefreshing)
        {
            var progress = new ProgressBar
            {
                Width = 34,
                Height = 3,
                IsIndeterminate = true,
                VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(progress, 1);
            header.Children.Add(progress);
        }

        section.Children.Add(header);
        var content = new StackPanel { Margin = new Thickness(0, 10, 0, 0) };
        section.Children.Add(content);

        switch (agent.State.Kind)
        {
            case AgentStateKind.SignedOut:
                content.Children.Add(SecondaryText(
                    $"Not signed in to {agent.Definition.DisplayName}."));
                var signIn = new Button
                {
                    Content = "Sign in…",
                    Margin = new Thickness(0, 9, 0, 0),
                    HorizontalAlignment = HorizontalAlignment.Left,
                };
                signIn.Click += (_, _) =>
                {
                    HideFlyout();
                    _showSettings();
                };
                content.Children.Add(signIn);
                break;

            case AgentStateKind.Loading:
                if (agent.IsRefreshing)
                {
                    content.Children.Add(SecondaryText("Loading usage…"));
                }
                else
                {
                    content.Children.Add(
                        BuildStatus(
                            agent,
                            "Couldn't load usage.",
                            isStale: true));
                }

                break;

            case AgentStateKind.Fresh:
                if (agent.State.Snapshot is { } fresh)
                {
                    content.Children.Add(BuildGauges(agent.Definition, fresh));
                    content.Children.Add(
                        BuildStatus(
                            agent,
                            $"Updated {UsageFormatting.RelativeAge(fresh.FetchedAt)}",
                            isStale: false));
                }

                break;

            case AgentStateKind.StaleDisclosed:
                if (agent.State.Snapshot is { } stale)
                {
                    content.Children.Add(BuildGauges(agent.Definition, stale));
                    content.Children.Add(
                        BuildStatus(
                            agent,
                            $"Couldn't refresh · last updated {UsageFormatting.RelativeAge(stale.FetchedAt)}",
                            isStale: true));
                }

                break;
        }

        return section;
    }

    private FrameworkElement BuildGauges(
        AgentDefinition definition,
        UsageSnapshot snapshot)
    {
        var style = _coordinator.Appearance.GaugeStyle;
        var slots = definition.Id == AgentId.Codex
            ? snapshot.Windows
                .Select(window => new GaugeSlot(
                    window.Label,
                    window.Kind == UsageWindowKind.ShortTerm))
                .ToArray()
            : definition.GaugeSlots;
        if (slots.Count == 0)
        {
            return SecondaryText("No active Usage Windows.");
        }

        if (style == GaugeStyle.Bar)
        {
            var stack = new StackPanel { Margin = new Thickness(0, 2, 0, 3) };
            foreach (var slot in slots)
            {
                var gauge = CreateGauge(slot, snapshot, style);
                gauge.Margin = new Thickness(0, 0, 0, 7);
                stack.Children.Add(gauge);
            }

            return stack;
        }

        var row = new StackPanel
        {
            Margin = new Thickness(0, 1, 0, 4),
            HorizontalAlignment = HorizontalAlignment.Center,
            Orientation = Orientation.Horizontal,
        };
        foreach (var slot in slots)
        {
            var gauge = CreateGauge(slot, snapshot, style);
            var codex = definition.Id == AgentId.Codex;
            gauge.Width = codex ? 128 : slot.Emphasized ? 112 : 96;
            gauge.Height = codex ? 154 : slot.Emphasized ? 164 : 146;
            gauge.Margin = new Thickness(codex ? 6 : 2, 0, codex ? 6 : 2, 0);
            row.Children.Add(gauge);
        }

        return row;
    }

    private static UsageGauge CreateGauge(
        GaugeSlot slot,
        UsageSnapshot snapshot,
        GaugeStyle style)
    {
        var window = snapshot.Windows.FirstOrDefault(
            item => string.Equals(item.Label, slot.Label, StringComparison.Ordinal));
        var gauge = new UsageGauge
        {
            Label = slot.Label,
            IsEmphasized = slot.Emphasized,
            GaugeStyle = style,
            IsAvailable = window is not null,
            Remaining = window?.PercentRemaining ?? 0,
            ResetText = window?.ResetAt is { } resetAt
                ? UsageFormatting.CompactDuration(resetAt)
                : "—",
        };
        var spoken = window is null
            ? $"{slot.Label}, not available"
            : $"{slot.Label}, {UsageFormatting.RemainingPercent(window.PercentRemaining)} left, " +
              (window.ResetAt is { } reset
                  ? UsageFormatting.ResetCountdown(reset)
                  : "reset time unknown");
        AutomationProperties.SetName(gauge, spoken);
        return gauge;
    }

    private FrameworkElement BuildStatus(
        AgentPresentation agent,
        string text,
        bool isStale)
    {
        var wrapper = new StackPanel { Margin = new Thickness(0, 5, 0, 0) };
        var hasDiagnostics = !string.IsNullOrWhiteSpace(agent.Diagnostics);
        var status = new Button
        {
            HorizontalAlignment = HorizontalAlignment.Right,
            Padding = new Thickness(3, 2, 0, 2),
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            IsHitTestVisible = hasDiagnostics,
            Focusable = hasDiagnostics,
            Cursor = hasDiagnostics ? Cursors.Hand : Cursors.Arrow,
        };
        var statusRow = new StackPanel { Orientation = Orientation.Horizontal };
        if (isStale)
        {
            statusRow.Children.Add(new TextBlock
            {
                Text = "⚠",
                Margin = new Thickness(0, 0, 6, 0),
                Foreground = FindBrush("SecondaryTextBrush"),
            });
        }

        statusRow.Children.Add(new TextBlock
        {
            Text = text,
            FontSize = 11.5,
            Foreground = FindBrush("SecondaryTextBrush"),
        });
        if (hasDiagnostics)
        {
            statusRow.Children.Add(new TextBlock
            {
                Text = _expandedDiagnostics.Contains(agent.Definition.Id) ? "⌄" : "›",
                Margin = new Thickness(6, 0, 0, 0),
                Foreground = FindBrush("SecondaryTextBrush"),
            });
        }

        status.Content = statusRow;
        if (hasDiagnostics)
        {
            status.Click += (_, _) =>
            {
                if (!_expandedDiagnostics.Add(agent.Definition.Id))
                {
                    _expandedDiagnostics.Remove(agent.Definition.Id);
                }

                Render();
            };
        }

        wrapper.Children.Add(status);
        if (hasDiagnostics && _expandedDiagnostics.Contains(agent.Definition.Id))
        {
            wrapper.Children.Add(new TextBox
            {
                Text = agent.Diagnostics,
                Margin = new Thickness(0, 5, 0, 0),
                Padding = new Thickness(7),
                MaxHeight = 160,
                IsReadOnly = true,
                TextWrapping = TextWrapping.Wrap,
                AcceptsReturn = true,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                FontFamily = new FontFamily("Cascadia Mono, Consolas"),
                FontSize = 11,
            });
        }

        return wrapper;
    }

    private static TextBlock SecondaryText(string text) =>
        new()
        {
            Text = text,
            FontSize = 12,
            Foreground = FindBrush("SecondaryTextBrush"),
        };

    private bool TrySaveDisplayPreferences(AppearancePreferences preferences)
    {
        try
        {
            _settings.SaveAppearance(preferences);
            return true;
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                this,
                $"Could not save TokenStats display settings.\n\n{exception.Message}",
                "TokenStats",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            Render();
            return false;
        }
    }

    private void ApplyPinnedState(bool pinned)
    {
        var wasPinned = _isPinned;
        _isPinned = pinned;
        Topmost = pinned;
        PinButton.ToolTip = pinned
            ? "Unpin flyout"
            : "Keep flyout on top";
        AutomationProperties.SetName(
            PinButton,
            pinned ? "Unpin flyout" : "Keep flyout on top");
        AutomationProperties.SetHelpText(
            PinButton,
            pinned
                ? "The flyout remains visible and above other windows."
                : "Pin the flyout so it remains visible and above other windows.");

        if (wasPinned && !pinned && IsVisible && !IsActive)
        {
            Dispatcher.BeginInvoke(
                () =>
                {
                    if (IsVisible &&
                        !_isPinned &&
                        !IsActive &&
                        !IsKeyboardFocusWithin &&
                        SettingsButton.ContextMenu?.IsOpen != true)
                    {
                        HideFlyout();
                    }
                },
                DispatcherPriority.Background);
        }
    }

    private static Brush FindBrush(string key) =>
        System.Windows.Application.Current.TryFindResource(key) as Brush ??
        Brushes.Gray;

    private void FlyoutWindow_OnDeactivated(object? sender, EventArgs eventArgs) =>
        Dispatcher.BeginInvoke(
            () =>
            {
                if (IsVisible &&
                    !_isPinned &&
                    !IsKeyboardFocusWithin &&
                    SettingsButton.ContextMenu?.IsOpen != true)
                {
                    HideFlyout();
                }
            },
            DispatcherPriority.Background);

    private void FlyoutWindow_OnClosing(
        object? sender,
        System.ComponentModel.CancelEventArgs eventArgs)
    {
        if (_allowClose)
        {
            return;
        }

        eventArgs.Cancel = true;
        HideFlyout();
    }

    private void FlyoutWindow_OnClosed(object? sender, EventArgs eventArgs)
    {
        _ageTimer.Stop();
        _coordinator.Changed -= Coordinator_OnChanged;
        _tokenOdometer.Changed -= TokenOdometer_OnChanged;
        WindowsThemeService.ThemeChanged -= WindowsThemeService_OnThemeChanged;
    }

    private void WindowsThemeService_OnThemeChanged(
        object? sender,
        EventArgs eventArgs)
    {
        if (Dispatcher.CheckAccess())
        {
            Render();
        }
        else
        {
            Dispatcher.BeginInvoke(Render);
        }
    }

    private void FlyoutWindow_OnPreviewKeyDown(object sender, KeyEventArgs eventArgs)
    {
        if (eventArgs.Key == Key.Escape)
        {
            HideFlyout();
            eventArgs.Handled = true;
            return;
        }

        if ((Keyboard.Modifiers & ModifierKeys.Control) == 0)
        {
            return;
        }

        if (eventArgs.Key == Key.R)
        {
            RefreshButton_OnClick(RefreshButton, new RoutedEventArgs());
            eventArgs.Handled = true;
        }
        else if (eventArgs.Key == Key.OemComma)
        {
            HideFlyout();
            _showSettings();
            eventArgs.Handled = true;
        }
    }

    private void FlyoutWindow_OnSizeChanged(
        object sender,
        SizeChangedEventArgs eventArgs)
    {
        if (!_isPositioning && IsVisible)
        {
            QueueReposition();
        }
    }

    private void QueueReposition()
    {
        if (_isPositioning ||
            !IsVisible ||
            _repositionOperation is
            {
                Status: DispatcherOperationStatus.Pending,
            })
        {
            return;
        }

        _repositionOperation = Dispatcher.BeginInvoke(
            () =>
            {
                _repositionOperation = null;
                if (IsVisible)
                {
                    PositionNearNotificationArea(settleDpi: false);
                }
            },
            DispatcherPriority.Loaded);
    }

    private void PositionNearNotificationArea(bool settleDpi)
    {
        if (_isPositioning || !IsVisible)
        {
            return;
        }

        _isPositioning = true;
        try
        {
            var helper = new WindowInteropHelper(this);
            var handle = helper.Handle;
            if (handle == IntPtr.Zero)
            {
                return;
            }

            if (!_hasNotificationAreaAnchor)
            {
                _notificationAreaAnchor = Forms.Cursor.Position;
                _hasNotificationAreaAnchor = true;
            }

            var screen = Forms.Screen.FromPoint(_notificationAreaAnchor);
            var working = screen.WorkingArea;
            var bounds = screen.Bounds;
            var dpi = GetDpiForWindow(handle);
            var scale = dpi > 0 ? dpi / 96d : 1d;
            var availableHeight = Math.Max(1, (working.Height - 16) / scale);
            var availableWidth = Math.Max(1, (working.Width - 16) / scale);
            MaxWidth = availableWidth;
            MaxHeight = Math.Min(760, availableHeight);
            UpdateLayout();
            var width = Math.Max(1, (int)Math.Ceiling(ActualWidth * scale));
            var height = Math.Max(1, (int)Math.Ceiling(ActualHeight * scale));
            const int margin = 8;
            var placement = WindowSizing.CalculateFlyoutPlacement(
                working,
                bounds,
                _notificationAreaAnchor,
                new System.Drawing.Size(width, height),
                margin);

            SetWindowPos(
                handle,
                IntPtr.Zero,
                placement.X,
                placement.Y,
                placement.Width,
                placement.Height,
                SetWindowPosFlags.NoZOrder |
                SetWindowPosFlags.NoOwnerZOrder |
                SetWindowPosFlags.NoActivate);

            if (settleDpi)
            {
                // The first Show can be created at the primary monitor's DPI.
                // Re-run once after Windows has moved it to the tray monitor.
                Dispatcher.BeginInvoke(
                    () => PositionNearNotificationArea(settleDpi: false),
                    DispatcherPriority.Loaded);
            }
        }
        finally
        {
            _isPositioning = false;
        }
    }

    [Flags]
    private enum SetWindowPosFlags : uint
    {
        NoZOrder = 0x0004,
        NoActivate = 0x0010,
        NoOwnerZOrder = 0x0200,
    }

    private enum FlyoutTab
    {
        Usage,
        Tokens,
    }

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr window);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(
        IntPtr window,
        IntPtr insertAfter,
        int x,
        int y,
        int width,
        int height,
        SetWindowPosFlags flags);
}
