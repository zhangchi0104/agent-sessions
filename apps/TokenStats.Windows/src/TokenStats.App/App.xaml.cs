using System.Net.Http;
using System.Windows;
using Microsoft.Win32;
using TokenStats.App.Infrastructure;
using TokenStats.App.Services;
using TokenStats.App.Views;
using TokenStats.Core;

namespace TokenStats.App;

public partial class App : System.Windows.Application
{
    private SingleInstanceService? _singleInstance;
    private HttpClient? _httpClient;
    private AppSettingsStore? _settings;
    private UsageCoordinator? _coordinator;
    private TokenOdometerWatcher? _tokenOdometer;
    private FlyoutWindow? _flyout;
    private SettingsWindow? _settingsWindow;
    private OnboardingWindow? _onboardingWindow;
    private TrayIconService? _tray;
    private bool _isQuitting;

    protected override async void OnStartup(StartupEventArgs eventArgs)
    {
        base.OnStartup(eventArgs);
        _singleInstance = new SingleInstanceService();
        if (!_singleInstance.IsPrimary)
        {
            await SingleInstanceService.SignalPrimaryAsync().ConfigureAwait(true);
            _singleInstance.Dispose();
            Shutdown();
            return;
        }

        ApplySystemTheme();
        SystemEvents.UserPreferenceChanged += SystemEvents_OnUserPreferenceChanged;
        SystemEvents.PowerModeChanged += SystemEvents_OnPowerModeChanged;

        _settings = new AppSettingsStore();
        _httpClient = new HttpClient();
        var oauthClient = new OAuthHttpClient(_httpClient);
        var claudeAuth = new ClaudeAuthSession(
            new CredentialTokenStore("claude"),
            oauthClient);
        var codexAuth = new CodexAuthSession(
            new CredentialTokenStore("codex"),
            oauthClient);
        var auth = new Dictionary<AgentId, IAgentAuthSession>
        {
            [AgentId.ClaudeCode] = claudeAuth,
            [AgentId.Codex] = codexAuth,
        };
        var providers = new Dictionary<AgentId, IUsageProvider>
        {
            [AgentId.ClaudeCode] = new ClaudeUsageProvider(
                _httpClient,
                claudeAuth.ValidAccessTokenAsync),
            [AgentId.Codex] = new CodexUsageProvider(
                _httpClient,
                codexAuth.ValidAccessTokenAsync,
                () => codexAuth.AccountId),
        };

        _coordinator = new UsageCoordinator(_settings, auth, providers);
        _tokenOdometer = new TokenOdometerWatcher(
            new TranscriptTokenReader(
                cacheDirectory: Path.Combine(
                    Environment.GetFolderPath(
                        Environment.SpecialFolder.LocalApplicationData),
                    "TokenStats",
                    "Cache",
                    "token-reader-v1")),
            initialRange: _settings.Appearance.SelectedTokenRange);
        _flyout = new FlyoutWindow(
            _coordinator,
            _settings,
            _tokenOdometer,
            ShowSettings,
            Quit);
        _tray = new TrayIconService(
            ToggleFlyout,
            RefreshAllAsync,
            ShowSettings,
            Quit);
        _coordinator.Changed += Coordinator_OnChanged;
        _tokenOdometer.Changed += TokenOdometer_OnChanged;

        _singleInstance.ActivationRequested += (_, _) =>
            Dispatcher.BeginInvoke(ActivatePrimaryInstance);
        _singleInstance.StartListening();

        _ = _coordinator.StartAsync();
        _ = _tokenOdometer.SetVisibleAsync(true);
        UpdateTray();

        var startsInBackground = eventArgs.Args.Any(
            argument => string.Equals(
                argument,
                "--background",
                StringComparison.OrdinalIgnoreCase));
        if (!_settings.OnboardingCompleted && !startsInBackground)
        {
            ShowOnboarding();
        }
    }

    protected override void OnExit(ExitEventArgs eventArgs)
    {
        SystemEvents.UserPreferenceChanged -= SystemEvents_OnUserPreferenceChanged;
        SystemEvents.PowerModeChanged -= SystemEvents_OnPowerModeChanged;
        _tray?.Dispose();
        _httpClient?.Dispose();
        _singleInstance?.Dispose();
        base.OnExit(eventArgs);
    }

    private void ToggleFlyout()
    {
        if (_flyout is null)
        {
            return;
        }

        if (_flyout.IsVisible)
        {
            _flyout.HideFlyout();
        }
        else
        {
            _flyout.ShowFlyout();
        }
    }

    private Task RefreshAllAsync() =>
        RefreshAllAsync(RefreshTrigger.Manual);

    private Task RefreshAllAsync(RefreshTrigger trigger)
    {
        if (_coordinator is null || _tokenOdometer is null)
        {
            return Task.CompletedTask;
        }

        return Task.WhenAll(
            _coordinator.RefreshAllAsync(trigger),
            _tokenOdometer.RefreshAsync());
    }

    private void ActivatePrimaryInstance()
    {
        if (_isQuitting || _flyout is null)
        {
            return;
        }

        if (!_flyout.IsVisible)
        {
            _flyout.ShowFlyout();
            return;
        }

        _flyout.Activate();
        _flyout.Focus();
    }

    private void ShowSettings()
    {
        if (_coordinator is null || _settings is null)
        {
            return;
        }

        if (_settingsWindow is null)
        {
            _settingsWindow = new SettingsWindow(
                _coordinator,
                _settings,
                ShowOnboarding);
            _settingsWindow.Closed += (_, _) => _settingsWindow = null;
        }

        _settingsWindow.Show();
        if (_settingsWindow.WindowState == WindowState.Minimized)
        {
            _settingsWindow.WindowState = WindowState.Normal;
        }

        _settingsWindow.Activate();
    }

    private void ShowOnboarding()
    {
        if (_coordinator is null || _settings is null)
        {
            return;
        }

        if (_onboardingWindow is null)
        {
            _onboardingWindow = new OnboardingWindow(_coordinator, _settings);
            _onboardingWindow.Closed += (_, _) =>
            {
                try
                {
                    _settings.SetOnboardingCompleted(true);
                }
                catch (Exception exception)
                {
                    if (!_isQuitting)
                    {
                        MessageBox.Show(
                            $"Setup completed, but TokenStats could not save that state.\n\n{exception.Message}",
                            "TokenStats",
                            MessageBoxButton.OK,
                            MessageBoxImage.Warning);
                    }
                }

                _onboardingWindow = null;
            };
        }

        _onboardingWindow.Show();
        _onboardingWindow.Activate();
    }

    private async void Quit()
    {
        if (_isQuitting)
        {
            return;
        }

        _isQuitting = true;
        _tray?.Dispose();
        _tray = null;
        _flyout?.AllowClose();
        _flyout?.Close();
        _settingsWindow?.Close();
        _onboardingWindow?.Close();
        if (_tokenOdometer is not null)
        {
            _tokenOdometer.Changed -= TokenOdometer_OnChanged;
            await _tokenOdometer.DisposeAsync().ConfigureAwait(true);
        }

        if (_coordinator is not null)
        {
            _coordinator.Changed -= Coordinator_OnChanged;
            await _coordinator.DisposeAsync().ConfigureAwait(true);
        }

        Shutdown();
    }

    private void Coordinator_OnChanged(object? sender, EventArgs eventArgs) =>
        Dispatcher.BeginInvoke(UpdateTray);

    private void TokenOdometer_OnChanged(object? sender, EventArgs eventArgs) =>
        Dispatcher.BeginInvoke(UpdateTray);

    private void UpdateTray()
    {
        if (_coordinator is null)
        {
            return;
        }

        var summaries = new List<string> { _coordinator.TraySummary };
        if (_tokenOdometer is
            {
                HasLoaded: true,
                Usage: { } tokenUsage,
            })
        {
            var preferences = _coordinator.Appearance;
            summaries.Add(
                UsageFormatting.TokenStatusSummary(
                    tokenUsage,
                    _tokenOdometer.DisplayedRange,
                    preferences.TodayMetric));
        }

        _tray?.UpdateSummary(string.Join(" · ", summaries));
    }

    private void SystemEvents_OnPowerModeChanged(
        object sender,
        PowerModeChangedEventArgs eventArgs)
    {
        if (eventArgs.Mode == PowerModes.Resume)
        {
            _ = RefreshAllAsync(RefreshTrigger.Wake);
        }
    }

    private void SystemEvents_OnUserPreferenceChanged(
        object sender,
        UserPreferenceChangedEventArgs eventArgs)
    {
        if (eventArgs.Category is UserPreferenceCategory.General or
            UserPreferenceCategory.Accessibility or
            UserPreferenceCategory.Color or
            UserPreferenceCategory.VisualStyle)
        {
            Dispatcher.BeginInvoke(ApplySystemTheme);
        }
    }

    private void ApplySystemTheme() =>
        WindowsThemeService.ApplySystemTheme(Resources);
}
