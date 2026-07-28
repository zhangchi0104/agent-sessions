using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace TokenStats.App.Controls;

public sealed class RollingNumberText : Control
{
    public static readonly DependencyProperty TextProperty =
        DependencyProperty.Register(
            nameof(Text),
            typeof(string),
            typeof(RollingNumberText),
            new FrameworkPropertyMetadata(
                string.Empty,
                FrameworkPropertyMetadataOptions.AffectsMeasure |
                FrameworkPropertyMetadataOptions.AffectsRender,
                TextProperty_OnChanged));

    public static readonly DependencyProperty TextAlignmentProperty =
        DependencyProperty.Register(
            nameof(TextAlignment),
            typeof(TextAlignment),
            typeof(RollingNumberText),
            new FrameworkPropertyMetadata(
                TextAlignment.Left,
                FrameworkPropertyMetadataOptions.AffectsRender));

    private static readonly DependencyProperty AnimationProgressProperty =
        DependencyProperty.Register(
            nameof(AnimationProgress),
            typeof(double),
            typeof(RollingNumberText),
            new FrameworkPropertyMetadata(
                1d,
                FrameworkPropertyMetadataOptions.AffectsRender));

    private string? _previousText;
    private decimal? _numericValue;
    private object? _transitionKey;
    private int _direction = -1;
    private long _animationGeneration;
    private bool _rollUnchangedDigits;
    private bool _isMotionPreferenceSubscribed;

    public RollingNumberText()
    {
        Loaded += RollingNumberText_OnLoaded;
        Unloaded += RollingNumberText_OnUnloaded;
        IsVisibleChanged += (_, eventArgs) =>
        {
            if (eventArgs.NewValue is false)
            {
                StopAnimation();
            }
        };
    }

    public long TransitionRevision { get; private set; }

    public bool IsRolling { get; private set; }

    public string Text
    {
        get => (string)GetValue(TextProperty);
        set => SetValue(TextProperty, value);
    }

    public TextAlignment TextAlignment
    {
        get => (TextAlignment)GetValue(TextAlignmentProperty);
        set => SetValue(TextAlignmentProperty, value);
    }

    private double AnimationProgress
    {
        get => (double)GetValue(AnimationProgressProperty);
        set => SetValue(AnimationProgressProperty, value);
    }

    protected override AutomationPeer OnCreateAutomationPeer() =>
        new RollingNumberTextAutomationPeer(this);

    public void SetAnimatedValue(
        string text,
        decimal? numericValue,
        object? transitionKey,
        bool animate = true)
    {
        ArgumentNullException.ThrowIfNull(text);
        var textChanged = !string.Equals(Text, text, StringComparison.Ordinal);
        var keyChanged = !Equals(_transitionKey, transitionKey);
        if (!textChanged && !keyChanged)
        {
            _numericValue = numericValue;
            return;
        }

        var previousText = Text;
        var previousValue = _numericValue;
        Text = text;
        _numericValue = numericValue;
        _transitionKey = transitionKey;
        TransitionRevision++;

        if (!animate ||
            string.IsNullOrEmpty(previousText) ||
            !IsLoaded ||
            !IsVisible ||
            !SystemParameters.ClientAreaAnimation)
        {
            StopAnimation();
            return;
        }

        _previousText = previousText;
        _rollUnchangedDigits = keyChanged && !textChanged;
        _direction =
            previousValue.HasValue &&
            numericValue.HasValue &&
            numericValue.Value < previousValue.Value
                ? 1
                : -1;
        IsRolling = true;
        var generation = ++_animationGeneration;
        var animation = new DoubleAnimation
        {
            From = 0,
            To = 1,
            Duration = TimeSpan.FromMilliseconds(360),
            EasingFunction = new CubicEase
            {
                EasingMode = EasingMode.EaseOut,
            },
            FillBehavior = FillBehavior.Stop,
        };
        animation.Completed += (_, _) =>
        {
            if (_animationGeneration != generation)
            {
                return;
            }

            _previousText = null;
            _rollUnchangedDigits = false;
            IsRolling = false;
            InvalidateMeasure();
            InvalidateVisual();
        };

        AnimationProgress = 1;
        BeginAnimation(
            AnimationProgressProperty,
            animation,
            HandoffBehavior.SnapshotAndReplace);
    }

    private static void TextProperty_OnChanged(
        DependencyObject dependencyObject,
        DependencyPropertyChangedEventArgs eventArgs)
    {
        if (dependencyObject is not RollingNumberText owner ||
            UIElementAutomationPeer.FromElement(owner) is not
                RollingNumberTextAutomationPeer peer)
        {
            return;
        }

        peer.RaiseNameChanged(
            eventArgs.OldValue as string ?? string.Empty,
            eventArgs.NewValue as string ?? string.Empty);
    }

    protected override Size MeasureOverride(Size constraint)
    {
        var current = string.IsNullOrEmpty(Text)
            ? null
            : CreateFormattedText(Text);
        var previous = string.IsNullOrEmpty(_previousText)
            ? null
            : CreateFormattedText(_previousText);
        var transition = _previousText is null
            ? null
            : CreateTransitionLayout(_previousText, Text);
        var width = transition?.Width ??
                    Math.Max(current?.Width ?? 0, previous?.Width ?? 0);
        var height = transition?.Height ??
                     Math.Max(current?.Height ?? 0, previous?.Height ?? 0);
        if (!double.IsInfinity(constraint.Width))
        {
            width = Math.Min(width, constraint.Width);
        }

        if (!double.IsInfinity(constraint.Height))
        {
            height = Math.Min(height, constraint.Height);
        }

        return new Size(width, height);
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        if (string.IsNullOrEmpty(Text))
        {
            return;
        }

        if (_previousText is null || AnimationProgress >= 1)
        {
            DrawText(drawingContext, Text, 0, 1);
            return;
        }

        var transition = CreateTransitionLayout(_previousText, Text);
        if (transition is null)
        {
            drawingContext.PushClip(new RectangleGeometry(new Rect(RenderSize)));
            DrawText(drawingContext, _previousText, 0, 1 - AnimationProgress);
            DrawText(drawingContext, Text, 0, AnimationProgress);
            drawingContext.Pop();
            return;
        }

        var x = TextAlignment switch
        {
            TextAlignment.Center =>
                Math.Max(0, (ActualWidth - transition.Width) / 2),
            TextAlignment.Right =>
                Math.Max(0, ActualWidth - transition.Width),
            _ => 0,
        };
        var lineHeight = transition.Height;
        var baseY = Math.Max(0, (ActualHeight - lineHeight) / 2);

        drawingContext.PushClip(new RectangleGeometry(new Rect(RenderSize)));
        foreach (var slot in transition.Slots)
        {
            var delay = slot.DigitRankFromRight is { } rank
                ? Math.Min(0.18, rank * 0.03)
                : 0;
            var progress = Math.Clamp(
                (AnimationProgress - delay) / (1 - delay),
                0,
                1);
            DrawSlot(drawingContext, slot, x, baseY, lineHeight, progress);
            x += slot.Width;
        }

        drawingContext.Pop();
    }

    private void StopAnimation()
    {
        _animationGeneration++;
        BeginAnimation(AnimationProgressProperty, null);
        AnimationProgress = 1;
        _previousText = null;
        _rollUnchangedDigits = false;
        IsRolling = false;
        InvalidateMeasure();
        InvalidateVisual();
    }

    private void RollingNumberText_OnLoaded(
        object sender,
        RoutedEventArgs eventArgs)
    {
        if (_isMotionPreferenceSubscribed)
        {
            return;
        }

        SystemParameters.StaticPropertyChanged +=
            SystemParameters_OnStaticPropertyChanged;
        _isMotionPreferenceSubscribed = true;
    }

    private void RollingNumberText_OnUnloaded(
        object sender,
        RoutedEventArgs eventArgs)
    {
        if (_isMotionPreferenceSubscribed)
        {
            SystemParameters.StaticPropertyChanged -=
                SystemParameters_OnStaticPropertyChanged;
            _isMotionPreferenceSubscribed = false;
        }

        StopAnimation();
    }

    private void SystemParameters_OnStaticPropertyChanged(
        object? sender,
        PropertyChangedEventArgs eventArgs)
    {
        if (eventArgs.PropertyName !=
                nameof(SystemParameters.ClientAreaAnimation) ||
            SystemParameters.ClientAreaAnimation)
        {
            return;
        }

        if (Dispatcher.CheckAccess())
        {
            StopAnimation();
        }
        else
        {
            Dispatcher.BeginInvoke(StopAnimation);
        }
    }

    private TransitionLayout? CreateTransitionLayout(
        string previousText,
        string currentText)
    {
        var previous = CreateNumericParts(previousText);
        var current = CreateNumericParts(currentText);
        if (previous is null || current is null)
        {
            return null;
        }

        var slots = new List<GlyphSlot>();
        AddSlot(slots, previous.Prefix, current.Prefix);
        var digitCount = Math.Max(
            previous.Digits.Count,
            current.Digits.Count);
        for (var rank = digitCount - 1; rank >= 0; rank--)
        {
            AddSlot(
                slots,
                previous.DigitAtRank(rank),
                current.DigitAtRank(rank),
                rank);
            if (rank > 0)
            {
                AddSlot(
                    slots,
                    previous.SeparatorAfterRank(rank),
                    current.SeparatorAfterRank(rank));
            }
        }

        AddSlot(slots, previous.Suffix, current.Suffix);
        return new TransitionLayout(
            slots,
            slots.Sum(slot => slot.Width),
            slots.Count == 0
                ? 0
                : slots.Max(slot =>
                    Math.Max(
                        slot.Previous?.Height ?? 0,
                        slot.Current?.Height ?? 0)));
    }

    private NumericParts? CreateNumericParts(string text)
    {
        var digitIndices = new List<int>();
        for (var index = 0; index < text.Length; index++)
        {
            if (char.IsDigit(text[index]))
            {
                digitIndices.Add(index);
            }
        }

        if (digitIndices.Count == 0)
        {
            return null;
        }

        var digits = digitIndices
            .Select(index => CreateGlyph(text[index].ToString()))
            .ToArray();
        var separators = new Dictionary<int, Glyph>();
        for (var index = 0; index < digitIndices.Count - 1; index++)
        {
            var start = digitIndices[index] + 1;
            var length = digitIndices[index + 1] - start;
            if (length == 0)
            {
                continue;
            }

            var higherRank = digitIndices.Count - index - 1;
            separators[higherRank] =
                CreateGlyph(text.Substring(start, length));
        }

        var firstDigit = digitIndices[0];
        var lastDigit = digitIndices[^1];
        return new NumericParts(
            firstDigit == 0
                ? null
                : CreateGlyph(text[..firstDigit]),
            digits,
            separators,
            lastDigit == text.Length - 1
                ? null
                : CreateGlyph(text[(lastDigit + 1)..]));
    }

    private static void AddSlot(
        ICollection<GlyphSlot> slots,
        Glyph? previous,
        Glyph? current,
        int? digitRankFromRight = null)
    {
        if (previous is null && current is null)
        {
            return;
        }

        slots.Add(new GlyphSlot(
            previous,
            current,
            Math.Max(previous?.Width ?? 0, current?.Width ?? 0),
            digitRankFromRight));
    }

    private void DrawSlot(
        DrawingContext context,
        GlyphSlot slot,
        double x,
        double baseY,
        double lineHeight,
        double progress)
    {
        if (slot.Previous is { } previous &&
            slot.Current is { } current &&
            string.Equals(
                previous.Content,
                current.Content,
                StringComparison.Ordinal) &&
            (!_rollUnchangedDigits || slot.DigitRankFromRight is null))
        {
            DrawGlyph(context, current, x, slot.Width, baseY, 1);
            return;
        }

        if (slot.DigitRankFromRight is not null)
        {
            if (slot.Previous is { } rollingOut)
            {
                DrawGlyph(
                    context,
                    rollingOut,
                    x,
                    slot.Width,
                    baseY + _direction * progress * lineHeight,
                    1);
            }

            if (slot.Current is { } rollingIn)
            {
                DrawGlyph(
                    context,
                    rollingIn,
                    x,
                    slot.Width,
                    baseY - _direction * (1 - progress) * lineHeight,
                    1);
            }

            return;
        }

        if (slot.Previous is { } fadingOut)
        {
            DrawGlyph(
                context,
                fadingOut,
                x,
                slot.Width,
                baseY,
                1 - progress);
        }

        if (slot.Current is { } fadingIn)
        {
            DrawGlyph(
                context,
                fadingIn,
                x,
                slot.Width,
                baseY,
                progress);
        }
    }

    private static void DrawGlyph(
        DrawingContext context,
        Glyph glyph,
        double x,
        double slotWidth,
        double y,
        double opacity)
    {
        if (opacity <= 0)
        {
            return;
        }

        context.PushOpacity(opacity);
        context.DrawText(
            glyph.Text,
            new Point(x + (slotWidth - glyph.Width) / 2, y));
        context.Pop();
    }

    private void DrawText(
        DrawingContext context,
        string text,
        double y,
        double opacity)
    {
        var formatted = CreateFormattedText(text);
        var x = TextAlignment switch
        {
            TextAlignment.Center => Math.Max(0, (ActualWidth - formatted.Width) / 2),
            TextAlignment.Right => Math.Max(0, ActualWidth - formatted.Width),
            _ => 0,
        };
        var centeredY = Math.Max(0, (ActualHeight - formatted.Height) / 2) + y;
        context.PushOpacity(opacity);
        context.DrawText(formatted, new Point(x, centeredY));
        context.Pop();
    }

    private Glyph CreateGlyph(string content)
    {
        var formatted = CreateFormattedText(content);
        return new Glyph(
            content,
            formatted,
            formatted.WidthIncludingTrailingWhitespace,
            formatted.Height);
    }

    private FormattedText CreateFormattedText(string text) =>
        new(
            text,
            CultureInfo.CurrentUICulture,
            FlowDirection,
            new Typeface(FontFamily, FontStyle, FontWeight, FontStretch),
            FontSize,
            Foreground,
            VisualTreeHelper.GetDpi(this).PixelsPerDip);

    private sealed record Glyph(
        string Content,
        FormattedText Text,
        double Width,
        double Height);

    private sealed record GlyphSlot(
        Glyph? Previous,
        Glyph? Current,
        double Width,
        int? DigitRankFromRight);

    private sealed record TransitionLayout(
        IReadOnlyList<GlyphSlot> Slots,
        double Width,
        double Height);

    private sealed record NumericParts(
        Glyph? Prefix,
        IReadOnlyList<Glyph> Digits,
        IReadOnlyDictionary<int, Glyph> Separators,
        Glyph? Suffix)
    {
        internal Glyph? DigitAtRank(int rank)
        {
            var index = Digits.Count - rank - 1;
            return index >= 0 && index < Digits.Count
                ? Digits[index]
                : null;
        }

        internal Glyph? SeparatorAfterRank(int rank) =>
            Separators.TryGetValue(rank, out var separator)
                ? separator
                : null;
    }

    private sealed class RollingNumberTextAutomationPeer(
        RollingNumberText owner)
        : FrameworkElementAutomationPeer(owner)
    {
        protected override string GetClassNameCore() =>
            nameof(RollingNumberText);

        protected override AutomationControlType GetAutomationControlTypeCore() =>
            AutomationControlType.Text;

        protected override string GetNameCore() =>
            ((RollingNumberText)Owner).Text;

        protected override bool IsContentElementCore() => true;

        protected override bool IsControlElementCore() => true;

        internal void RaiseNameChanged(string oldName, string newName) =>
            RaisePropertyChangedEvent(
                AutomationElementIdentifiers.NameProperty,
                oldName,
                newName);
    }
}
