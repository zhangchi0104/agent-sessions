namespace TokenStats.Core;

public enum RefreshTrigger
{
    Timer,
    Wake,
    PopoverOpen,
    Manual,
}

public sealed record RefreshDecision(bool ShouldFetch, TimeSpan NextInterval);

public static class RefreshPolicy
{
    public static readonly TimeSpan BaseInterval = TimeSpan.FromMinutes(30);
    public static readonly TimeSpan MaxInterval = TimeSpan.FromHours(6);

    public static RefreshDecision Decide(
        RefreshTrigger trigger,
        DateTimeOffset? lastFetch,
        DateTimeOffset now,
        int consecutiveFailures)
    {
        var multiplier = Math.Pow(2, Math.Max(consecutiveFailures, 0));
        var seconds = Math.Min(
            BaseInterval.TotalSeconds * multiplier,
            MaxInterval.TotalSeconds);
        var interval = TimeSpan.FromSeconds(seconds);

        var shouldFetch = trigger != RefreshTrigger.Timer ||
                          lastFetch is null ||
                          now - lastFetch >= interval;
        return new RefreshDecision(shouldFetch, interval);
    }
}
