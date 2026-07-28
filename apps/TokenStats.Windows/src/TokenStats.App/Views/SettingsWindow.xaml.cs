using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using TokenStats.App.Controls;
using TokenStats.App.Infrastructure;
using TokenStats.App.Services;
using TokenStats.Core;

namespace TokenStats.App.Views;

public partial class SettingsWindow : Window
{
    private readonly UsageCoordinator _coordinator;
    private readonly AppSettingsStore _settings;
    private readonly Action _runSetupAgain;
    private readonly HashSet<AgentId> _loginBusy = [];
    private readonly Dictionary<AgentId, string> _pastedCodes = [];
    private bool _isRendering;

    public SettingsWindow(
        UsageCoordinator coordinator,
        AppSettingsStore settings,
        Action runSetupAgain)
    {
        _coordinator = coordinator;
        _settings = settings;
        _runSetupAgain = runSetupAgain;
        InitializeComponent();
        WindowsThemeService.Attach(this);

        PrimaryAgentCombo.ItemsSource = AgentRegistry.All;
        VersionText.Text = $"Version {Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "—"}";
        _coordinator.Changed += Coordinator_OnChanged;
        WindowsThemeService.ThemeChanged += WindowsThemeService_OnThemeChanged;
        Closed += SettingsWindow_OnClosed;
        SourceInitialized += (_, _) => ConstrainToWorkArea();
        LocationChanged += (_, _) => ConstrainToWorkArea();
        Render();
    }

    private void ConstrainToWorkArea()
    {
        WindowSizing.ConstrainToCurrentWorkArea(this, 480, 320);
        NavigationColumn.Width = new GridLength(MaxWidth < 620 ? 150 : 190);
    }

    private void Render()
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.BeginInvoke(Render);
            return;
        }

        _isRendering = true;
        try
        {
            RenderAccounts();
            var appearance = _settings.Appearance;
            PrimaryAgentCombo.SelectedValue = appearance.PrimaryAgent;
            DialStyle.IsChecked = appearance.GaugeStyle == GaugeStyle.Dial;
            RingStyle.IsChecked = appearance.GaugeStyle == GaugeStyle.Ring;
            BarStyle.IsChecked = appearance.GaugeStyle == GaugeStyle.Bar;
            UsageMetric.IsChecked =
                appearance.TodayMetric == TodayMetricMode.Usage;
            TokenMetric.IsChecked =
                appearance.TodayMetric == TodayMetricMode.Token;
            TokenValueMode.IsChecked =
                appearance.TokenValueDisplay == TokenValueDisplayMode.Value;
            TokenPercentageMode.IsChecked =
                appearance.TokenValueDisplay == TokenValueDisplayMode.Percentage;
            TokenValuePercentageMode.IsChecked =
                appearance.TokenValueDisplay ==
                TokenValueDisplayMode.ValueAndPercentage;
            AlwaysOnTopCheckBox.IsChecked = appearance.AlwaysOnTop;
            RenderAgentOrder(appearance);
            try
            {
                StartWithWindowsCheckBox.IsChecked = StartupManager.IsEnabled;
                StartWithWindowsCheckBox.IsEnabled = true;
                StartWithWindowsCheckBox.ToolTip = null;
            }
            catch (Exception exception)
            {
                StartWithWindowsCheckBox.IsEnabled = false;
                StartWithWindowsCheckBox.ToolTip =
                    $"Windows startup setting is unavailable: {exception.Message}";
            }

            RenderGaugePreview(appearance.GaugeStyle);
        }
        finally
        {
            _isRendering = false;
        }
    }

    private void RenderAccounts()
    {
        AccountsPanel.Children.Clear();
        foreach (var agent in _coordinator.Agents)
        {
            var card = new Border
            {
                Margin = new Thickness(0, 0, 0, 12),
                Style = (Style)FindResource("CardBorder"),
            };
            var body = new StackPanel();
            card.Child = body;

            var header = new Grid();
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            header.ColumnDefinitions.Add(new ColumnDefinition());
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            header.Children.Add(BrandBadge(agent.Definition));

            var identity = new StackPanel
            {
                Margin = new Thickness(11, 0, 12, 0),
                VerticalAlignment = VerticalAlignment.Center,
            };
            identity.Children.Add(new TextBlock
            {
                Text = agent.Definition.DisplayName,
                FontWeight = FontWeights.SemiBold,
                FontSize = 14,
            });
            identity.Children.Add(new TextBlock
            {
                Text = ConnectionText(agent),
                Margin = new Thickness(0, 2, 0, 0),
                FontSize = 11.5,
                Foreground = ConnectionBrush(agent),
            });
            Grid.SetColumn(identity, 1);
            header.Children.Add(identity);

            if (agent.State.Kind != AgentStateKind.SignedOut)
            {
                var signOut = new Button
                {
                    Content = "Sign out",
                    Foreground = FindBrush("DangerBrush"),
                    VerticalAlignment = VerticalAlignment.Center,
                };
                signOut.Click += (_, _) => _coordinator.SignOut(agent.Definition.Id);
                Grid.SetColumn(signOut, 2);
                header.Children.Add(signOut);
            }
            else
            {
                var signInBusy =
                    _loginBusy.Contains(agent.Definition.Id) ||
                    (agent.IsSigningIn &&
                     agent.Definition.SignInStyle == SignInStyle.SelfCompleting);
                var signIn = new Button
                {
                    Content = signInBusy
                        ? "Waiting for browser…"
                        : agent.AwaitingCode
                            ? "Re-open browser"
                            : "Sign in",
                    IsEnabled = !signInBusy,
                    VerticalAlignment = VerticalAlignment.Center,
                };
                signIn.Click += async (_, _) =>
                    await BeginLoginAsync(agent.Definition.Id).ConfigureAwait(true);
                Grid.SetColumn(signIn, 2);
                header.Children.Add(signIn);
            }

            body.Children.Add(header);
            if (agent.AwaitingCode)
            {
                var codeRow = new Grid { Margin = new Thickness(43, 12, 0, 0) };
                codeRow.ColumnDefinitions.Add(new ColumnDefinition());
                codeRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                var code = new TextBox
                {
                    Text = _pastedCodes.GetValueOrDefault(agent.Definition.Id, string.Empty),
                    ToolTip = "Paste the code#state shown in the browser",
                };
                codeRow.Children.Add(code);
                var submit = new Button
                {
                    Content = "Submit",
                    Margin = new Thickness(8, 0, 0, 0),
                    IsEnabled = !_loginBusy.Contains(agent.Definition.Id) &&
                                !string.IsNullOrWhiteSpace(code.Text),
                };
                code.TextChanged += (_, _) =>
                {
                    _pastedCodes[agent.Definition.Id] = code.Text;
                    submit.IsEnabled = !_loginBusy.Contains(agent.Definition.Id) &&
                                       !string.IsNullOrWhiteSpace(code.Text);
                };
                code.KeyDown += async (_, eventArgs) =>
                {
                    if (eventArgs.Key == System.Windows.Input.Key.Enter &&
                        !string.IsNullOrWhiteSpace(code.Text))
                    {
                        await SubmitCodeAsync(agent.Definition.Id, code.Text)
                            .ConfigureAwait(true);
                    }
                };
                submit.Click += async (_, _) =>
                    await SubmitCodeAsync(agent.Definition.Id, code.Text)
                        .ConfigureAwait(true);
                Grid.SetColumn(submit, 1);
                codeRow.Children.Add(submit);
                body.Children.Add(codeRow);
            }

            if (!string.IsNullOrWhiteSpace(agent.LoginError))
            {
                body.Children.Add(new TextBlock
                {
                    Text = $"⚠ {agent.LoginError}",
                    Margin = new Thickness(43, 10, 0, 0),
                    Foreground = FindBrush("DangerBrush"),
                    FontSize = 11.5,
                });
            }

            AccountsPanel.Children.Add(card);
        }
    }

    private async Task BeginLoginAsync(AgentId id)
    {
        if (!_loginBusy.Add(id))
        {
            return;
        }

        RenderAccounts();
        try
        {
            await _coordinator.BeginSignInAsync(id).ConfigureAwait(true);
        }
        finally
        {
            _loginBusy.Remove(id);
            RenderAccounts();
        }
    }

    private async Task SubmitCodeAsync(AgentId id, string code)
    {
        if (string.IsNullOrWhiteSpace(code) || !_loginBusy.Add(id))
        {
            return;
        }

        RenderAccounts();
        try
        {
            await _coordinator.CompleteSignInAsync(id, code).ConfigureAwait(true);
            if (_coordinator.GetAgent(id).State.Kind != AgentStateKind.SignedOut)
            {
                _pastedCodes.Remove(id);
            }
        }
        finally
        {
            _loginBusy.Remove(id);
            RenderAccounts();
        }
    }

    private void RenderGaugePreview(GaugeStyle style)
    {
        GaugePreviewPanel.Children.Clear();
        var samples = new[]
        {
            (Slot: new GaugeSlot("5-hour", true), Remaining: 72d, Reset: "3h 20m"),
            (Slot: new GaugeSlot("Weekly"), Remaining: 28d, Reset: "4d"),
        };
        var panel = new StackPanel
        {
            Orientation = style == GaugeStyle.Bar
                ? Orientation.Vertical
                : Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        foreach (var sample in samples)
        {
            panel.Children.Add(new UsageGauge
            {
                Label = sample.Slot.Label,
                IsEmphasized = sample.Slot.Emphasized,
                GaugeStyle = style,
                Remaining = sample.Remaining,
                ResetText = sample.Reset,
                IsAvailable = true,
                Width = style == GaugeStyle.Bar ? 360 : sample.Slot.Emphasized ? 108 : 94,
                Height = style == GaugeStyle.Bar ? 70 : sample.Slot.Emphasized ? 154 : 142,
                Margin = new Thickness(4),
            });
        }

        GaugePreviewPanel.Children.Add(panel);
    }

    private void RenderAgentOrder(AppearancePreferences appearance)
    {
        AgentOrderPanel.Children.Clear();
        var order = appearance.DisplayOrder();
        for (var index = 0; index < order.Count; index++)
        {
            var definition = AgentRegistry.Get(order[index]);
            var row = new Grid
            {
                Margin = new Thickness(0, index == 0 ? 0 : 8, 0, 0),
            };
            row.ColumnDefinitions.Add(new ColumnDefinition());
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.Children.Add(new TextBlock { Text = definition.DisplayName });
            if (definition.Id == appearance.PrimaryAgent)
            {
                var primary = new TextBlock
                {
                    Text = "Primary",
                    Foreground = FindBrush("AccentBrush"),
                    FontSize = 11,
                };
                Grid.SetColumn(primary, 1);
                row.Children.Add(primary);
            }

            AgentOrderPanel.Children.Add(row);
        }
    }

    private void Navigation_OnSelectionChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        // SelectedIndex is applied while InitializeComponent is still creating
        // the later page fields, so the first event can legitimately arrive
        // before those named elements exist.
        if (AccountsPage is null ||
            AppearancePage is null ||
            AboutPage is null ||
            Navigation.SelectedItem is not ListBoxItem item)
        {
            return;
        }

        var selected = item.Tag as string;
        AccountsPage.Visibility = selected == "accounts"
            ? Visibility.Visible
            : Visibility.Collapsed;
        AppearancePage.Visibility = selected == "appearance"
            ? Visibility.Visible
            : Visibility.Collapsed;
        AboutPage.Visibility = selected == "about"
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void PrimaryAgentCombo_OnSelectionChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        if (_isRendering || PrimaryAgentCombo.SelectedValue is not AgentId id)
        {
            return;
        }

        TrySaveDisplayPreferences(
            _settings.Appearance with { PrimaryAgent = id });
    }

    private void GaugeStyle_OnChecked(object sender, RoutedEventArgs eventArgs)
    {
        if (_isRendering ||
            sender is not RadioButton { Tag: string value } ||
            !Enum.TryParse<GaugeStyle>(value, out var style))
        {
            return;
        }

        TrySaveDisplayPreferences(
            _settings.Appearance with { GaugeStyle = style });
    }

    private void TodayMetric_OnChecked(object sender, RoutedEventArgs eventArgs)
    {
        if (_isRendering ||
            sender is not RadioButton { Tag: string value } ||
            !Enum.TryParse<TodayMetricMode>(value, out var metric))
        {
            return;
        }

        TrySaveDisplayPreferences(
            _settings.Appearance with { TodayMetric = metric });
    }

    private void TokenValueDisplay_OnChecked(
        object sender,
        RoutedEventArgs eventArgs)
    {
        if (_isRendering ||
            sender is not RadioButton { Tag: string value } ||
            !Enum.TryParse<TokenValueDisplayMode>(value, out var displayMode))
        {
            return;
        }

        TrySaveDisplayPreferences(
            _settings.Appearance with { TokenValueDisplay = displayMode });
    }

    private void AlwaysOnTop_OnChanged(
        object sender,
        RoutedEventArgs eventArgs)
    {
        if (_isRendering)
        {
            return;
        }

        TrySaveDisplayPreferences(
            _settings.Appearance with
            {
                AlwaysOnTop = AlwaysOnTopCheckBox.IsChecked == true,
            });
    }

    private bool TrySaveDisplayPreferences(AppearancePreferences appearance)
    {
        try
        {
            _settings.SaveAppearance(appearance);
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

    private void StartWithWindows_OnChanged(object sender, RoutedEventArgs eventArgs)
    {
        if (_isRendering)
        {
            return;
        }

        try
        {
            StartupManager.IsEnabled = StartWithWindowsCheckBox.IsChecked == true;
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                this,
                $"Could not update the Windows startup setting.\n\n{exception.Message}",
                "TokenStats",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            Render();
        }
    }

    private void ViewOnGitHub_OnClick(object sender, RoutedEventArgs eventArgs) =>
        BrowserLauncher.Open("https://github.com/zhangchi0104/agent-sessions");

    private void RunSetupAgain_OnClick(object sender, RoutedEventArgs eventArgs) =>
        _runSetupAgain();

    private void Coordinator_OnChanged(object? sender, EventArgs eventArgs) =>
        Dispatcher.BeginInvoke(Render);

    private void SettingsWindow_OnClosed(object? sender, EventArgs eventArgs)
    {
        _coordinator.Changed -= Coordinator_OnChanged;
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

    private static Border BrandBadge(AgentDefinition definition)
    {
        var color = definition.Id == AgentId.ClaudeCode
            ? Color.FromRgb(0xD8, 0x78, 0x57)
            : Color.FromRgb(0x0A, 0xA3, 0x80);
        return new Border
        {
            Width = 32,
            Height = 32,
            CornerRadius = new CornerRadius(8),
            Background = new SolidColorBrush(color),
            Child = new TextBlock
            {
                Text = definition.ShortLabel,
                Foreground = Brushes.White,
                FontWeight = FontWeights.Bold,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            },
        };
    }

    private string ConnectionText(AgentPresentation agent)
    {
        if (_loginBusy.Contains(agent.Definition.Id) ||
            (agent.IsSigningIn && !agent.AwaitingCode))
        {
            return agent.Definition.SignInStyle == SignInStyle.PasteCode
                ? "Opening browser…"
                : "Waiting for browser approval…";
        }

        if (agent.AwaitingCode)
        {
            return "Awaiting code";
        }

        return agent.State.Kind == AgentStateKind.SignedOut
            ? "Not signed in"
            : "Connected";
    }

    private Brush ConnectionBrush(AgentPresentation agent)
    {
        if (_loginBusy.Contains(agent.Definition.Id) ||
            agent.IsSigningIn ||
            agent.AwaitingCode)
        {
            return FindBrush("WarningBrush");
        }

        return agent.State.Kind == AgentStateKind.SignedOut
            ? FindBrush("SecondaryTextBrush")
            : FindBrush("AccentBrush");
    }

    private static Brush FindBrush(string key) =>
        System.Windows.Application.Current.TryFindResource(key) as Brush ??
        Brushes.Gray;
}
