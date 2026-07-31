using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Media;
using TokenStats.App.Services;

namespace TokenStats.App.Infrastructure;

internal enum AppearanceWindowKind
{
    Flyout,
    Settings,
    Onboarding,
}

/// <summary>
/// Applies user scaling and top-level opacity without fighting Windows' native
/// per-monitor DPI scaling. The content transform scales text and controls as a
/// unit; the host window grows by the same ratio so the transformed layout is
/// not clipped.
/// </summary>
internal static class WindowAppearanceService
{
    private static readonly ConditionalWeakTable<Window, AppliedState> States = new();

    internal static void Apply(
        Window window,
        FrameworkElement contentRoot,
        VisualAppearancePreferences appearance,
        AppearanceWindowKind kind)
    {
        ArgumentNullException.ThrowIfNull(window);
        ArgumentNullException.ThrowIfNull(contentRoot);
        ArgumentNullException.ThrowIfNull(appearance);

        var scale = Math.Clamp(
            appearance.InterfaceScale,
            VisualAppearancePreferences.MinimumInterfaceScale,
            VisualAppearancePreferences.MaximumInterfaceScale);
        var state = States.GetOrCreateValue(window);
        contentRoot.LayoutTransform = new ScaleTransform(scale, scale);
        contentRoot.UseLayoutRounding = true;

        if (kind == AppearanceWindowKind.Flyout)
        {
            window.Opacity = WindowsThemeService.CurrentTheme ==
                             WindowsAppTheme.HighContrast
                ? 1
                : Math.Clamp(
                    appearance.FlyoutOpacity,
                    VisualAppearancePreferences.MinimumFlyoutOpacity,
                    1);
            window.Width = Math.Clamp(
                               appearance.FlyoutWidth,
                               VisualAppearancePreferences.MinimumFlyoutWidth,
                               VisualAppearancePreferences.MaximumFlyoutWidth) *
                           scale;
            state.Scale = scale;
            state.Initialized = true;
            return;
        }

        window.Opacity = 1;
        if (!state.Initialized || Math.Abs(state.Scale - scale) >= 0.001)
        {
            var previousScale = state.Initialized ? state.Scale : 1;
            ResizeDimension(
                window.Width,
                value => window.Width = value,
                previousScale,
                scale);
            ResizeDimension(
                window.Height,
                value => window.Height = value,
                previousScale,
                scale);
        }

        state.Scale = scale;
        state.Initialized = true;
    }

    private static void ResizeDimension(
        double current,
        Action<double> setter,
        double previousScale,
        double scale)
    {
        if (double.IsFinite(current) && current > 0 && previousScale > 0)
        {
            setter(current / previousScale * scale);
        }
    }

    private sealed class AppliedState
    {
        internal bool Initialized { get; set; }

        internal double Scale { get; set; } = 1;
    }
}
