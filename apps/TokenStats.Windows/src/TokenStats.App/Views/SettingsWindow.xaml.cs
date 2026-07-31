using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Win32;
using TokenStats.App.Controls;
using TokenStats.App.Infrastructure;
using TokenStats.App.Services;
using TokenStats.Core;
using Forms = System.Windows.Forms;

namespace TokenStats.App.Views;

public partial class SettingsWindow : Window
{
    private static readonly ColorOption[] ColorOptions =
    [
        new(nameof(ThemeColorOverrides.WindowBackground), "Window", "WindowBackgroundBrush"),
        new(nameof(ThemeColorOverrides.CardBackground), "Cards", "CardBackgroundBrush"),
        new(nameof(ThemeColorOverrides.SubtleBackground), "Subtle surface", "SubtleBackgroundBrush"),
        new(nameof(ThemeColorOverrides.ControlBackground), "Controls", "ControlBackgroundBrush"),
        new(nameof(ThemeColorOverrides.PrimaryText), "Primary text", "PrimaryTextBrush"),
        new(nameof(ThemeColorOverrides.SecondaryText), "Secondary text", "SecondaryTextBrush"),
        new(nameof(ThemeColorOverrides.Border), "Borders", "BorderBrush"),
        new(nameof(ThemeColorOverrides.Accent), "Accent", "AccentBrush"),
        new(nameof(ThemeColorOverrides.Danger), "Danger", "DangerBrush"),
        new(nameof(ThemeColorOverrides.Warning), "Warning", "WarningBrush"),
        new(nameof(ThemeColorOverrides.TokenInput), "Input tokens", "TokenInputBrush"),
        new(nameof(ThemeColorOverrides.TokenOutput), "Output tokens", "TokenOutputBrush"),
        new(nameof(ThemeColorOverrides.TokenCacheWrite), "Cache write", "TokenCacheWriteBrush"),
        new(nameof(ThemeColorOverrides.TokenCacheRead), "Cache read", "TokenCacheReadBrush"),
    ];
    private readonly UsageCoordinator _coordinator;
    private readonly AppSettingsStore _settings;
    private readonly Action _runSetupAgain;
    private readonly HashSet<AgentId> _loginBusy = [];
    private readonly Dictionary<AgentId, string> _pastedCodes = [];
    private readonly DispatcherTimer _appearanceSaveTimer = new()
    {
        Interval = TimeSpan.FromMilliseconds(180),
    };
    private VisualAppearancePreferences? _pendingVisualAppearance;
    private bool _isRendering;

    public SettingsWindow(
        UsageCoordinator coordinator,
        AppSettingsStore settings,
        Action runSetupAgain)
    {
        _coordinator = coordinator;
        _settings = settings;
        _runSetupAgain = runSetupAgain;
        _isRendering = true;
        InitializeComponent();
        WindowsThemeService.Attach(this);
        _appearanceSaveTimer.Tick += AppearanceSaveTimer_OnTick;

        PrimaryAgentCombo.ItemsSource = AgentRegistry.All;
        FontFamilyCombo.ItemsSource = BuildFontChoices(_settings.VisualAppearance.FontFamily);
        VersionText.Text = $"Version {Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "—"}";
        _coordinator.Changed += Coordinator_OnChanged;
        WindowsThemeService.ThemeChanged += WindowsThemeService_OnThemeChanged;
        Closing += SettingsWindow_OnClosing;
        Closed += SettingsWindow_OnClosed;
        SourceInitialized += (_, _) => ConstrainToWorkArea();
        LocationChanged += (_, _) => ConstrainToWorkArea();
        Render();
    }

    private VisualAppearancePreferences EditingVisualAppearance =>
        _pendingVisualAppearance ?? _settings.VisualAppearance;

    private void ConstrainToWorkArea()
    {
        var scale = EditingVisualAppearance.InterfaceScale;
        WindowSizing.ConstrainToCurrentWorkArea(this, 480 * scale, 320 * scale);
        NavigationColumn.Width = new GridLength(
            MaxWidth < 620 * scale ? 150 : 190);
    }

    private void Render()
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.BeginInvoke(Render);
            return;
        }

        var visualAppearance = EditingVisualAppearance;
        WindowAppearanceService.Apply(
            this,
            AppearanceRoot,
            visualAppearance,
            AppearanceWindowKind.Settings);
        ConstrainToWorkArea();

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
            RenderVisualAppearance(visualAppearance);
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
            DisplayPage is null ||
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
        DisplayPage.Visibility = selected == "display"
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

    private void RenderVisualAppearance(VisualAppearancePreferences appearance)
    {
        SelectTaggedItem(ThemeModeCombo, appearance.ThemeMode.ToString());
        FontFamilyCombo.SelectedValue = appearance.FontFamily;
        BackgroundImagePathText.Text = appearance.BackgroundImagePath ??
                                       "No image selected";
        ClearBackgroundImageButton.IsEnabled =
            !string.IsNullOrWhiteSpace(appearance.BackgroundImagePath);
        SelectTaggedItem(
            BackgroundPlacementCombo,
            appearance.BackgroundImagePlacement.ToString());
        SelectTaggedItem(
            BackgroundPositionCombo,
            appearance.BackgroundImagePosition.ToString());
        BackgroundImageOpacitySlider.Value =
            appearance.BackgroundImageOpacity * 100;
        FlyoutOpacitySlider.Value = appearance.FlyoutOpacity * 100;
        FlyoutWidthSlider.Value = appearance.FlyoutWidth;
        InterfaceScaleSlider.Value = appearance.InterfaceScale * 100;
        BackgroundImageOpacityValue.Text =
            PercentText(appearance.BackgroundImageOpacity);
        FlyoutOpacityValue.Text = PercentText(appearance.FlyoutOpacity);
        FlyoutWidthValue.Text = $"{appearance.FlyoutWidth:0} px";
        InterfaceScaleValue.Text = PercentText(appearance.InterfaceScale);
        RenderColorOptions(appearance.Colors);
    }

    private void RenderColorOptions(ThemeColorOverrides colors)
    {
        ColorOverridesPanel.Children.Clear();
        foreach (var option in ColorOptions)
        {
            var row = new Grid { Margin = new Thickness(0, 0, 8, 8) };
            row.ColumnDefinitions.Add(new ColumnDefinition());
            row.ColumnDefinitions.Add(
                new ColumnDefinition { Width = GridLength.Auto });

            var choose = new Button
            {
                Padding = new Thickness(9, 6, 7, 6),
                HorizontalContentAlignment = HorizontalAlignment.Stretch,
                ToolTip = $"Choose the {option.Label.ToLowerInvariant()} color",
            };
            var content = new Grid();
            content.ColumnDefinitions.Add(
                new ColumnDefinition { Width = GridLength.Auto });
            content.ColumnDefinitions.Add(new ColumnDefinition());
            content.ColumnDefinitions.Add(
                new ColumnDefinition { Width = GridLength.Auto });
            content.Children.Add(new Border
            {
                Width = 18,
                Height = 18,
                Margin = new Thickness(0, 0, 8, 0),
                VerticalAlignment = VerticalAlignment.Center,
                Background = FindBrush(option.ResourceKey),
                BorderBrush = FindBrush("BorderBrush"),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(4),
            });
            var label = new TextBlock
            {
                Text = option.Label,
                VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(label, 1);
            content.Children.Add(label);
            var resolvedValue = new TextBlock
            {
                Text = BrushHex(option.ResourceKey),
                Margin = new Thickness(8, 0, 0, 0),
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = FindBrush("SecondaryTextBrush"),
                FontSize = 11,
            };
            Grid.SetColumn(resolvedValue, 2);
            content.Children.Add(resolvedValue);
            choose.Content = content;
            choose.Click += (_, _) => ChooseColor(option);
            row.Children.Add(choose);

            var reset = new Button
            {
                Content = "↺",
                Width = 30,
                MinHeight = 30,
                Margin = new Thickness(5, 0, 0, 0),
                Padding = new Thickness(0),
                ToolTip = $"Use the theme default for {option.Label.ToLowerInvariant()}",
                IsEnabled = GetColorOverride(colors, option.Key) is not null,
            };
            reset.Click += (_, _) => ResetColor(option);
            Grid.SetColumn(reset, 1);
            row.Children.Add(reset);
            ColorOverridesPanel.Children.Add(row);
        }
    }

    private void ThemeModeCombo_OnSelectionChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        if (_isRendering ||
            ThemeModeCombo.SelectedItem is not ComboBoxItem { Tag: string value } ||
            !Enum.TryParse<AppThemeMode>(value, out var mode))
        {
            return;
        }

        TrySaveVisualAppearance(
            EditingVisualAppearance with { ThemeMode = mode });
    }

    private void FontFamilyCombo_OnSelectionChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        if (_isRendering || FontFamilyCombo.SelectedValue is not string value)
        {
            return;
        }

        TrySaveVisualAppearance(
            EditingVisualAppearance with { FontFamily = value });
    }

    private void BackgroundPlacementCombo_OnSelectionChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        if (_isRendering ||
            BackgroundPlacementCombo.SelectedItem is not ComboBoxItem
            {
                Tag: string value,
            } ||
            !Enum.TryParse<BackgroundImagePlacement>(value, out var placement))
        {
            return;
        }

        TrySaveVisualAppearance(
            EditingVisualAppearance with
            {
                BackgroundImagePlacement = placement,
            });
    }

    private void BackgroundPositionCombo_OnSelectionChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        if (_isRendering ||
            BackgroundPositionCombo.SelectedItem is not ComboBoxItem
            {
                Tag: string value,
            } ||
            !Enum.TryParse<BackgroundImagePosition>(value, out var position))
        {
            return;
        }

        TrySaveVisualAppearance(
            EditingVisualAppearance with
            {
                BackgroundImagePosition = position,
            });
    }

    private void ChooseBackgroundImage_OnClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        var dialog = new OpenFileDialog
        {
            Title = "Choose a TokenStats background image",
            Filter = "Image files|*.png;*.jpg;*.jpeg;*.bmp;*.gif|All files|*.*",
            CheckFileExists = true,
            Multiselect = false,
        };
        if (dialog.ShowDialog(this) == true)
        {
            TrySaveVisualAppearance(
                EditingVisualAppearance with
                {
                    BackgroundImagePath = dialog.FileName,
                });
        }
    }

    private void ClearBackgroundImage_OnClick(
        object sender,
        RoutedEventArgs eventArgs) =>
        TrySaveVisualAppearance(
            EditingVisualAppearance with { BackgroundImagePath = null });

    private void BackgroundImageOpacity_OnValueChanged(
        object sender,
        RoutedPropertyChangedEventArgs<double> eventArgs)
    {
        if (_isRendering)
        {
            return;
        }

        var opacity = eventArgs.NewValue / 100;
        BackgroundImageOpacityValue.Text = PercentText(opacity);
        SaveSliderVisualAppearance(
            sender,
            EditingVisualAppearance with
            {
                BackgroundImageOpacity = opacity,
            });
    }

    private void FlyoutOpacity_OnValueChanged(
        object sender,
        RoutedPropertyChangedEventArgs<double> eventArgs)
    {
        if (_isRendering)
        {
            return;
        }

        var opacity = eventArgs.NewValue / 100;
        FlyoutOpacityValue.Text = PercentText(opacity);
        SaveSliderVisualAppearance(
            sender,
            EditingVisualAppearance with
            {
                FlyoutOpacity = opacity,
            });
    }

    private void FlyoutWidth_OnValueChanged(
        object sender,
        RoutedPropertyChangedEventArgs<double> eventArgs)
    {
        if (_isRendering)
        {
            return;
        }

        FlyoutWidthValue.Text = $"{eventArgs.NewValue:0} px";
        SaveSliderVisualAppearance(
            sender,
            EditingVisualAppearance with { FlyoutWidth = eventArgs.NewValue });
    }

    private void InterfaceScale_OnValueChanged(
        object sender,
        RoutedPropertyChangedEventArgs<double> eventArgs)
    {
        if (_isRendering)
        {
            return;
        }

        var scale = eventArgs.NewValue / 100;
        InterfaceScaleValue.Text = PercentText(scale);
        SaveSliderVisualAppearance(
            sender,
            EditingVisualAppearance with
            {
                InterfaceScale = scale,
            });
    }

    private void ResetColors_OnClick(object sender, RoutedEventArgs eventArgs) =>
        TrySaveVisualAppearance(
            EditingVisualAppearance with { Colors = ThemeColorOverrides.Empty });

    private void ResetAppearance_OnClick(
        object sender,
        RoutedEventArgs eventArgs) =>
        TrySaveVisualAppearance(VisualAppearancePreferences.Default);

    private void ChooseColor(ColorOption option)
    {
        var brush = FindBrush(option.ResourceKey) as SolidColorBrush;
        var initial = brush?.Color ?? Colors.Gray;
        using var dialog = new Forms.ColorDialog
        {
            FullOpen = true,
            AnyColor = true,
            Color = System.Drawing.Color.FromArgb(
                initial.R,
                initial.G,
                initial.B),
        };
        if (dialog.ShowDialog() != Forms.DialogResult.OK)
        {
            return;
        }

        var color = dialog.Color;
        var value = $"#FF{color.R:X2}{color.G:X2}{color.B:X2}";
        TrySaveVisualAppearance(
            EditingVisualAppearance with
            {
                Colors = SetColorOverride(
                    EditingVisualAppearance.Colors,
                    option.Key,
                    value),
            });
    }

    private void ResetColor(ColorOption option) =>
        TrySaveVisualAppearance(
            EditingVisualAppearance with
            {
                Colors = SetColorOverride(
                    EditingVisualAppearance.Colors,
                    option.Key,
                    null),
            });

    private void SaveSliderVisualAppearance(
        object sender,
        VisualAppearancePreferences appearance)
    {
        if (sender is Slider { IsMouseCaptureWithin: true })
        {
            _pendingVisualAppearance = appearance;
            _appearanceSaveTimer.Stop();
            _appearanceSaveTimer.Start();
            return;
        }

        TrySaveVisualAppearance(appearance);
    }

    private void AppearanceSaveTimer_OnTick(
        object? sender,
        EventArgs eventArgs) =>
        CommitPendingVisualAppearance();

    private void CommitPendingVisualAppearance()
    {
        if (_pendingVisualAppearance is not { } pending)
        {
            _appearanceSaveTimer.Stop();
            return;
        }

        _pendingVisualAppearance = null;
        _appearanceSaveTimer.Stop();
        TrySaveVisualAppearance(pending);
    }

    private bool TrySaveVisualAppearance(VisualAppearancePreferences appearance)
    {
        _appearanceSaveTimer.Stop();
        _pendingVisualAppearance = null;
        try
        {
            _settings.SaveVisualAppearance(appearance);
            var saved = _settings.VisualAppearance;
            if (WindowsThemeService.CurrentAppearance != saved &&
                System.Windows.Application.Current is { } application)
            {
                WindowsThemeService.ApplyAppearance(
                    application.Resources,
                    saved);
            }

            return true;
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                this,
                $"Could not save TokenStats appearance settings.\n\n{exception.Message}",
                "TokenStats",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            Render();
            return false;
        }
    }

    private static void SelectTaggedItem(ComboBox comboBox, string value)
    {
        foreach (var item in comboBox.Items.OfType<ComboBoxItem>())
        {
            if (string.Equals(item.Tag as string, value, StringComparison.Ordinal))
            {
                comboBox.SelectedItem = item;
                return;
            }
        }
    }

    private static IReadOnlyList<FontChoice> BuildFontChoices(string current)
    {
        var choices = new List<FontChoice>
        {
            new("System default", VisualAppearancePreferences.DefaultFontFamily),
        };
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            VisualAppearancePreferences.DefaultFontFamily,
        };
        if (!string.IsNullOrWhiteSpace(current) && seen.Add(current))
        {
            choices.Add(new FontChoice(current, current));
        }

        choices.AddRange(
            Fonts.SystemFontFamilies
                .Select(font => font.Source)
                .Where(seen.Add)
                .OrderBy(name => name, StringComparer.CurrentCultureIgnoreCase)
                .Select(name => new FontChoice(name, name)));
        return choices;
    }

    private static string? GetColorOverride(
        ThemeColorOverrides colors,
        string key) =>
        key switch
        {
            nameof(ThemeColorOverrides.WindowBackground) => colors.WindowBackground,
            nameof(ThemeColorOverrides.CardBackground) => colors.CardBackground,
            nameof(ThemeColorOverrides.SubtleBackground) => colors.SubtleBackground,
            nameof(ThemeColorOverrides.ControlBackground) => colors.ControlBackground,
            nameof(ThemeColorOverrides.PrimaryText) => colors.PrimaryText,
            nameof(ThemeColorOverrides.SecondaryText) => colors.SecondaryText,
            nameof(ThemeColorOverrides.Border) => colors.Border,
            nameof(ThemeColorOverrides.Accent) => colors.Accent,
            nameof(ThemeColorOverrides.Danger) => colors.Danger,
            nameof(ThemeColorOverrides.Warning) => colors.Warning,
            nameof(ThemeColorOverrides.TokenInput) => colors.TokenInput,
            nameof(ThemeColorOverrides.TokenOutput) => colors.TokenOutput,
            nameof(ThemeColorOverrides.TokenCacheWrite) => colors.TokenCacheWrite,
            nameof(ThemeColorOverrides.TokenCacheRead) => colors.TokenCacheRead,
            _ => null,
        };

    private static ThemeColorOverrides SetColorOverride(
        ThemeColorOverrides colors,
        string key,
        string? value) =>
        key switch
        {
            nameof(ThemeColorOverrides.WindowBackground) =>
                colors with { WindowBackground = value },
            nameof(ThemeColorOverrides.CardBackground) =>
                colors with { CardBackground = value },
            nameof(ThemeColorOverrides.SubtleBackground) =>
                colors with { SubtleBackground = value },
            nameof(ThemeColorOverrides.ControlBackground) =>
                colors with { ControlBackground = value },
            nameof(ThemeColorOverrides.PrimaryText) =>
                colors with { PrimaryText = value },
            nameof(ThemeColorOverrides.SecondaryText) =>
                colors with { SecondaryText = value },
            nameof(ThemeColorOverrides.Border) => colors with { Border = value },
            nameof(ThemeColorOverrides.Accent) => colors with { Accent = value },
            nameof(ThemeColorOverrides.Danger) => colors with { Danger = value },
            nameof(ThemeColorOverrides.Warning) => colors with { Warning = value },
            nameof(ThemeColorOverrides.TokenInput) =>
                colors with { TokenInput = value },
            nameof(ThemeColorOverrides.TokenOutput) =>
                colors with { TokenOutput = value },
            nameof(ThemeColorOverrides.TokenCacheWrite) =>
                colors with { TokenCacheWrite = value },
            nameof(ThemeColorOverrides.TokenCacheRead) =>
                colors with { TokenCacheRead = value },
            _ => colors,
        };

    private static string BrushHex(string resourceKey) =>
        FindBrush(resourceKey) is SolidColorBrush brush
            ? $"#{brush.Color.R:X2}{brush.Color.G:X2}{brush.Color.B:X2}"
            : "—";

    private static string PercentText(double value) => $"{value * 100:0}%";

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

    private void SettingsWindow_OnClosing(
        object? sender,
        System.ComponentModel.CancelEventArgs eventArgs) =>
        CommitPendingVisualAppearance();

    private void SettingsWindow_OnClosed(object? sender, EventArgs eventArgs)
    {
        _appearanceSaveTimer.Stop();
        _appearanceSaveTimer.Tick -= AppearanceSaveTimer_OnTick;
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

    private sealed record ColorOption(
        string Key,
        string Label,
        string ResourceKey);

    private sealed record FontChoice(string Label, string Value);

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
