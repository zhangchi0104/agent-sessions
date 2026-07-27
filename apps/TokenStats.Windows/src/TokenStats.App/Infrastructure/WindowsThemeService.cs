using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using Microsoft.Win32;
using TokenStats.App.Controls;

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

    internal static void ApplySystemTheme(ResourceDictionary resources) =>
        Apply(resources, DetectSystemTheme());

    internal static void Apply(
        ResourceDictionary resources,
        WindowsAppTheme theme)
    {
        CurrentTheme = theme;
        var palette = ThemePalette.For(theme);
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
        SetBrush(resources, "TooltipBackgroundBrush", palette.TooltipBackground);

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
        Color TooltipBackground)
    {
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
                    Rgb(0xFF, 0xFF, 0xFF)),
            };
    }
}
