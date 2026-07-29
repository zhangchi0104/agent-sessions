using System.Globalization;
using System.Windows;
using System.Windows.Automation.Peers;
using System.Windows.Media;
using TokenStats.App.Services;
using TokenStats.Core;

namespace TokenStats.App.Controls;

public sealed class UsageGauge : FrameworkElement
{
    public static readonly DependencyProperty LabelProperty =
        DependencyProperty.Register(
            nameof(Label),
            typeof(string),
            typeof(UsageGauge),
            new FrameworkPropertyMetadata(
                string.Empty,
                FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty RemainingProperty =
        DependencyProperty.Register(
            nameof(Remaining),
            typeof(double),
            typeof(UsageGauge),
            new FrameworkPropertyMetadata(
                0d,
                FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty ResetTextProperty =
        DependencyProperty.Register(
            nameof(ResetText),
            typeof(string),
            typeof(UsageGauge),
            new FrameworkPropertyMetadata(
                "—",
                FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty IsAvailableProperty =
        DependencyProperty.Register(
            nameof(IsAvailable),
            typeof(bool),
            typeof(UsageGauge),
            new FrameworkPropertyMetadata(
                true,
                FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty IsEmphasizedProperty =
        DependencyProperty.Register(
            nameof(IsEmphasized),
            typeof(bool),
            typeof(UsageGauge),
            new FrameworkPropertyMetadata(
                false,
                FrameworkPropertyMetadataOptions.AffectsRender |
                FrameworkPropertyMetadataOptions.AffectsMeasure));

    public static readonly DependencyProperty GaugeStyleProperty =
        DependencyProperty.Register(
            nameof(GaugeStyle),
            typeof(GaugeStyle),
            typeof(UsageGauge),
            new FrameworkPropertyMetadata(
                GaugeStyle.Dial,
                FrameworkPropertyMetadataOptions.AffectsRender |
                FrameworkPropertyMetadataOptions.AffectsMeasure));

    public string Label
    {
        get => (string)GetValue(LabelProperty);
        set => SetValue(LabelProperty, value);
    }

    public double Remaining
    {
        get => (double)GetValue(RemainingProperty);
        set => SetValue(RemainingProperty, value);
    }

    public string ResetText
    {
        get => (string)GetValue(ResetTextProperty);
        set => SetValue(ResetTextProperty, value);
    }

    public bool IsAvailable
    {
        get => (bool)GetValue(IsAvailableProperty);
        set => SetValue(IsAvailableProperty, value);
    }

    public bool IsEmphasized
    {
        get => (bool)GetValue(IsEmphasizedProperty);
        set => SetValue(IsEmphasizedProperty, value);
    }

    public GaugeStyle GaugeStyle
    {
        get => (GaugeStyle)GetValue(GaugeStyleProperty);
        set => SetValue(GaugeStyleProperty, value);
    }

    protected override Size MeasureOverride(Size availableSize)
    {
        if (GaugeStyle == GaugeStyle.Bar)
        {
            var width = double.IsInfinity(availableSize.Width)
                ? 332
                : Math.Max(120, availableSize.Width);
            return new Size(width, 70);
        }

        var diameter = IsEmphasized ? 104 : 82;
        return new Size(diameter + 8, diameter + 54);
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        if (GaugeStyle == GaugeStyle.Bar)
        {
            DrawBar(drawingContext);
        }
        else
        {
            DrawCircular(drawingContext);
        }
    }

    protected override AutomationPeer OnCreateAutomationPeer() =>
        new FrameworkElementAutomationPeer(this);

    private void DrawCircular(DrawingContext context)
    {
        var usableHeight = Math.Max(40, ActualHeight - 46);
        var diameter = Math.Min(ActualWidth - 8, usableHeight);
        var center = new Point(ActualWidth / 2, diameter / 2 + 2);
        var radius = Math.Max(8, diameter / 2 - 5);
        var lineWidth = IsEmphasized ? 7d : 5.5d;
        var sweep = GaugeStyle == GaugeStyle.Ring ? 360d : 270d;
        var start = GaugeStyle == GaugeStyle.Ring ? -90d : 135d;
        var tint = TintBrush();
        var track = tint.Clone();
        track.Opacity = 0.17;

        DrawArc(context, center, radius, start, sweep, track, lineWidth);
        if (GaugeStyle == GaugeStyle.Dial)
        {
            foreach (var fraction in new[] { 0.25, 0.5, 0.75 })
            {
                var angle = DegreesToRadians(start + fraction * sweep);
                var inner = radius - lineWidth * 1.15;
                var outer = radius - lineWidth * 0.35;
                context.DrawLine(
                    new Pen(SecondaryBrush(), 1.2),
                    PointOnCircle(center, inner, angle),
                    PointOnCircle(center, outer, angle));
            }
        }

        if (IsAvailable)
        {
            DrawArc(
                context,
                center,
                radius,
                start,
                sweep * Math.Clamp(Remaining / 100, 0, 1),
                tint,
                lineWidth);
        }

        var percent = IsAvailable
            ? UsageFormatting.RemainingPercent(Remaining)
            : "—";
        DrawCenteredText(
            context,
            percent,
            IsEmphasized ? 21 : 18,
            FontWeights.SemiBold,
            ForegroundBrush(),
            new Point(center.X, center.Y - 7));
        if (IsAvailable)
        {
            DrawCenteredText(
                context,
                "left",
                10.5,
                FontWeights.Medium,
                SecondaryBrush(),
                new Point(center.X, center.Y + 13));
        }

        if (IsAvailable && Remaining < 30)
        {
            DrawWarning(context, new Point(center.X, center.Y - radius * 0.48), tint);
        }

        var titleY = diameter + 7;
        DrawCenteredText(
            context,
            Label,
            IsEmphasized ? 13 : 12,
            FontWeights.SemiBold,
            ForegroundBrush(),
            new Point(center.X, titleY));
        DrawCenteredText(
            context,
            ResetText == "—" ? "—" : $"↻ {ResetText}",
            11.5,
            FontWeights.Normal,
            SecondaryBrush(),
            new Point(center.X, titleY + 19));
    }

    private void DrawBar(DrawingContext context)
    {
        var tint = TintBrush();
        var track = tint.Clone();
        track.Opacity = 0.17;
        var label = MakeText(
            Label,
            13,
            IsEmphasized ? FontWeights.SemiBold : FontWeights.Medium,
            ForegroundBrush());
        context.DrawText(label, new Point(0, 0));

        var percentText = IsAvailable
            ? $"{UsageFormatting.RemainingPercent(Remaining)} left"
            : "—";
        var percent = MakeText(
            percentText,
            13,
            FontWeights.SemiBold,
            ForegroundBrush());
        context.DrawText(percent, new Point(Math.Max(0, ActualWidth - percent.Width), 0));

        if (IsAvailable && Remaining < 30)
        {
            DrawWarning(context, new Point(label.Width + 12, 8), tint);
        }

        var trackRect = new Rect(0, 27, Math.Max(0, ActualWidth), 8);
        context.DrawRoundedRectangle(track, null, trackRect, 4, 4);
        if (IsAvailable)
        {
            var fill = new Rect(
                0,
                27,
                trackRect.Width * Math.Clamp(Remaining / 100, 0, 1),
                8);
            context.DrawRoundedRectangle(tint, null, fill, 4, 4);
        }

        var reset = MakeText(
            ResetText == "—" ? "—" : $"↻ {ResetText}",
            11.5,
            FontWeights.Normal,
            SecondaryBrush());
        context.DrawText(reset, new Point(0, 43));
    }

    private Brush TintBrush()
    {
        if (!IsAvailable)
        {
            return SecondaryBrush();
        }

        if (SystemParameters.HighContrast)
        {
            return SystemColors.HighlightBrush;
        }

        return Remaining switch
        {
            >= 50 => FrozenBrush("#209B63"),
            >= 30 => FrozenBrush("#D59A00"),
            _ => FrozenBrush("#D84A4A"),
        };
    }

    private static Brush ForegroundBrush() =>
        System.Windows.Application.Current?.TryFindResource("PrimaryTextBrush") as Brush ??
        SystemColors.ControlTextBrush;

    private static Brush SecondaryBrush()
    {
        if (SystemParameters.HighContrast)
        {
            return SystemColors.GrayTextBrush;
        }

        return System.Windows.Application.Current?.TryFindResource("SecondaryTextBrush") as Brush ??
               FrozenBrush("#7A7A7A");
    }

    private static SolidColorBrush FrozenBrush(string color)
    {
        var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
        brush.Freeze();
        return brush;
    }

    private static void DrawArc(
        DrawingContext context,
        Point center,
        double radius,
        double startDegrees,
        double sweepDegrees,
        Brush brush,
        double lineWidth)
    {
        if (sweepDegrees <= 0.001)
        {
            return;
        }

        var pen = new Pen(brush, lineWidth)
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round,
        };
        pen.Freeze();

        if (sweepDegrees >= 359.999)
        {
            DrawArc(context, center, radius, startDegrees, 180, brush, lineWidth);
            DrawArc(context, center, radius, startDegrees + 180, 179.999, brush, lineWidth);
            return;
        }

        var start = PointOnCircle(
            center,
            radius,
            DegreesToRadians(startDegrees));
        var end = PointOnCircle(
            center,
            radius,
            DegreesToRadians(startDegrees + sweepDegrees));
        var geometry = new StreamGeometry();
        using (var figure = geometry.Open())
        {
            figure.BeginFigure(start, false, false);
            figure.ArcTo(
                end,
                new Size(radius, radius),
                0,
                sweepDegrees > 180,
                SweepDirection.Clockwise,
                true,
                false);
        }

        geometry.Freeze();
        context.DrawGeometry(null, pen, geometry);
    }

    private static Point PointOnCircle(Point center, double radius, double radians) =>
        new(
            center.X + radius * Math.Cos(radians),
            center.Y + radius * Math.Sin(radians));

    private static double DegreesToRadians(double degrees) =>
        degrees * Math.PI / 180;

    private void DrawCenteredText(
        DrawingContext context,
        string text,
        double fontSize,
        FontWeight weight,
        Brush brush,
        Point center)
    {
        var formatted = MakeText(text, fontSize, weight, brush);
        context.DrawText(
            formatted,
            new Point(center.X - formatted.Width / 2, center.Y - formatted.Height / 2));
    }

    private FormattedText MakeText(
        string text,
        double fontSize,
        FontWeight weight,
        Brush brush) =>
        new(
            text,
            CultureInfo.CurrentUICulture,
            FlowDirection.LeftToRight,
            new Typeface(
                TryFindResource("AppFontFamily") as FontFamily ??
                new FontFamily(VisualAppearancePreferences.DefaultFontFamily),
                FontStyles.Normal,
                weight,
                FontStretches.Normal),
            fontSize,
            brush,
            VisualTreeHelper.GetDpi(this).PixelsPerDip);

    private void DrawWarning(DrawingContext context, Point center, Brush tint)
    {
        var geometry = new StreamGeometry();
        using (var figure = geometry.Open())
        {
            figure.BeginFigure(new Point(center.X, center.Y - 6), true, true);
            figure.LineTo(new Point(center.X + 6, center.Y + 5), true, false);
            figure.LineTo(new Point(center.X - 6, center.Y + 5), true, false);
        }

        geometry.Freeze();
        context.DrawGeometry(tint, null, geometry);
        var mark = MakeText("!", 8, FontWeights.Bold, Brushes.White);
        context.DrawText(
            mark,
            new Point(center.X - mark.Width / 2, center.Y - mark.Height / 2 + 1));
    }
}
