using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
using TokenStats.App.Controls;
using TokenStats.App.Services;

namespace TokenStats.App.Infrastructure;

internal enum WindowsAppTheme
{
    Light,
    Dark,
    HighContrast,
}

internal static class WindowsThemeService
{
    private const int DwmUseImmersiveDarkModeBefore20H1 = 19;
    private const int DwmUseImmersiveDarkMode = 20;

    internal static event EventHandler? ThemeChanged;

    internal static WindowsAppTheme CurrentTheme { get; private set; } =
        WindowsAppTheme.Light;

    internal static VisualAppearancePreferences CurrentAppearance { get; private set; } =
        VisualAppearancePreferences.Default;

    private static readonly object BackgroundImageCacheGate = new();
    private static BackgroundImageCacheEntry? _backgroundImageCache;

    private sealed record BackgroundImageCacheEntry(
        string Path,
        long Length,
        DateTime LastWriteTimeUtc,
        BitmapSource Image);

    internal static void ApplySystemTheme(ResourceDictionary resources) =>
        Apply(resources, DetectSystemTheme());

    internal static void ApplyAppearance(
        ResourceDictionary resources,
        VisualAppearancePreferences appearance)
    {
        ArgumentNullException.ThrowIfNull(resources);
        ArgumentNullException.ThrowIfNull(appearance);
        var systemTheme = DetectSystemTheme();
        Apply(resources, ResolveTheme(appearance.ThemeMode, systemTheme), appearance);
    }

    internal static WindowsAppTheme ResolveTheme(
        AppThemeMode preference,
        WindowsAppTheme systemTheme)
    {
        if (systemTheme == WindowsAppTheme.HighContrast)
        {
            return WindowsAppTheme.HighContrast;
        }

        return preference switch
        {
            AppThemeMode.Light => WindowsAppTheme.Light,
            AppThemeMode.Dark => WindowsAppTheme.Dark,
            _ => systemTheme,
        };
    }

    internal static void Apply(
        ResourceDictionary resources,
        WindowsAppTheme theme) =>
        Apply(resources, theme, VisualAppearancePreferences.Default);

    internal static void Apply(
        ResourceDictionary resources,
        WindowsAppTheme theme,
        VisualAppearancePreferences appearance)
    {
        ArgumentNullException.ThrowIfNull(resources);
        ArgumentNullException.ThrowIfNull(appearance);
        CurrentTheme = theme;
        CurrentAppearance = appearance;
        var palette = ThemePalette.For(theme);
        if (theme != WindowsAppTheme.HighContrast)
        {
            palette = palette.WithOverrides(appearance.Colors);
        }

        SetBrush(resources, "WindowBackgroundBrush", palette.WindowBackground);
        SetBrush(resources, "CardBackgroundBrush", palette.CardBackground);
        SetBrush(resources, "SubtleBackgroundBrush", palette.SubtleBackground);
        SetBrush(resources, "ControlBackgroundBrush", palette.ControlBackground);
        SetBrush(resources, "ControlHoverBrush", palette.ControlHover);
        SetBrush(resources, "ControlPressedBrush", palette.ControlPressed);
        SetBrush(resources, "PrimaryTextBrush", palette.PrimaryText);
        SetBrush(resources, "SecondaryTextBrush", palette.SecondaryText);
        SetBrush(resources, "DisabledTextBrush", palette.DisabledText);
        SetBrush(resources, "BorderBrush", palette.Border);
        SetBrush(resources, "AccentBrush", palette.Accent);
        SetBrush(resources, "AccentForegroundBrush", palette.AccentForeground);
        SetBrush(resources, "AccentSoftBrush", palette.AccentSoft);
        SetBrush(resources, "SelectionBrush", palette.Selection);
        SetBrush(resources, "SelectionTextBrush", palette.SelectionText);
        SetBrush(
            resources,
            "SelectedItemBackgroundBrush",
            palette.SelectedItemBackground);
        SetBrush(resources, "SelectedItemTextBrush", palette.SelectedItemText);
        SetBrush(resources, "DangerBrush", palette.Danger);
        SetBrush(resources, "WarningBrush", palette.Warning);
        SetBrush(resources, "TokenInputBrush", palette.TokenInput);
        SetBrush(resources, "TokenOutputBrush", palette.TokenOutput);
        SetBrush(resources, "TokenCacheReadBrush", palette.TokenCacheRead);
        SetBrush(resources, "TooltipBackgroundBrush", palette.TooltipBackground);
        resources["AppFontFamily"] = CreateFontFamily(appearance.FontFamily);
        resources["AppBackgroundImageBrush"] = CreateBackgroundImageBrush(
            appearance,
            theme);
        resources["InterfaceScale"] = appearance.InterfaceScale;

        if (System.Windows.Application.Current is { } application)
        {
            foreach (Window window in application.Windows)
            {
                ApplyWindowChrome(window);
                InvalidateThemeVisuals(window);
            }
        }

        ThemeChanged?.Invoke(null, EventArgs.Empty);
    }

    internal static void Attach(Window window)
    {
        window.SourceInitialized += (_, _) => ApplyWindowChrome(window);
        if (new WindowInteropHelper(window).Handle != IntPtr.Zero)
        {
            ApplyWindowChrome(window);
        }
    }

    internal static WindowsAppTheme DetectSystemTheme()
    {
        if (SystemParameters.HighContrast)
        {
            return WindowsAppTheme.HighContrast;
        }

        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is int value && value == 0
                ? WindowsAppTheme.Dark
                : WindowsAppTheme.Light;
        }
        catch
        {
            return WindowsAppTheme.Light;
        }
    }

    private static void ApplyWindowChrome(Window window)
    {
        if (!OperatingSystem.IsWindowsVersionAtLeast(10, 0, 17763))
        {
            return;
        }

        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero)
        {
            return;
        }

        var useDarkChrome = CurrentTheme == WindowsAppTheme.Dark ? 1 : 0;
        var result = DwmSetWindowAttribute(
            handle,
            DwmUseImmersiveDarkMode,
            ref useDarkChrome,
            sizeof(int));
        if (result != 0)
        {
            _ = DwmSetWindowAttribute(
                handle,
                DwmUseImmersiveDarkModeBefore20H1,
                ref useDarkChrome,
                sizeof(int));
        }
    }

    private static void InvalidateThemeVisuals(DependencyObject root)
    {
        if (root is UsageGauge gauge)
        {
            gauge.InvalidateVisual();
        }

        var childCount = VisualTreeHelper.GetChildrenCount(root);
        for (var index = 0; index < childCount; index++)
        {
            InvalidateThemeVisuals(VisualTreeHelper.GetChild(root, index));
        }
    }

    private static void SetBrush(
        ResourceDictionary resources,
        string key,
        Color color)
    {
        if (resources[key] is SolidColorBrush brush && !brush.IsFrozen)
        {
            brush.Color = color;
            return;
        }

        // Reuse a mutable brush when WPF permits it. Shared resources may be
        // frozen after resolution; in that case replace the resource and let
        // ThemeChanged refresh controls that were created in code.
        resources[key] = new SolidColorBrush(color);
    }

    private static FontFamily CreateFontFamily(string value)
    {
        try
        {
            return new FontFamily(
                string.IsNullOrWhiteSpace(value)
                    ? VisualAppearancePreferences.DefaultFontFamily
                    : value);
        }
        catch (ArgumentException)
        {
            return new FontFamily(VisualAppearancePreferences.DefaultFontFamily);
        }
    }

    private static Brush CreateBackgroundImageBrush(
        VisualAppearancePreferences appearance,
        WindowsAppTheme theme)
    {
        if (theme == WindowsAppTheme.HighContrast ||
            appearance.BackgroundImageOpacity <= 0 ||
            string.IsNullOrWhiteSpace(appearance.BackgroundImagePath))
        {
            return new SolidColorBrush(Colors.Transparent);
        }

        try
        {
            var path = Path.GetFullPath(appearance.BackgroundImagePath);
            var file = new FileInfo(path);
            if (!file.Exists || file.Length > 64 * 1024 * 1024)
            {
                ClearCachedBackgroundImage(path);
                return new SolidColorBrush(Colors.Transparent);
            }

            var image = LoadBackgroundImage(path, file);
            var brush = new ImageBrush(image)
            {
                Opacity = appearance.BackgroundImageOpacity,
            };
            ApplyImagePosition(brush, appearance.BackgroundImagePosition);
            switch (appearance.BackgroundImagePlacement)
            {
                case BackgroundImagePlacement.Fit:
                    brush.Stretch = Stretch.Uniform;
                    break;
                case BackgroundImagePlacement.Center:
                    brush.Stretch = Stretch.None;
                    break;
                case BackgroundImagePlacement.Tile:
                    brush.Stretch = Stretch.Fill;
                    brush.TileMode = TileMode.Tile;
                    brush.ViewboxUnits = BrushMappingMode.Absolute;
                    brush.Viewbox = new Rect(
                        0,
                        0,
                        Math.Max(1, image.Width),
                        Math.Max(1, image.Height));
                    brush.ViewportUnits = BrushMappingMode.Absolute;
                    brush.Viewport = new Rect(
                        0,
                        0,
                        Math.Clamp(image.Width, 64, 512),
                        Math.Clamp(image.Height, 64, 512));
                    break;
                default:
                    brush.Stretch = Stretch.UniformToFill;
                    break;
            }

            brush.Freeze();
            return brush;
        }
        catch (Exception exception) when (
            exception is IOException or
            FileFormatException or
            UnauthorizedAccessException or
            NotSupportedException or
            ArgumentException or
            InvalidOperationException)
        {
            return new SolidColorBrush(Colors.Transparent);
        }
    }

    private static BitmapSource LoadBackgroundImage(
        string path,
        FileInfo file)
    {
        lock (BackgroundImageCacheGate)
        {
            var length = file.Length;
            var lastWriteTimeUtc = file.LastWriteTimeUtc;
            if (_backgroundImageCache is { } cached &&
                string.Equals(
                    cached.Path,
                    path,
                    StringComparison.OrdinalIgnoreCase) &&
                cached.Length == length &&
                cached.LastWriteTimeUtc == lastWriteTimeUtc)
            {
                return cached.Image;
            }

            _backgroundImageCache = null;
            var image = new BitmapImage();
            using (var stream = new FileStream(
                       path,
                       FileMode.Open,
                       FileAccess.Read,
                       FileShare.ReadWrite | FileShare.Delete))
            {
                image.BeginInit();
                image.CacheOption = BitmapCacheOption.OnLoad;
                image.CreateOptions = BitmapCreateOptions.IgnoreColorProfile;
                image.DecodePixelWidth = 2560;
                image.StreamSource = stream;
                image.EndInit();
            }

            image.Freeze();
            _backgroundImageCache = new BackgroundImageCacheEntry(
                path,
                length,
                lastWriteTimeUtc,
                image);
            return image;
        }
    }

    private static void ClearCachedBackgroundImage(string path)
    {
        lock (BackgroundImageCacheGate)
        {
            if (_backgroundImageCache is { } cached &&
                string.Equals(
                    cached.Path,
                    path,
                    StringComparison.OrdinalIgnoreCase))
            {
                _backgroundImageCache = null;
            }
        }
    }

    private static void ApplyImagePosition(
        ImageBrush brush,
        BackgroundImagePosition position)
    {
        brush.AlignmentX = position switch
        {
            BackgroundImagePosition.TopLeft or
            BackgroundImagePosition.Left or
            BackgroundImagePosition.BottomLeft => AlignmentX.Left,
            BackgroundImagePosition.TopRight or
            BackgroundImagePosition.Right or
            BackgroundImagePosition.BottomRight => AlignmentX.Right,
            _ => AlignmentX.Center,
        };
        brush.AlignmentY = position switch
        {
            BackgroundImagePosition.TopLeft or
            BackgroundImagePosition.Top or
            BackgroundImagePosition.TopRight => AlignmentY.Top,
            BackgroundImagePosition.BottomLeft or
            BackgroundImagePosition.Bottom or
            BackgroundImagePosition.BottomRight => AlignmentY.Bottom,
            _ => AlignmentY.Center,
        };
    }

    private static Color ResolveColor(string? value, Color fallback)
    {
        if (value is not { Length: 9 } || value[0] != '#')
        {
            return fallback;
        }

        return byte.TryParse(
                   value.AsSpan(1, 2),
                   System.Globalization.NumberStyles.HexNumber,
                   System.Globalization.CultureInfo.InvariantCulture,
                   out var alpha) &&
               byte.TryParse(
                   value.AsSpan(3, 2),
                   System.Globalization.NumberStyles.HexNumber,
                   System.Globalization.CultureInfo.InvariantCulture,
                   out var red) &&
               byte.TryParse(
                   value.AsSpan(5, 2),
                   System.Globalization.NumberStyles.HexNumber,
                   System.Globalization.CultureInfo.InvariantCulture,
                   out var green) &&
               byte.TryParse(
                   value.AsSpan(7, 2),
                   System.Globalization.NumberStyles.HexNumber,
                   System.Globalization.CultureInfo.InvariantCulture,
                   out var blue)
            ? Color.FromArgb(alpha, red, green, blue)
            : fallback;
    }

    private static Color Blend(Color background, Color foreground, double amount)
    {
        amount = Math.Clamp(amount, 0, 1);
        return Color.FromArgb(
            0xFF,
            (byte)Math.Round(background.R + (foreground.R - background.R) * amount),
            (byte)Math.Round(background.G + (foreground.G - background.G) * amount),
            (byte)Math.Round(background.B + (foreground.B - background.B) * amount));
    }

    private static Color WithAlpha(Color color, byte alpha) =>
        Color.FromArgb(alpha, color.R, color.G, color.B);

    private static Color ContrastForeground(Color background) =>
        RelativeLuminance(background) > 0.42
            ? Rgb(0x12, 0x16, 0x19)
            : Colors.White;

    private static double RelativeLuminance(Color color)
    {
        static double Linear(byte component)
        {
            var channel = component / 255d;
            return channel <= 0.04045
                ? channel / 12.92
                : Math.Pow((channel + 0.055) / 1.055, 2.4);
        }

        return 0.2126 * Linear(color.R) +
               0.7152 * Linear(color.G) +
               0.0722 * Linear(color.B);
    }

    private static Color Rgb(int red, int green, int blue) =>
        Color.FromRgb((byte)red, (byte)green, (byte)blue);

    private static Color Argb(int alpha, int red, int green, int blue) =>
        Color.FromArgb((byte)alpha, (byte)red, (byte)green, (byte)blue);

    [DllImport("dwmapi.dll", ExactSpelling = true)]
    private static extern int DwmSetWindowAttribute(
        IntPtr window,
        int attribute,
        ref int attributeValue,
        int attributeSize);

    private sealed record ThemePalette(
        Color WindowBackground,
        Color CardBackground,
        Color SubtleBackground,
        Color ControlBackground,
        Color ControlHover,
        Color ControlPressed,
        Color PrimaryText,
        Color SecondaryText,
        Color DisabledText,
        Color Border,
        Color Accent,
        Color AccentForeground,
        Color AccentSoft,
        Color Selection,
        Color SelectionText,
        Color SelectedItemBackground,
        Color SelectedItemText,
        Color Danger,
        Color Warning,
        Color TokenInput,
        Color TokenOutput,
        Color TokenCacheRead,
        Color TooltipBackground)
    {
        internal ThemePalette WithOverrides(ThemeColorOverrides? overrides)
        {
            overrides ??= ThemeColorOverrides.Empty;
            var windowBackground = ResolveColor(
                overrides.WindowBackground,
                WindowBackground);
            var cardBackground = ResolveColor(
                overrides.CardBackground,
                CardBackground);
            var subtleBackground = ResolveColor(
                overrides.SubtleBackground,
                SubtleBackground);
            var controlBackground = ResolveColor(
                overrides.ControlBackground,
                ControlBackground);
            var primaryText = ResolveColor(overrides.PrimaryText, PrimaryText);
            var secondaryText = ResolveColor(overrides.SecondaryText, SecondaryText);
            var accent = ResolveColor(overrides.Accent, Accent);
            var controlChanged = overrides.ControlBackground is not null ||
                                 overrides.PrimaryText is not null;
            var textChanged = overrides.WindowBackground is not null ||
                              overrides.PrimaryText is not null ||
                              overrides.SecondaryText is not null;
            var accentChanged = overrides.Accent is not null;

            return this with
            {
                WindowBackground = windowBackground,
                CardBackground = cardBackground,
                SubtleBackground = subtleBackground,
                ControlBackground = controlBackground,
                ControlHover = controlChanged
                    ? Blend(controlBackground, primaryText, 0.08)
                    : ControlHover,
                ControlPressed = controlChanged
                    ? Blend(controlBackground, primaryText, 0.14)
                    : ControlPressed,
                PrimaryText = primaryText,
                SecondaryText = secondaryText,
                DisabledText = textChanged
                    ? Blend(windowBackground, secondaryText, 0.58)
                    : DisabledText,
                Border = ResolveColor(overrides.Border, Border),
                Accent = accent,
                AccentForeground = accentChanged
                    ? ContrastForeground(accent)
                    : AccentForeground,
                AccentSoft = accentChanged
                    ? WithAlpha(accent, AccentSoft.A)
                    : AccentSoft,
                Selection = accentChanged ? accent : Selection,
                SelectionText = accentChanged
                    ? ContrastForeground(accent)
                    : SelectionText,
                SelectedItemBackground = accentChanged
                    ? WithAlpha(accent, SelectedItemBackground.A)
                    : SelectedItemBackground,
                SelectedItemText = accentChanged ? accent : SelectedItemText,
                Danger = ResolveColor(overrides.Danger, Danger),
                Warning = ResolveColor(overrides.Warning, Warning),
                TokenInput = ResolveColor(overrides.TokenInput, TokenInput),
                TokenOutput = ResolveColor(overrides.TokenOutput, TokenOutput),
                TokenCacheRead = ResolveColor(
                    overrides.TokenCacheRead,
                    TokenCacheRead),
                TooltipBackground = overrides.CardBackground is not null
                    ? cardBackground
                    : TooltipBackground,
            };
        }

        internal static ThemePalette For(WindowsAppTheme theme) =>
            theme switch
            {
                WindowsAppTheme.Dark => new ThemePalette(
                    Rgb(0x20, 0x22, 0x25),
                    Rgb(0x2B, 0x2E, 0x32),
                    Rgb(0x25, 0x28, 0x2C),
                    Rgb(0x30, 0x34, 0x39),
                    Rgb(0x39, 0x3E, 0x44),
                    Rgb(0x43, 0x49, 0x50),
                    Rgb(0xF3, 0xF4, 0xF5),
                    Rgb(0xB3, 0xB8, 0xC0),
                    Rgb(0x7D, 0x83, 0x8B),
                    Rgb(0x46, 0x4A, 0x50),
                    Rgb(0x45, 0xD0, 0xAD),
                    Rgb(0x0B, 0x25, 0x1E),
                    Argb(0x30, 0x45, 0xD0, 0xAD),
                    Rgb(0x36, 0xA9, 0x8D),
                    Rgb(0x08, 0x1F, 0x19),
                    Argb(0x30, 0x45, 0xD0, 0xAD),
                    Rgb(0x45, 0xD0, 0xAD),
                    Rgb(0xFF, 0x7B, 0x72),
                    Rgb(0xF1, 0xC7, 0x5B),
                    Rgb(0x4A, 0x99, 0xF0),
                    Rgb(0x38, 0xAD, 0x87),
                    Rgb(0x8F, 0x85, 0xBF),
                    Rgb(0x38, 0x3C, 0x42)),
                WindowsAppTheme.HighContrast => new ThemePalette(
                    SystemColors.WindowColor,
                    SystemColors.WindowColor,
                    SystemColors.ControlColor,
                    SystemColors.WindowColor,
                    SystemColors.HighlightColor,
                    SystemColors.HotTrackColor,
                    SystemColors.WindowTextColor,
                    SystemColors.GrayTextColor,
                    SystemColors.GrayTextColor,
                    SystemColors.WindowTextColor,
                    SystemColors.HighlightColor,
                    SystemColors.HighlightTextColor,
                    SystemColors.ControlColor,
                    SystemColors.HighlightColor,
                    SystemColors.HighlightTextColor,
                    SystemColors.HighlightColor,
                    SystemColors.HighlightTextColor,
                    SystemColors.HotTrackColor,
                    SystemColors.HotTrackColor,
                    SystemColors.HighlightColor,
                    SystemColors.HotTrackColor,
                    SystemColors.GrayTextColor,
                    SystemColors.InfoColor),
                _ => new ThemePalette(
                    Rgb(0xF9, 0xFA, 0xFB),
                    Rgb(0xFF, 0xFF, 0xFF),
                    Rgb(0xF1, 0xF3, 0xF5),
                    Rgb(0xFF, 0xFF, 0xFF),
                    Rgb(0xEA, 0xED, 0xF0),
                    Rgb(0xDD, 0xE2, 0xE7),
                    Rgb(0x17, 0x19, 0x1C),
                    Rgb(0x62, 0x67, 0x6F),
                    Rgb(0x98, 0x9D, 0xA4),
                    Rgb(0xD9, 0xDC, 0xE1),
                    Rgb(0x08, 0x86, 0x6D),
                    Rgb(0xFF, 0xFF, 0xFF),
                    Argb(0x1F, 0x08, 0x86, 0x6D),
                    Rgb(0x08, 0x86, 0x6D),
                    Rgb(0xFF, 0xFF, 0xFF),
                    Argb(0x1F, 0x08, 0x86, 0x6D),
                    Rgb(0x08, 0x86, 0x6D),
                    Rgb(0xC9, 0x37, 0x37),
                    Rgb(0xA6, 0x68, 0x00),
                    Rgb(0x21, 0x6B, 0xC7),
                    Rgb(0x17, 0x78, 0x59),
                    Rgb(0x66, 0x5C, 0x9E),
                    Rgb(0xFF, 0xFF, 0xFF)),
            };
    }
}
