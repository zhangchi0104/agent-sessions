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
    TodayMetricMode TodayMetric = TodayMetricMode.Token)
{
    public static AppearancePreferences Default { get; } = new(
        AgentId.ClaudeCode,
        AgentRegistry.All.Select(agent => agent.Id).ToArray(),
        GaugeStyle.Dial,
        TodayMetricMode.Token);

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
    OnboardingPreferences Onboarding,
    IReadOnlyDictionary<AgentId, UsageSnapshot> LastSnapshots)
{
    public const int CurrentVersion = 2;

    public static AppSettings Default { get; } = new(
        CurrentVersion,
        AppearancePreferences.Default,
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
        return new AppearancePreferences(
            primary,
            order,
            gaugeStyle,
            todayMetric);
    }

    private static AppSettings Clone(AppSettings settings) => new(
        settings.Version,
        new AppearancePreferences(
            settings.Appearance.PrimaryAgent,
            settings.Appearance.Order.ToArray(),
            settings.Appearance.GaugeStyle,
            settings.Appearance.TodayMetric),
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
        options.Converters.Add(new JsonStringEnumConverter(
            JsonNamingPolicy.CamelCase,
            allowIntegerValues: false));
        return options;
    }

    private void OnChanged() => Changed?.Invoke(this, EventArgs.Empty);
}
