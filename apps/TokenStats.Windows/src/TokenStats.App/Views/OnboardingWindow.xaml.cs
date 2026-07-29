using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using TokenStats.App.Infrastructure;
using TokenStats.App.Services;
using TokenStats.Core;

namespace TokenStats.App.Views;

public partial class OnboardingWindow : Window
{
    private readonly UsageCoordinator _coordinator;
    private readonly AppSettingsStore _settings;
    private readonly HashSet<AgentId> _busy = [];
    private readonly Dictionary<AgentId, string> _codes = [];
    private int _step;
    private bool _isRendering;

    public OnboardingWindow(
        UsageCoordinator coordinator,
        AppSettingsStore settings)
    {
        _coordinator = coordinator;
        _settings = settings;
        InitializeComponent();
        WindowsThemeService.Attach(this);
        OnboardingPrimaryCombo.ItemsSource = AgentRegistry.All;
        _coordinator.Changed += Coordinator_OnChanged;
        WindowsThemeService.ThemeChanged += WindowsThemeService_OnThemeChanged;
        Closed += OnboardingWindow_OnClosed;
        SourceInitialized += (_, _) => ConstrainToWorkArea();
        LocationChanged += (_, _) => ConstrainToWorkArea();
        Render();
    }

    private void ConstrainToWorkArea()
    {
        var scale = _settings.VisualAppearance.InterfaceScale;
        WindowSizing.ConstrainToCurrentWorkArea(
            this,
            400 * scale,
            360 * scale);
    }

    private void Render()
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.BeginInvoke(Render);
            return;
        }

        WindowAppearanceService.Apply(
            this,
            AppearanceRoot,
            _settings.VisualAppearance,
            AppearanceWindowKind.Onboarding);
        ConstrainToWorkArea();

        _isRendering = true;
        try
        {
            DisclosureStep.Visibility = _step == 0
                ? Visibility.Visible
                : Visibility.Collapsed;
            AccountsStep.Visibility = _step == 1
                ? Visibility.Visible
                : Visibility.Collapsed;
            DoneStep.Visibility = _step == 2
                ? Visibility.Visible
                : Visibility.Collapsed;
            BackButton.Visibility = _step > 0
                ? Visibility.Visible
                : Visibility.Collapsed;
            ContinueButton.Content = _step == 2 ? "Finish" : "Continue";
            UpdateStepDots();

            OnboardingPrimaryCombo.SelectedValue = _settings.Appearance.PrimaryAgent;
            RenderAccounts();
            ConnectedSummary.Text = _coordinator.ConnectedCount switch
            {
                0 => "No agents connected yet",
                var count => $"{count} of {AgentRegistry.All.Count} agents connected",
            };
            PrimarySummary.Text =
                $"Primary: {AgentRegistry.Get(_settings.Appearance.PrimaryAgent).DisplayName}";
        }
        finally
        {
            _isRendering = false;
        }
    }

    private void RenderAccounts()
    {
        OnboardingAccountsPanel.Children.Clear();
        foreach (var agent in _coordinator.Agents)
        {
            var card = new Border
            {
                Margin = new Thickness(0, 0, 0, 10),
                Style = (Style)FindResource("CardBorder"),
            };
            var body = new StackPanel();
            card.Child = body;
            var row = new Grid();
            row.ColumnDefinitions.Add(new ColumnDefinition());
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var identity = new StackPanel();
            identity.Children.Add(new TextBlock
            {
                Text = agent.Definition.DisplayName,
                FontWeight = FontWeights.SemiBold,
            });
            identity.Children.Add(new TextBlock
            {
                Text = StatusText(agent),
                Margin = new Thickness(0, 2, 0, 0),
                FontSize = 11,
                Foreground = StatusBrush(agent),
            });
            row.Children.Add(identity);

            if (agent.State.Kind != AgentStateKind.SignedOut)
            {
                var check = new TextBlock
                {
                    Text = "✓",
                    FontSize = 22,
                    Foreground = FindBrush("AccentBrush"),
                    VerticalAlignment = VerticalAlignment.Center,
                };
                Grid.SetColumn(check, 1);
                row.Children.Add(check);
            }
            else
            {
                var signInBusy =
                    _busy.Contains(agent.Definition.Id) ||
                    (agent.IsSigningIn &&
                     agent.Definition.SignInStyle == SignInStyle.SelfCompleting);
                var connect = new Button
                {
                    Content = signInBusy
                        ? "Waiting…"
                        : agent.AwaitingCode
                            ? "Re-open browser"
                            : "Connect",
                    IsEnabled = !signInBusy,
                };
                connect.Click += async (_, _) =>
                    await BeginLoginAsync(agent.Definition.Id).ConfigureAwait(true);
                Grid.SetColumn(connect, 1);
                row.Children.Add(connect);
            }

            body.Children.Add(row);
            if (agent.AwaitingCode)
            {
                var codeRow = new Grid { Margin = new Thickness(0, 10, 0, 0) };
                codeRow.ColumnDefinitions.Add(new ColumnDefinition());
                codeRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                var code = new TextBox
                {
                    Text = _codes.GetValueOrDefault(agent.Definition.Id, string.Empty),
                    ToolTip = "Paste the code#state shown in the browser",
                };
                codeRow.Children.Add(code);
                var submit = new Button
                {
                    Content = "Submit",
                    Margin = new Thickness(8, 0, 0, 0),
                    IsEnabled = !_busy.Contains(agent.Definition.Id) &&
                                !string.IsNullOrWhiteSpace(code.Text),
                };
                code.TextChanged += (_, _) =>
                {
                    _codes[agent.Definition.Id] = code.Text;
                    submit.IsEnabled = !_busy.Contains(agent.Definition.Id) &&
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
                    Margin = new Thickness(0, 8, 0, 0),
                    FontSize = 11,
                    Foreground = FindBrush("DangerBrush"),
                });
            }

            OnboardingAccountsPanel.Children.Add(card);
        }
    }

    private async Task BeginLoginAsync(AgentId id)
    {
        if (!_busy.Add(id))
        {
            return;
        }

        Render();
        try
        {
            await _coordinator.BeginSignInAsync(id).ConfigureAwait(true);
        }
        finally
        {
            _busy.Remove(id);
            Render();
        }
    }

    private async Task SubmitCodeAsync(AgentId id, string code)
    {
        if (string.IsNullOrWhiteSpace(code) || !_busy.Add(id))
        {
            return;
        }

        Render();
        try
        {
            await _coordinator.CompleteSignInAsync(id, code).ConfigureAwait(true);
            if (_coordinator.GetAgent(id).State.Kind != AgentStateKind.SignedOut)
            {
                _codes.Remove(id);
            }
        }
        finally
        {
            _busy.Remove(id);
            Render();
        }
    }

    private void ContinueButton_OnClick(object sender, RoutedEventArgs eventArgs)
    {
        if (_step >= 2)
        {
            Close();
            return;
        }

        _step++;
        Render();
    }

    private void BackButton_OnClick(object sender, RoutedEventArgs eventArgs)
    {
        if (_step > 0)
        {
            _step--;
            Render();
        }
    }

    private void SkipButton_OnClick(object sender, RoutedEventArgs eventArgs) =>
        Close();

    private void OnboardingPrimaryCombo_OnSelectionChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        if (_isRendering || OnboardingPrimaryCombo.SelectedValue is not AgentId id)
        {
            return;
        }

        try
        {
            _settings.SaveAppearance(
                _settings.Appearance with { PrimaryAgent = id });
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                this,
                $"Could not save the primary account setting.\n\n{exception.Message}",
                "TokenStats",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            Render();
        }
    }

    private void Coordinator_OnChanged(object? sender, EventArgs eventArgs) =>
        Dispatcher.BeginInvoke(Render);

    private void OnboardingWindow_OnClosed(object? sender, EventArgs eventArgs)
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

    private void UpdateStepDots()
    {
        var dots = new[] { StepDot0, StepDot1, StepDot2 };
        for (var index = 0; index < dots.Length; index++)
        {
            dots[index].Width = index == _step ? 25 : 18;
            dots[index].Background = index <= _step
                ? FindBrush("AccentBrush")
                : FindBrush("BorderBrush");
        }
    }

    private string StatusText(AgentPresentation agent)
    {
        if (_busy.Contains(agent.Definition.Id) ||
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

    private Brush StatusBrush(AgentPresentation agent)
    {
        if (_busy.Contains(agent.Definition.Id) ||
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
