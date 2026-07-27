using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
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
    private readonly TokensTodayWatcher _tokensToday;
    private readonly Action _showSettings;
    private readonly Action _quit;
    private readonly HashSet<AgentId> _expandedDiagnostics = [];
    private readonly DispatcherTimer _ageTimer;
    private bool _allowClose;
    private bool _refreshInFlight;

    public FlyoutWindow(
        UsageCoordinator coordinator,
        TokensTodayWatcher tokensToday,
        Action showSettings,
        Action quit)
    {
        _coordinator = coordinator;
        _tokensToday = tokensToday;
        _showSettings = showSettings;
        _quit = quit;
        InitializeComponent();
        WindowsThemeService.Attach(this);

        _coordinator.Changed += Coordinator_OnChanged;
        _tokensToday.Changed += TokensToday_OnChanged;
        WindowsThemeService.ThemeChanged += WindowsThemeService_OnThemeChanged;
        Deactivated += FlyoutWindow_OnDeactivated;
        Closing += FlyoutWindow_OnClosing;
        Closed += FlyoutWindow_OnClosed;
        PreviewKeyDown += FlyoutWindow_OnPreviewKeyDown;
        var settingsMenu = new ContextMenu();
        var openSettings = new MenuItem { Header = "Settings…" };
        openSettings.Click += (_, _) =>
        {
            HideFlyout();
            _showSettings();
        };
        var quitItem = new MenuItem { Header = "Quit TokenStats" };
        quitItem.Click += (_, _) => _quit();
        settingsMenu.Items.Add(openSettings);
        settingsMenu.Items.Add(new Separator());
        settingsMenu.Items.Add(quitItem);
        settingsMenu.Closed += (_, _) =>
        {
            if (IsVisible && !IsActive)
            {
                HideFlyout();
            }
        };
        SettingsButton.ContextMenu = settingsMenu;
        _ageTimer = new DispatcherTimer(TimeSpan.FromSeconds(30), DispatcherPriority.Background, (_, _) => Render(), Dispatcher);
        Render();
    }

    public void ShowFlyout()
    {
        Render();
        Show();
        UpdateLayout();
        PositionNearNotificationArea(settleDpi: true);
        Activate();
        Focus();
        _ageTimer.Start();
        _ = _tokensToday.SetVisibleAsync(true);
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
        _ = _tokensToday.SetVisibleAsync(false);
    }

    public void AllowClose() => _allowClose = true;

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
            await _coordinator.RefreshAllAsync(RefreshTrigger.Manual)
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

    private void TokensToday_OnChanged(object? sender, EventArgs eventArgs) =>
        Dispatcher.BeginInvoke(RenderTokensToday);

    private void Render()
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.BeginInvoke(Render);
            return;
        }

        RenderTokensToday();
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

    private void RenderTokensToday()
    {
        var usage = _tokensToday.Usage;
        if (usage is null)
        {
            TokensTodayPanel.Visibility = Visibility.Collapsed;
            return;
        }

        TokensTodayPanel.Visibility = Visibility.Visible;
        if (_coordinator.Appearance.TodayMetric == TodayMetricMode.Usage)
        {
            RenderApiEquivalentToday(usage);
        }
        else
        {
            RenderBillingTokensToday(usage);
        }
    }

    private void RenderBillingTokensToday(TokenUsage usage)
    {
        TokensTodayCount.Text = usage.BillableTokens.ToString("N0");
        TokensTodayLabel.Text = "billing tokens today";
        var agentSplit = string.Join(
            " · ",
            _tokensToday.PerAgent.Select(
                slice => $"{slice.Label} {slice.Usage.BillableTokens:N0}"));
        TokensTodayPanel.ToolTip =
            $"{(agentSplit.Length > 0 ? agentSplit + " — " : string.Empty)}" +
            $"{UsageFormatting.TokenBreakdown(usage)}. " +
            "Token excludes cache reads.";
        AutomationProperties.SetName(
            TokensTodayPanel,
            $"{usage.BillableTokens:N0} billing tokens today; cache reads excluded");
    }

    private void RenderApiEquivalentToday(TokenUsage usage)
    {
        var pricingDate = DateOnly.FromDateTime(DateTime.Today);
        var estimate = ApiPricingCatalog.Estimate(usage, pricingDate);
        TokensTodayCount.Text = UsageFormatting.ApiEquivalentCost(estimate);
        TokensTodayLabel.Text = "API-equivalent today";

        var agentSplit = string.Join(
            " · ",
            _tokensToday.PerAgent.Select(slice =>
            {
                var agentEstimate =
                    ApiPricingCatalog.Estimate(slice.Usage, pricingDate);
                return $"{slice.Label} " +
                       UsageFormatting.ApiEquivalentCost(agentEstimate);
            }));
        var unpriced = estimate.IsPartial
            ? $" Unpriced: {string.Join(", ", estimate.UnpricedModels)} " +
              $"({estimate.UnpricedTokens:N0} tokens)."
            : string.Empty;
        var models = string.Join(
            ", ",
            usage.ModelUsage
                .Select(item => item.Model ?? "unknown model")
                .Distinct(StringComparer.OrdinalIgnoreCase));
        TokensTodayPanel.ToolTip =
            $"{(agentSplit.Length > 0 ? agentSplit + " — " : string.Empty)}" +
            "Standard API-equivalent estimate by recorded model; includes " +
            "raw input, cache writes, cache reads, and output at list rates. " +
            "Claude cache writes without TTL detail use the default 5-minute rate. " +
            $"Models: {(models.Length > 0 ? models : "unknown")}. " +
            $"Prices reviewed {ApiPricingCatalog.LastReviewed:yyyy-MM-dd}." +
            unpriced;
        AutomationProperties.SetName(
            TokensTodayPanel,
            estimate.IsAvailable
                ? $"{UsageFormatting.ApiEquivalentCost(estimate)} estimated API-equivalent usage today"
                : "API-equivalent usage unavailable because the transcript model is unknown");
    }

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

    private static Brush FindBrush(string key) =>
        System.Windows.Application.Current.TryFindResource(key) as Brush ??
        Brushes.Gray;

    private void FlyoutWindow_OnDeactivated(object? sender, EventArgs eventArgs) =>
        Dispatcher.BeginInvoke(
            () =>
            {
                if (IsVisible &&
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
        _tokensToday.Changed -= TokensToday_OnChanged;
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

    private void PositionNearNotificationArea(bool settleDpi)
    {
        var helper = new WindowInteropHelper(this);
        var handle = helper.Handle;
        var cursor = Forms.Cursor.Position;
        var screen = Forms.Screen.FromPoint(cursor);
        var working = screen.WorkingArea;
        var bounds = screen.Bounds;
        var dpi = GetDpiForWindow(handle);
        var scale = dpi / 96d;
        var availableHeight = Math.Max(
            280,
            (working.Height - 16) / scale);
        MaxHeight = availableHeight;
        ContentScroll.MaxHeight = Math.Max(170, availableHeight - 110);
        UpdateLayout();
        var width = Math.Max(1, (int)Math.Ceiling(ActualWidth * scale));
        var height = Math.Max(1, (int)Math.Ceiling(ActualHeight * scale));
        const int margin = 8;

        var x = Math.Clamp(
            cursor.X - width + 24,
            working.Left + margin,
            Math.Max(working.Left + margin, working.Right - width - margin));
        int y;
        if (working.Top > bounds.Top)
        {
            y = working.Top + margin;
        }
        else if (working.Left > bounds.Left)
        {
            x = working.Left + margin;
            y = Math.Clamp(
                cursor.Y - height / 2,
                working.Top + margin,
                Math.Max(working.Top + margin, working.Bottom - height - margin));
        }
        else if (working.Right < bounds.Right)
        {
            x = working.Right - width - margin;
            y = Math.Clamp(
                cursor.Y - height / 2,
                working.Top + margin,
                Math.Max(working.Top + margin, working.Bottom - height - margin));
        }
        else
        {
            y = working.Bottom - height - margin;
        }

        SetWindowPos(
            handle,
            IntPtr.Zero,
            x,
            y,
            width,
            height,
            SetWindowPosFlags.NoZOrder | SetWindowPosFlags.NoOwnerZOrder);

        if (settleDpi)
        {
            // The first Show can be created at the primary monitor's DPI.
            // Re-run once after Windows has moved it to the tray monitor.
            Dispatcher.BeginInvoke(
                () => PositionNearNotificationArea(settleDpi: false),
                DispatcherPriority.Loaded);
        }
    }

    [Flags]
    private enum SetWindowPosFlags : uint
    {
        NoZOrder = 0x0004,
        NoOwnerZOrder = 0x0200,
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
