using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using Drawing = System.Drawing;
using Forms = System.Windows.Forms;

namespace TokenStats.App.Infrastructure;

public static class WindowSizing
{
    private const double WorkAreaMargin = 16;
    private const int NotificationAnchorOffset = 24;

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

    /// <summary>
    /// Calculates a notification-area flyout rectangle entirely in physical
    /// pixels. The result is inset from and clamped to the supplied work area,
    /// including when the requested window is larger than that usable space.
    /// </summary>
    internal static Drawing.Rectangle CalculateFlyoutPlacement(
        Drawing.Rectangle workingArea,
        Drawing.Rectangle screenBounds,
        Drawing.Point anchor,
        Drawing.Size windowSize,
        int margin)
    {
        if (workingArea.Width <= 0 || workingArea.Height <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(workingArea),
                workingArea,
                "The work area must have a positive size.");
        }

        if (screenBounds.Width <= 0 || screenBounds.Height <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(screenBounds),
                screenBounds,
                "The screen bounds must have a positive size.");
        }

        if (windowSize.Width <= 0 || windowSize.Height <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(windowSize),
                windowSize,
                "The flyout must have a positive size.");
        }

        if (margin < 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(margin),
                margin,
                "The work-area margin cannot be negative.");
        }

        // Preserve at least one usable pixel even when a synthetic/test work
        // area is narrower than twice the requested margin.
        var horizontalMargin = Math.Min(
            margin,
            Math.Max(0, (workingArea.Width - 1) / 2));
        var verticalMargin = Math.Min(
            margin,
            Math.Max(0, (workingArea.Height - 1) / 2));
        var availableWidth = Math.Max(
            1,
            workingArea.Width - horizontalMargin * 2);
        var availableHeight = Math.Max(
            1,
            workingArea.Height - verticalMargin * 2);
        var width = Math.Min(windowSize.Width, availableWidth);
        var height = Math.Min(windowSize.Height, availableHeight);
        var minimumX = workingArea.Left + horizontalMargin;
        var maximumX = workingArea.Right - horizontalMargin - width;
        var minimumY = workingArea.Top + verticalMargin;
        var maximumY = workingArea.Bottom - verticalMargin - height;

        var x = anchor.X - width + NotificationAnchorOffset;
        int y;
        if (workingArea.Top > screenBounds.Top)
        {
            // Taskbar/appbar on the top edge.
            y = minimumY;
        }
        else if (workingArea.Left > screenBounds.Left)
        {
            // Taskbar/appbar on the left edge.
            x = minimumX;
            y = anchor.Y - height / 2;
        }
        else if (workingArea.Right < screenBounds.Right)
        {
            // Taskbar/appbar on the right edge.
            x = maximumX;
            y = anchor.Y - height / 2;
        }
        else
        {
            // The Windows notification area is normally on the bottom edge.
            y = maximumY;
        }

        return new Drawing.Rectangle(
            Math.Clamp(x, minimumX, maximumX),
            Math.Clamp(y, minimumY, maximumY),
            width,
            height);
    }

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr window);
}
