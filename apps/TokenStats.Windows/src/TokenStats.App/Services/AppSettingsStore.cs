using System.Collections.ObjectModel;
using System.Text.Json;
using System.Text.Json.Serialization;
using TokenStats.Core;

namespace TokenStats.App.Services;

/// <summary>
/// User-controlled presentation preferences. <see cref="Order"/> stores every
/// known agent; <see cref="DisplayOrder"/> always places the primary agent first.
/// </summary>
public sealed record AppearancePreferences(
    AgentId PrimaryAgent,
    IReadOnlyList<AgentId> Order,
    GaugeStyle GaugeStyle,
    TodayMetricMode TodayMetric = TodayMetricMode.Token,
    TokenKindSelection SelectedTokenKinds = TokenKindSelection.All,
    TokenValueDisplayMode TokenValueDisplay = TokenValueDisplayMode.Value,
    TokenRange SelectedTokenRange = TokenRange.Today,
    bool AlwaysOnTop = false)
{
    public static AppearancePreferences Default { get; } = new(
        AgentId.ClaudeCode,
        AgentRegistry.All.Select(agent => agent.Id).ToArray(),
        GaugeStyle.Dial,
        TodayMetricMode.Token,
        TokenKindSelection.All,
        TokenValueDisplayMode.Value,
        TokenRange.Today,
        false);

    public IReadOnlyList<AgentId> DisplayOrder()
    {
        var result = new List<AgentId> { PrimaryAgent };
        result.AddRange(Order.Where(id => id != PrimaryAgent && !result.Contains(id)));
        result.AddRange(AgentRegistry.All
            .Select(agent => agent.Id)
            .Where(id => !result.Contains(id)));
        return result;
    }
}

public enum AppThemeMode
{
    System,
    Light,
    Dark,
}

public enum BackgroundImagePlacement
{
    Fill,
    Fit,
    Center,
    Tile,
}

public enum BackgroundImagePosition
{
    Center = 0,
    TopLeft = 1,
    Top = 2,
    TopRight = 3,
    Left = 4,
    Right = 5,
    BottomLeft = 6,
    Bottom = 7,
    BottomRight = 8,
}

/// <summary>
/// Optional overrides layered over the selected light or dark palette. Null
/// values continue to use the built-in palette so changing theme mode remains
/// useful after individual colors have been customized.
/// </summary>
public sealed record ThemeColorOverrides(
    string? WindowBackground = null,
    string? CardBackground = null,
    string? SubtleBackground = null,
    string? ControlBackground = null,
    string? PrimaryText = null,
    string? SecondaryText = null,
    string? Border = null,
    string? Accent = null,
    string? Danger = null,
    string? Warning = null,
    string? TokenInput = null,
    string? TokenOutput = null,
    string? TokenCacheRead = null)
{
    public static ThemeColorOverrides Empty { get; } = new();
}

/// <summary>
/// Visual customization that is independent of the data-presentation choices
/// stored in <see cref="AppearancePreferences"/>.
/// </summary>
public sealed record VisualAppearancePreferences(
    AppThemeMode ThemeMode,
    ThemeColorOverrides Colors,
    string FontFamily,
    string? BackgroundImagePath,
    BackgroundImagePlacement BackgroundImagePlacement,
    BackgroundImagePosition BackgroundImagePosition,
    double BackgroundImageOpacity,
    double FlyoutOpacity,
    double FlyoutWidth,
    double InterfaceScale)
{
    public const string DefaultFontFamily = "Segoe UI Variable Text, Segoe UI";
    public const double MinimumFlyoutWidth = 360;
    public const double MaximumFlyoutWidth = 640;
    public const double MinimumInterfaceScale = 0.8;
    public const double MaximumInterfaceScale = 1.4;
    public const double MinimumFlyoutOpacity = 0.55;

    public static VisualAppearancePreferences Default { get; } = new(
        AppThemeMode.System,
        ThemeColorOverrides.Empty,
        DefaultFontFamily,
        null,
        BackgroundImagePlacement.Fill,
        BackgroundImagePosition.Center,
        0.2,
        1,
        424,
        1);
}

public sealed record OnboardingPreferences(bool Completed)
{
    public static OnboardingPreferences Default { get; } = new(false);
}

/// <summary>
/// Versioned, non-secret application settings. OAuth credentials deliberately
/// live in the platform token store rather than this document.
/// </summary>
public sealed record AppSettings(
    int Version,
    AppearancePreferences Appearance,
    VisualAppearancePreferences VisualAppearance,
    OnboardingPreferences Onboarding,
    IReadOnlyDictionary<AgentId, UsageSnapshot> LastSnapshots)
{
    public const int CurrentVersion = 4;

    public static AppSettings Default { get; } = new(
        CurrentVersion,
        AppearancePreferences.Default,
        VisualAppearancePreferences.Default,
        OnboardingPreferences.Default,
        new ReadOnlyDictionary<AgentId, UsageSnapshot>(
            new Dictionary<AgentId, UsageSnapshot>()));
}

/// <summary>
/// Persists TokenStats' non-secret settings to
/// %LocalAppData%\TokenStats\settings.json.
///
/// Writes use a same-directory temporary file followed by an atomic replace.
/// DateTimeOffset values are serialized by System.Text.Json in ISO-8601 round
/// trip form.
/// </summary>
public sealed class AppSettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = CreateJsonOptions();

    private readonly object _gate = new();
    private AppSettings _current;

    public AppSettingsStore(string? settingsPath = null)
    {
        SettingsPath = settingsPath ?? DefaultSettingsPath();
        _current = LoadCore();
    }

    public event EventHandler? Changed;

    public string SettingsPath { get; }

    /// <summary>
    /// The most recent deserialization or read error. Corrupt/unreadable settings
    /// fall back to defaults so the tray process can still start.
    /// </summary>
    public Exception? LastLoadError { get; private set; }

    public AppSettings Current
    {
        get
        {
            lock (_gate)
            {
                return Clone(_current);
            }
        }
    }

    public AppearancePreferences Appearance => Current.Appearance;

    public VisualAppearancePreferences VisualAppearance =>
        Current.VisualAppearance;

    public bool OnboardingCompleted => Current.Onboarding.Completed;

    public AppSettings Reload()
    {
        AppSettings loaded;
        lock (_gate)
        {
            loaded = LoadCore();
            _current = loaded;
        }

        OnChanged();
        return Clone(loaded);
    }

    public void Save(AppSettings settings)
    {
        var normalized = Normalize(settings);
        lock (_gate)
        {
            SaveCore(normalized);
            _current = normalized;
        }

        OnChanged();
    }

    public void SaveVisualAppearance(VisualAppearancePreferences appearance)
    {
        ArgumentNullException.ThrowIfNull(appearance);
        Mutate(settings => settings with
        {
            VisualAppearance = NormalizeVisualAppearance(appearance),
        });
    }

    public void SaveAppearance(AppearancePreferences appearance)
    {
        Mutate(settings => settings with
        {
            Appearance = NormalizeAppearance(appearance),
        });
    }

    public void SetOnboardingCompleted(bool completed)
    {
        Mutate(settings => settings with
        {
            Onboarding = new OnboardingPreferences(completed),
        });
    }

    public UsageSnapshot? LoadLastSnapshot(AgentId agentId)
    {
        lock (_gate)
        {
            return _current.LastSnapshots.TryGetValue(agentId, out var snapshot)
                ? Clone(snapshot)
                : null;
        }
    }

    public void SaveLastSnapshot(AgentId agentId, UsageSnapshot snapshot)
    {
        Mutate(settings =>
        {
            var snapshots = settings.LastSnapshots.ToDictionary();
            snapshots[agentId] = Clone(snapshot);
            return settings with
            {
                LastSnapshots = AsReadOnly(snapshots),
            };
        });
    }

    public void ClearLastSnapshot(AgentId agentId)
    {
        Mutate(settings =>
        {
            if (!settings.LastSnapshots.ContainsKey(agentId))
            {
                return settings;
            }

            var snapshots = settings.LastSnapshots.ToDictionary();
            snapshots.Remove(agentId);
            return settings with
            {
                LastSnapshots = AsReadOnly(snapshots),
            };
        });
    }

    private static string DefaultSettingsPath()
    {
        var localAppData = Environment.GetFolderPath(
            Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrWhiteSpace(localAppData))
        {
            throw new InvalidOperationException(
                "Windows did not provide a LocalApplicationData directory.");
        }

        return Path.Combine(localAppData, "TokenStats", "settings.json");
    }

    private void Mutate(Func<AppSettings, AppSettings> mutation)
    {
        var changed = false;
        lock (_gate)
        {
            var next = Normalize(mutation(Clone(_current)));
            if (next == _current)
            {
                return;
            }

            SaveCore(next);
            _current = next;
            changed = true;
        }

        if (changed)
        {
            OnChanged();
        }
    }

    private AppSettings LoadCore()
    {
        LastLoadError = null;
        if (!File.Exists(SettingsPath))
        {
            return Clone(AppSettings.Default);
        }

        try
        {
            using var stream = new FileStream(
                SettingsPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read);
            var settings = JsonSerializer.Deserialize<AppSettings>(stream, JsonOptions);
            return settings is null
                ? Clone(AppSettings.Default)
                : Normalize(settings);
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or JsonException)
        {
            LastLoadError = exception;
            return Clone(AppSettings.Default);
        }
    }

    private void SaveCore(AppSettings settings)
    {
        var directory = Path.GetDirectoryName(SettingsPath);
        if (string.IsNullOrWhiteSpace(directory))
        {
            throw new InvalidOperationException(
                $"Settings path has no parent directory: {SettingsPath}");
        }

        Directory.CreateDirectory(directory);
        var temporaryPath = Path.Combine(
            directory,
            $".{Path.GetFileName(SettingsPath)}.{Environment.ProcessId}.{Guid.NewGuid():N}.tmp");
        var payload = JsonSerializer.SerializeToUtf8Bytes(settings, JsonOptions);

        try
        {
            using (var stream = new FileStream(
                       temporaryPath,
                       FileMode.CreateNew,
                       FileAccess.Write,
                       FileShare.None,
                       bufferSize: 16 * 1024,
                       options: FileOptions.WriteThrough))
            {
                stream.Write(payload);
                stream.Flush(flushToDisk: true);
            }

            if (File.Exists(SettingsPath))
            {
                try
                {
                    File.Replace(temporaryPath, SettingsPath, null);
                }
                catch (PlatformNotSupportedException)
                {
                    File.Move(temporaryPath, SettingsPath, overwrite: true);
                }
            }
            else
            {
                File.Move(temporaryPath, SettingsPath);
            }
        }
        finally
        {
            if (File.Exists(temporaryPath))
            {
                File.Delete(temporaryPath);
            }
        }
    }

    private static AppSettings Normalize(AppSettings settings)
    {
        var knownAgents = AgentRegistry.All.Select(agent => agent.Id).ToHashSet();
        var snapshots = new Dictionary<AgentId, UsageSnapshot>();
        foreach (var pair in settings.LastSnapshots ??
                     new Dictionary<AgentId, UsageSnapshot>())
        {
            if (knownAgents.Contains(pair.Key) &&
                TryNormalizeSnapshot(pair.Value, out var snapshot))
            {
                snapshots[pair.Key] = snapshot;
            }
        }

        return new AppSettings(
            AppSettings.CurrentVersion,
            NormalizeAppearance(settings.Appearance ?? AppearancePreferences.Default),
            NormalizeVisualAppearance(
                settings.VisualAppearance ?? VisualAppearancePreferences.Default),
            settings.Onboarding ?? OnboardingPreferences.Default,
            AsReadOnly(snapshots));
    }

    private static bool TryNormalizeSnapshot(
        UsageSnapshot? snapshot,
        out UsageSnapshot normalized)
    {
        normalized = null!;
        if (snapshot?.Windows is null)
        {
            return false;
        }

        var windows = snapshot.Windows
            .Where(window =>
                window is not null &&
                !string.IsNullOrWhiteSpace(window.Label) &&
                double.IsFinite(window.PercentConsumed))
            .Select(window => new UsageWindow(
                window.Label,
                window.PercentConsumed,
                window.ResetAt,
                Enum.IsDefined(window.Kind)
                    ? window.Kind
                    : UsageWindowKind.Unknown,
                window.DurationSeconds is > 0
                    ? window.DurationSeconds
                    : null))
            .ToArray();

        normalized = new UsageSnapshot(windows, snapshot.FetchedAt);
        return true;
    }

    private static AppearancePreferences NormalizeAppearance(
        AppearancePreferences appearance)
    {
        var knownAgents = AgentRegistry.All.Select(agent => agent.Id).ToArray();
        var primary = knownAgents.Contains(appearance.PrimaryAgent)
            ? appearance.PrimaryAgent
            : AppearancePreferences.Default.PrimaryAgent;
        var order = (appearance.Order ?? Array.Empty<AgentId>())
            .Where(knownAgents.Contains)
            .Distinct()
            .ToList();
        order.AddRange(knownAgents.Where(id => !order.Contains(id)));

        var gaugeStyle = Enum.IsDefined(appearance.GaugeStyle)
            ? appearance.GaugeStyle
            : AppearancePreferences.Default.GaugeStyle;
        var todayMetric = Enum.IsDefined(appearance.TodayMetric)
            ? appearance.TodayMetric
            : AppearancePreferences.Default.TodayMetric;
        var selectedTokenKinds =
            appearance.SelectedTokenKinds.IsValid(allowNone: false)
                ? appearance.SelectedTokenKinds
                : AppearancePreferences.Default.SelectedTokenKinds;
        var tokenValueDisplay = Enum.IsDefined(appearance.TokenValueDisplay)
            ? appearance.TokenValueDisplay
            : AppearancePreferences.Default.TokenValueDisplay;
        var selectedTokenRange = Enum.IsDefined(appearance.SelectedTokenRange)
            ? appearance.SelectedTokenRange
            : AppearancePreferences.Default.SelectedTokenRange;
        return new AppearancePreferences(
            primary,
            order,
            gaugeStyle,
            todayMetric,
            selectedTokenKinds,
            tokenValueDisplay,
            selectedTokenRange,
            appearance.AlwaysOnTop);
    }

    private static VisualAppearancePreferences NormalizeVisualAppearance(
        VisualAppearancePreferences appearance)
    {
        var themeMode = Enum.IsDefined(appearance.ThemeMode)
            ? appearance.ThemeMode
            : VisualAppearancePreferences.Default.ThemeMode;
        var placement = Enum.IsDefined(appearance.BackgroundImagePlacement)
            ? appearance.BackgroundImagePlacement
            : VisualAppearancePreferences.Default.BackgroundImagePlacement;
        var position = Enum.IsDefined(appearance.BackgroundImagePosition)
            ? appearance.BackgroundImagePosition
            : VisualAppearancePreferences.Default.BackgroundImagePosition;
        var colors = appearance.Colors ?? ThemeColorOverrides.Empty;
        var fontFamily = string.IsNullOrWhiteSpace(appearance.FontFamily)
            ? VisualAppearancePreferences.Default.FontFamily
            : appearance.FontFamily.Trim();
        var imagePath = string.IsNullOrWhiteSpace(appearance.BackgroundImagePath)
            ? null
            : appearance.BackgroundImagePath.Trim();

        return new VisualAppearancePreferences(
            themeMode,
            new ThemeColorOverrides(
                NormalizeColor(colors.WindowBackground),
                NormalizeColor(colors.CardBackground),
                NormalizeColor(colors.SubtleBackground),
                NormalizeColor(colors.ControlBackground),
                NormalizeColor(colors.PrimaryText),
                NormalizeColor(colors.SecondaryText),
                NormalizeColor(colors.Border),
                NormalizeColor(colors.Accent),
                NormalizeColor(colors.Danger),
                NormalizeColor(colors.Warning),
                NormalizeColor(colors.TokenInput),
                NormalizeColor(colors.TokenOutput),
                NormalizeColor(colors.TokenCacheRead)),
            fontFamily,
            imagePath,
            placement,
            position,
            NormalizeUnitInterval(
                appearance.BackgroundImageOpacity,
                VisualAppearancePreferences.Default.BackgroundImageOpacity),
            Math.Clamp(
                NormalizeFinite(
                    appearance.FlyoutOpacity,
                    VisualAppearancePreferences.Default.FlyoutOpacity),
                VisualAppearancePreferences.MinimumFlyoutOpacity,
                1),
            Math.Clamp(
                NormalizeFinite(
                    appearance.FlyoutWidth,
                    VisualAppearancePreferences.Default.FlyoutWidth),
                VisualAppearancePreferences.MinimumFlyoutWidth,
                VisualAppearancePreferences.MaximumFlyoutWidth),
            Math.Clamp(
                NormalizeFinite(
                    appearance.InterfaceScale,
                    VisualAppearancePreferences.Default.InterfaceScale),
                VisualAppearancePreferences.MinimumInterfaceScale,
                VisualAppearancePreferences.MaximumInterfaceScale));
    }

    private static double NormalizeUnitInterval(double value, double fallback) =>
        Math.Clamp(NormalizeFinite(value, fallback), 0, 1);

    private static double NormalizeFinite(double value, double fallback) =>
        double.IsFinite(value) ? value : fallback;

    private static string? NormalizeColor(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var candidate = value.Trim();
        if (candidate.StartsWith('#'))
        {
            candidate = candidate[1..];
        }

        if (candidate.Length == 6)
        {
            candidate = $"FF{candidate}";
        }

        return candidate.Length == 8 &&
               uint.TryParse(
                   candidate,
                   System.Globalization.NumberStyles.HexNumber,
                   System.Globalization.CultureInfo.InvariantCulture,
                   out _)
            ? $"#{candidate.ToUpperInvariant()}"
            : null;
    }

    private static AppSettings Clone(AppSettings settings) => new(
        settings.Version,
        new AppearancePreferences(
            settings.Appearance.PrimaryAgent,
            settings.Appearance.Order.ToArray(),
            settings.Appearance.GaugeStyle,
            settings.Appearance.TodayMetric,
            settings.Appearance.SelectedTokenKinds,
            settings.Appearance.TokenValueDisplay,
            settings.Appearance.SelectedTokenRange,
            settings.Appearance.AlwaysOnTop),
        new VisualAppearancePreferences(
            settings.VisualAppearance.ThemeMode,
            new ThemeColorOverrides(
                settings.VisualAppearance.Colors.WindowBackground,
                settings.VisualAppearance.Colors.CardBackground,
                settings.VisualAppearance.Colors.SubtleBackground,
                settings.VisualAppearance.Colors.ControlBackground,
                settings.VisualAppearance.Colors.PrimaryText,
                settings.VisualAppearance.Colors.SecondaryText,
                settings.VisualAppearance.Colors.Border,
                settings.VisualAppearance.Colors.Accent,
                settings.VisualAppearance.Colors.Danger,
                settings.VisualAppearance.Colors.Warning,
                settings.VisualAppearance.Colors.TokenInput,
                settings.VisualAppearance.Colors.TokenOutput,
                settings.VisualAppearance.Colors.TokenCacheRead),
            settings.VisualAppearance.FontFamily,
            settings.VisualAppearance.BackgroundImagePath,
            settings.VisualAppearance.BackgroundImagePlacement,
            settings.VisualAppearance.BackgroundImagePosition,
            settings.VisualAppearance.BackgroundImageOpacity,
            settings.VisualAppearance.FlyoutOpacity,
            settings.VisualAppearance.FlyoutWidth,
            settings.VisualAppearance.InterfaceScale),
        new OnboardingPreferences(settings.Onboarding.Completed),
        AsReadOnly(settings.LastSnapshots.ToDictionary(
            pair => pair.Key,
            pair => Clone(pair.Value))));

    private static UsageSnapshot Clone(UsageSnapshot snapshot) => new(
        snapshot.Windows
            .Select(window => new UsageWindow(
                window.Label,
                window.PercentConsumed,
                window.ResetAt,
                window.Kind,
                window.DurationSeconds))
            .ToArray(),
        snapshot.FetchedAt);

    private static IReadOnlyDictionary<AgentId, UsageSnapshot> AsReadOnly(
        IDictionary<AgentId, UsageSnapshot> snapshots) =>
        new ReadOnlyDictionary<AgentId, UsageSnapshot>(
            new Dictionary<AgentId, UsageSnapshot>(snapshots));

    private static JsonSerializerOptions CreateJsonOptions()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            DictionaryKeyPolicy = JsonNamingPolicy.CamelCase,
            PropertyNameCaseInsensitive = true,
            WriteIndented = true,
        };
        options.Converters.Add(new TokenKindSelectionJsonConverter());
        options.Converters.Add(new JsonStringEnumConverter(
            JsonNamingPolicy.CamelCase,
            allowIntegerValues: false));
        return options;
    }

    /// <summary>
    /// Reads the pre-three-kind selection value long enough to discard its
    /// obsolete cache-write flag. The flag is intentionally not part of
    /// <see cref="TokenKindSelection"/> anymore, so this converter is scoped to
    /// settings migration rather than the application domain.
    /// </summary>
    private sealed class TokenKindSelectionJsonConverter :
        JsonConverter<TokenKindSelection>
    {
        public override TokenKindSelection Read(
            ref Utf8JsonReader reader,
            Type typeToConvert,
            JsonSerializerOptions options)
        {
            if (reader.TokenType != JsonTokenType.String ||
                reader.GetString() is not { } raw ||
                string.IsNullOrWhiteSpace(raw))
            {
                throw new JsonException(
                    "Token Kind selection must be a non-empty string.");
            }

            var selection = TokenKindSelection.None;
            foreach (var rawName in raw.Split(
                         ',',
                         StringSplitOptions.RemoveEmptyEntries |
                         StringSplitOptions.TrimEntries))
            {
                switch (rawName.ToLowerInvariant())
                {
                    case "none":
                        break;
                    case "all":
                        selection |= TokenKindSelection.All;
                        break;
                    case "directinput":
                        selection |= TokenKindSelection.DirectInput;
                        break;
                    case "output":
                        selection |= TokenKindSelection.Output;
                        break;
                    case "cacheread":
                        selection |= TokenKindSelection.CacheRead;
                        break;
                    case "cachewrite":
                        // Legacy settings only. It must not become a current
                        // Token Kind or affect the selected total.
                        break;
                    default:
                        throw new JsonException(
                            $"Unknown Token Kind selection '{rawName}'.");
                }
            }

            return selection;
        }

        public override void Write(
            Utf8JsonWriter writer,
            TokenKindSelection value,
            JsonSerializerOptions options)
        {
            if (!value.IsValid())
            {
                throw new JsonException(
                    $"Invalid Token Kind selection '{value}'.");
            }

            if (value == TokenKindSelection.None)
            {
                writer.WriteStringValue("none");
                return;
            }

            if (value == TokenKindSelection.All)
            {
                writer.WriteStringValue("all");
                return;
            }

            var names = new List<string>(3);
            if (value.Includes(TokenKind.DirectInput))
            {
                names.Add("directInput");
            }

            if (value.Includes(TokenKind.Output))
            {
                names.Add("output");
            }

            if (value.Includes(TokenKind.CacheRead))
            {
                names.Add("cacheRead");
            }

            writer.WriteStringValue(string.Join(", ", names));
        }
    }

    private void OnChanged() => Changed?.Invoke(this, EventArgs.Empty);
}
