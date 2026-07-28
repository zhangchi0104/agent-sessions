using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace TokenStats.App.Infrastructure;

public sealed class TrayIconService : IDisposable
{
    private readonly NotifyIcon _notifyIcon;
    private readonly Icon _icon;
    private readonly ContextMenuStrip _menu;
    private readonly ToolStripMenuItem _refreshItem;
    private bool _disposed;

    public TrayIconService(
        Action toggleFlyout,
        Func<Task> refreshAll,
        Action showSettings,
        Action quit)
    {
        _icon = CreateGaugeIcon();
        var refreshItem = new ToolStripMenuItem("Refresh all");
        refreshItem.Click += async (_, _) =>
        {
            refreshItem.Enabled = false;
            try
            {
                await refreshAll().ConfigureAwait(true);
            }
            finally
            {
                refreshItem.Enabled = true;
            }
        };
        _refreshItem = refreshItem;

        _menu = new ContextMenuStrip();
        _menu.Items.Add(new ToolStripMenuItem("Open TokenStats", null, (_, _) => toggleFlyout())
        {
            Font = new Font(_menu.Font, FontStyle.Bold),
        });
        _menu.Items.Add(_refreshItem);
        _menu.Items.Add(new ToolStripSeparator());
        _menu.Items.Add(new ToolStripMenuItem("Settings…", null, (_, _) => showSettings()));
        _menu.Items.Add(new ToolStripSeparator());
        _menu.Items.Add(new ToolStripMenuItem("Quit TokenStats", null, (_, _) => quit()));
        ApplyMenuTheme();

        _notifyIcon = new NotifyIcon
        {
            ContextMenuStrip = _menu,
            Icon = _icon,
            Text = "TokenStats —",
            Visible = true,
        };
        _notifyIcon.MouseClick += (_, eventArgs) =>
        {
            if (eventArgs.Button == MouseButtons.Left)
            {
                toggleFlyout();
            }
        };
        WindowsThemeService.ThemeChanged += WindowsThemeService_OnThemeChanged;
    }

    public void UpdateSummary(string summary)
    {
        var text = $"TokenStats {summary}";
        _notifyIcon.Text = text[..Math.Min(text.Length, 127)];
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        WindowsThemeService.ThemeChanged -= WindowsThemeService_OnThemeChanged;
        _notifyIcon.Visible = false;
        _notifyIcon.ContextMenuStrip = null;
        _menu.Dispose();
        _notifyIcon.Dispose();
        _icon.Dispose();
    }

    private void WindowsThemeService_OnThemeChanged(
        object? sender,
        EventArgs eventArgs)
    {
        if (_disposed)
        {
            return;
        }

        ApplyMenuTheme();
    }

    private void ApplyMenuTheme()
    {
        if (WindowsThemeService.CurrentTheme == WindowsAppTheme.Dark)
        {
            _menu.Renderer = new DarkMenuRenderer();
            _menu.BackColor = DarkMenuColorTable.Background;
            _menu.ForeColor = DarkMenuColorTable.Foreground;
            SetItemForeground(_menu.Items, DarkMenuColorTable.Foreground);
        }
        else
        {
            // The system renderer is important for High Contrast, and also
            // restores native light-mode selection and disabled states.
            _menu.Renderer = new ToolStripSystemRenderer();
            _menu.BackColor = SystemColors.Menu;
            _menu.ForeColor = SystemColors.MenuText;
            SetItemForeground(_menu.Items, SystemColors.MenuText);
        }

        _menu.Invalidate();
    }

    private static void SetItemForeground(
        ToolStripItemCollection items,
        Color foreground)
    {
        foreach (ToolStripItem item in items)
        {
            item.ForeColor = foreground;
            if (item is ToolStripDropDownItem dropDown)
            {
                SetItemForeground(dropDown.DropDownItems, foreground);
            }
        }
    }

    private static Icon CreateGaugeIcon()
    {
        using var bitmap = new Bitmap(32, 32);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.Clear(Color.Transparent);
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;

            using var outline = new Pen(Color.FromArgb(210, 28, 31, 34), 5.5f)
            {
                StartCap = LineCap.Round,
                EndCap = LineCap.Round,
            };
            using var track = new Pen(Color.FromArgb(245, 238, 242, 243), 3.2f)
            {
                StartCap = LineCap.Round,
                EndCap = LineCap.Round,
            };
            using var active = new Pen(Color.FromArgb(255, 10, 163, 128), 3.2f)
            {
                StartCap = LineCap.Round,
                EndCap = LineCap.Round,
            };
            var arcRect = new RectangleF(4.5f, 4.5f, 23, 23);
            graphics.DrawArc(outline, arcRect, 135, 270);
            graphics.DrawArc(track, arcRect, 135, 270);
            graphics.DrawArc(active, arcRect, 135, 178);

            using var needle = new Pen(Color.FromArgb(255, 239, 177, 48), 2.4f)
            {
                StartCap = LineCap.Round,
                EndCap = LineCap.Round,
            };
            graphics.DrawLine(needle, 16, 17, 22.5f, 10.5f);
            using var hub = new SolidBrush(Color.FromArgb(255, 28, 31, 34));
            graphics.FillEllipse(hub, 13.5f, 14.5f, 5, 5);
        }

        var handle = bitmap.GetHicon();
        try
        {
            using var borrowed = Icon.FromHandle(handle);
            return (Icon)borrowed.Clone();
        }
        finally
        {
            DestroyIcon(handle);
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr handle);

    private sealed class DarkMenuRenderer : ToolStripProfessionalRenderer
    {
        internal DarkMenuRenderer()
            : base(new DarkMenuColorTable())
        {
            RoundedEdges = false;
        }

        protected override void OnRenderItemText(
            ToolStripItemTextRenderEventArgs eventArgs)
        {
            eventArgs.TextColor = eventArgs.Item.Enabled
                ? DarkMenuColorTable.Foreground
                : DarkMenuColorTable.DisabledForeground;
            base.OnRenderItemText(eventArgs);
        }
    }

    private sealed class DarkMenuColorTable : ProfessionalColorTable
    {
        internal static readonly Color Background =
            Color.FromArgb(255, 43, 46, 50);
        internal static readonly Color Foreground =
            Color.FromArgb(255, 243, 244, 245);
        internal static readonly Color DisabledForeground =
            Color.FromArgb(255, 125, 131, 139);
        private static readonly Color Hover =
            Color.FromArgb(255, 57, 62, 68);
        private static readonly Color Pressed =
            Color.FromArgb(255, 67, 73, 80);
        private static readonly Color Border =
            Color.FromArgb(255, 70, 74, 80);

        internal DarkMenuColorTable()
        {
            UseSystemColors = false;
        }

        public override Color ToolStripDropDownBackground => Background;
        public override Color ImageMarginGradientBegin => Background;
        public override Color ImageMarginGradientMiddle => Background;
        public override Color ImageMarginGradientEnd => Background;
        public override Color MenuBorder => Border;
        public override Color MenuItemBorder => Border;
        public override Color MenuItemSelected => Hover;
        public override Color MenuItemSelectedGradientBegin => Hover;
        public override Color MenuItemSelectedGradientEnd => Hover;
        public override Color MenuItemPressedGradientBegin => Pressed;
        public override Color MenuItemPressedGradientMiddle => Pressed;
        public override Color MenuItemPressedGradientEnd => Pressed;
        public override Color SeparatorDark => Border;
        public override Color SeparatorLight => Background;
        public override Color ToolStripBorder => Border;
        public override Color ToolStripGradientBegin => Background;
        public override Color ToolStripGradientMiddle => Background;
        public override Color ToolStripGradientEnd => Background;
        public override Color CheckBackground => Hover;
        public override Color CheckSelectedBackground => Hover;
        public override Color CheckPressedBackground => Pressed;
    }
}
