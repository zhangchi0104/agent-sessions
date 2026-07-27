using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using Forms = System.Windows.Forms;

namespace TokenStats.App.Infrastructure;

public static class WindowSizing
{
    private const double WorkAreaMargin = 16;

    public static void ConstrainToCurrentWorkArea(
        Window window,
        double preferredMinimumWidth,
        double preferredMinimumHeight)
    {
        ArgumentNullException.ThrowIfNull(window);
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero)
        {
            return;
        }

        var screen = Forms.Screen.FromHandle(handle);
        var dpi = GetDpiForWindow(handle);
        var constraints = CalculateConstraints(
            screen.WorkingArea.Width,
            screen.WorkingArea.Height,
            dpi,
            preferredMinimumWidth,
            preferredMinimumHeight);

        // WPF rejects MaxWidth/MaxHeight values below the current minimum.
        // Lower the minimum first so very small or highly scaled work areas
        // cannot make the window fail while opening.
        window.MinWidth = constraints.MinimumWidth;
        window.MinHeight = constraints.MinimumHeight;
        window.MaxWidth = constraints.MaximumWidth;
        window.MaxHeight = constraints.MaximumHeight;
        window.Width = Math.Min(window.Width, constraints.MaximumWidth);
        window.Height = Math.Min(window.Height, constraints.MaximumHeight);
    }

    internal static (
        double MinimumWidth,
        double MinimumHeight,
        double MaximumWidth,
        double MaximumHeight) CalculateConstraints(
            double workingAreaWidthPixels,
            double workingAreaHeightPixels,
            double dpi,
            double preferredMinimumWidth,
            double preferredMinimumHeight)
    {
        var scale = dpi > 0 ? dpi / 96d : 1d;
        var maximumWidth = Math.Max(
            1,
            workingAreaWidthPixels / scale - WorkAreaMargin * 2);
        var maximumHeight = Math.Max(
            1,
            workingAreaHeightPixels / scale - WorkAreaMargin * 2);

        return (
            Math.Min(preferredMinimumWidth, maximumWidth),
            Math.Min(preferredMinimumHeight, maximumHeight),
            maximumWidth,
            maximumHeight);
    }

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr window);
}
