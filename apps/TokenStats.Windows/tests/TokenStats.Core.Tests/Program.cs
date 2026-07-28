using System.Globalization;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using TokenStats.Core;

namespace TokenStats.Core.Tests;

internal static class Program
{
    private static readonly CultureInfo Invariant = CultureInfo.InvariantCulture;

    public static async Task<int> Main()
    {
        var tests = new TestCase[]
        {
            new(nameof(ClaudeUsageParserReadsKnownWindows), Sync(ClaudeUsageParserReadsKnownWindows)),
            new(nameof(CodexUsageParserReadsPrimaryAndSecondary), Sync(CodexUsageParserReadsPrimaryAndSecondary)),
            new(nameof(CodexUsageParserHandlesWeeklyOnlyAndMalformedPrimary), Sync(CodexUsageParserHandlesWeeklyOnlyAndMalformedPrimary)),
            new(nameof(CodexUsageParserRecognizesNoLimitPayloads), Sync(CodexUsageParserRecognizesNoLimitPayloads)),
            new(nameof(OAuthHelpersBuildPkceAndClaudeFlow), Sync(OAuthHelpersBuildPkceAndClaudeFlow)),
            new(nameof(CodexOAuthExtractsAccountId), Sync(CodexOAuthExtractsAccountId)),
            new(nameof(FormattingPreservesRemainingSemantics), Sync(FormattingPreservesRemainingSemantics)),
            new(nameof(TokenMetricExcludesCacheReads), Sync(TokenMetricExcludesCacheReads)),
            new(nameof(TokenOdometerKindsIncludeCacheReads), Sync(TokenOdometerKindsIncludeCacheReads)),
            new(nameof(TokenSelectionsDriveTotalsAndFormatting), Sync(TokenSelectionsDriveTotalsAndFormatting)),
            new(nameof(ApiPricingCatalogPricesKnownModelsAndDisclosesUnknown), Sync(ApiPricingCatalogPricesKnownModelsAndDisclosesUnknown)),
            new(nameof(ApiPricingCatalogFiltersSelectedKinds), Sync(ApiPricingCatalogFiltersSelectedKinds)),
            new(nameof(RefreshPolicyAppliesCadenceAndBackoff), Sync(RefreshPolicyAppliesCadenceAndBackoff)),
            new(nameof(StateReducerDisclosesStaleData), Sync(StateReducerDisclosesStaleData)),
            new(nameof(TokenCacheSignOutWinsInFlightRefresh), TokenCacheSignOutWinsInFlightRefresh),
            new(nameof(TokenCacheDoesNotPublishFailedAdoption), TokenCacheDoesNotPublishFailedAdoption),
            new(nameof(OAuthHttpClientBuildsExpectedRequestsAndSurfacesErrors), OAuthHttpClientBuildsExpectedRequestsAndSurfacesErrors),
            new(nameof(UsageProvidersSendExpectedHeadersAndRejectEmptyWindows), UsageProvidersSendExpectedHeadersAndRejectEmptyWindows),
            new(nameof(ClaudeTranscriptsDeduplicateByMessageIdAndUseLocalDay), ClaudeTranscriptsDeduplicateByMessageIdAndUseLocalDay),
            new(nameof(ClaudeTranscriptsCaptureModelAndCacheWriteDurations), ClaudeTranscriptsCaptureModelAndCacheWriteDurations),
            new(nameof(CodexTranscriptsSplitCachedInputAndScanRecursively), CodexTranscriptsSplitCachedInputAndScanRecursively),
            new(nameof(CodexTranscriptsTrackModelsCacheWritesAndUnknown), CodexTranscriptsTrackModelsCacheWritesAndUnknown),
            new(nameof(CodexRunningTotalsDeduplicateAdvanceAndReset), CodexRunningTotalsDeduplicateAdvanceAndReset),
            new(nameof(CodexOpeningBaselineExcludesInheritedHead), CodexOpeningBaselineExcludesInheritedHead),
            new(nameof(CodexModelAttributionBackfillsAndReadsThreadSettings), CodexModelAttributionBackfillsAndReadsThreadSettings),
            new(nameof(CodexTranscriptRetainsModelAcrossIncrementalAppends), CodexTranscriptRetainsModelAcrossIncrementalAppends),
            new(nameof(TokenRangesUseExactLocalCalendarDays), TokenRangesUseExactLocalCalendarDays),
            new(nameof(TranscriptReadsOnlyAppendedBytesAndRetainsPartialLines), TranscriptReadsOnlyAppendedBytesAndRetainsPartialLines),
        };

        var failed = 0;
        foreach (var test in tests)
        {
            try
            {
                await test.Run().ConfigureAwait(false);
                Console.WriteLine($"PASS {test.Name}");
            }
            catch (Exception error)
            {
                failed++;
                Console.Error.WriteLine($"FAIL {test.Name}");
                Console.Error.WriteLine(error);
            }
        }

        Console.WriteLine(
            $"{tests.Length - failed}/{tests.Length} tests passed.");
        return failed == 0 ? 0 : 1;
    }

    private static Func<Task> Sync(Action test) =>
        () =>
        {
            test();
            return Task.CompletedTask;
        };

    private static void ClaudeUsageParserReadsKnownWindows()
    {
        const string json = """
            {
              "five_hour": {
                "utilization": 24.5,
                "resets_at": "2026-07-27T05:00:00.123456+00:00"
              },
              "seven_day": {
                "utilization": 18,
                "resets_at": null
              },
              "limits": [
                {
                  "kind": "weekly_scoped",
                  "percent": 91,
                  "resets_at": "2026-08-01T00:00:00Z",
                  "scope": { "model": { "display_name": "Other model" } }
                },
                {
                  "kind": "weekly_scoped",
                  "percent": "broken",
                  "resets_at": false,
                  "scope": { "model": { "display_name": "Fable broken" } }
                },
                {
                  "kind": "weekly_scoped",
                  "percent": 61,
                  "resets_at": "2026-08-02T00:00:00Z",
                  "scope": { "model": { "display_name": "Fable 5" } }
                }
              ]
            }
            """;

        var windows = ClaudeUsageParser.Parse(json);
        Check.Equal(3, windows.Count);
        Check.Equal("5-hour", windows[0].Label);
        Check.Near(24.5, windows[0].PercentConsumed);
        Check.Near(75.5, windows[0].PercentRemaining);
        Check.Equal(
            DateTimeOffset.Parse(
                "2026-07-27T05:00:00.123456+00:00",
                Invariant),
            windows[0].ResetAt);
        Check.Equal("Weekly", windows[1].Label);
        Check.True(windows[1].ResetAt is null);
        Check.Equal("Fable", windows[2].Label);
        Check.Near(61, windows[2].PercentConsumed);
    }

    private static void CodexUsageParserReadsPrimaryAndSecondary()
    {
        const string json = """
            {
              "rate_limit": {
                "primary_window": {
                  "used_percent": 42,
                  "limit_window_seconds": 18000,
                  "reset_at": 1716800000
                },
                "secondary_window": {
                  "used_percent": 18,
                  "limit_window_seconds": 604800,
                  "reset_at": 0
                }
              },
              "credits": { "balance": "9.99" }
            }
            """;

        var windows = CodexUsageParser.Parse(json);
        Check.Equal(2, windows.Count);
        Check.Equal("5-hour", windows[0].Label);
        Check.Near(42, windows[0].PercentConsumed);
        Check.Equal(
            DateTimeOffset.FromUnixTimeSeconds(1_716_800_000),
            windows[0].ResetAt);
        Check.Equal(UsageWindowKind.ShortTerm, windows[0].Kind);
        Check.Equal<long?>(18_000, windows[0].DurationSeconds);
        Check.Equal("Weekly", windows[1].Label);
        Check.True(windows[1].ResetAt is null);
        Check.Equal(UsageWindowKind.Weekly, windows[1].Kind);
        Check.Equal<long?>(604_800, windows[1].DurationSeconds);

        Check.Equal(
            0,
            CodexUsageParser.Parse("""{"rate_limit":{"primary_window":"broken"}}""")
                .Count);
    }

    private static void CodexUsageParserHandlesWeeklyOnlyAndMalformedPrimary()
    {
        const string validWeekly = """
            {
              "used_percent": 18,
              "limit_window_seconds": 604800,
              "reset_at": 1717300000
            }
            """;
        var weeklyOnly = CodexUsageParser.Parse(
            """{"rate_limit":{"secondary_window":""" + validWeekly + "}}");
        Check.Equal(1, weeklyOnly.Count);
        Check.Equal("Weekly", weeklyOnly[0].Label);
        Check.Equal(UsageWindowKind.Weekly, weeklyOnly[0].Kind);
        Check.Equal<long?>(604_800, weeklyOnly[0].DurationSeconds);

        var weeklyMovedToPrimary = CodexUsageParser.Parse(
            """{"rate_limit":{"primary_window":""" + validWeekly + "}}");
        Check.Equal(1, weeklyMovedToPrimary.Count);
        Check.Equal("Weekly", weeklyMovedToPrimary[0].Label);
        Check.Equal(UsageWindowKind.Weekly, weeklyMovedToPrimary[0].Kind);

        foreach (var malformedPrimary in new[]
                 {
                     """{"used_percent":"broken","reset_at":0}""",
                     """{"used_percent":42,"reset_at":"broken"}""",
                 })
        {
            var windows = CodexUsageParser.Parse(
                $$"""
                  {
                    "rate_limit": {
                      "primary_window": {{malformedPrimary}},
                      "secondary_window": {{validWeekly}}
                    }
                  }
                  """);
            Check.Equal(1, windows.Count);
            Check.Equal("Weekly", windows[0].Label);
        }

        var nullReset = CodexUsageParser.Parse(
            """
            {
              "rate_limit": {
                "primary_window": {
                  "used_percent": 42,
                  "limit_window_seconds": 18000,
                  "reset_at": null
                }
              }
            }
            """);
        Check.Equal(1, nullReset.Count);
        Check.Equal("5-hour", nullReset[0].Label);
        Check.Equal(UsageWindowKind.ShortTerm, nullReset[0].Kind);
        Check.True(nullReset[0].ResetAt is null);
    }

    private static void CodexUsageParserRecognizesNoLimitPayloads()
    {
        foreach (var json in new[]
                 {
                     """{"rate_limit":null}""",
                     """{"rate_limit":{}}""",
                     """{"rate_limit":{"primary_window":null,"secondary_window":null}}""",
                     """{"credits":{"unlimited":true}}""",
                     """{"agentic_usage":{}}""",
                 })
        {
            Check.True(CodexUsageParser.IsRecognizedNoLimit(json));
            Check.Equal(0, CodexUsageParser.Parse(json).Count);
        }

        Check.False(CodexUsageParser.IsRecognizedNoLimit("{}"));
        Check.False(CodexUsageParser.IsRecognizedNoLimit(
            """{"rate_limit":{"primary_window":"broken"}}"""));
        Check.False(CodexUsageParser.IsRecognizedNoLimit("not json"));
    }

    private static void OAuthHelpersBuildPkceAndClaudeFlow()
    {
        var pkce = OAuthHelpers.MakePkce();
        Check.Equal(43, pkce.Verifier.Length);
        Check.Equal(
            OAuthHelpers.Base64Url(
                SHA256.HashData(Encoding.UTF8.GetBytes(pkce.Verifier))),
            pkce.Challenge);
        Check.False(pkce.Verifier.Contains('='));
        Check.False(pkce.Challenge.Contains('+'));

        var state = OAuthHelpers.MakeState();
        var authorizeUrl = ClaudeOAuthFlow.AuthorizeUrl(pkce, state);
        Check.True(authorizeUrl.StartsWith(
            ClaudeOAuthFlow.AuthorizeEndpoint,
            StringComparison.Ordinal));
        Check.True(authorizeUrl.Contains(
            $"client_id={ClaudeOAuthFlow.ClientId}",
            StringComparison.Ordinal));
        Check.True(authorizeUrl.Contains(
            $"state={state}",
            StringComparison.Ordinal));
        Check.True(authorizeUrl.Contains(
            "code_challenge_method=S256",
            StringComparison.Ordinal));

        var pasted = OAuthHelpers.SplitPastedCode("  approval-code#returned-state  ");
        Check.Equal("approval-code", pasted.Code);
        Check.Equal("returned-state", pasted.State);

        var now = DateTimeOffset.Parse("2026-07-27T00:00:00Z", Invariant);
        var tokens = ClaudeOAuthFlow.ParseTokens(
            """{"access_token":"access","refresh_token":"refresh","expires_in":3600}""",
            now);
        Check.Equal("access", tokens.AccessToken);
        Check.Equal("refresh", tokens.RefreshToken);
        Check.Equal(now.AddHours(1), tokens.ExpiresAt);
        Check.False(tokens.IsExpired(now.AddMinutes(58)));
        Check.True(tokens.IsExpired(now.AddMinutes(59)));
    }

    private static void CodexOAuthExtractsAccountId()
    {
        const string accountId = "account-123";
        var payload = OAuthHelpers.Base64Url(
            Encoding.UTF8.GetBytes(
                """{"https://api.openai.com/auth":{"chatgpt_account_id":"account-123"}}"""));
        var idToken = $"header.{payload}.signature";

        Check.Equal(accountId, CodexOAuthFlow.AccountIdFromIdToken(idToken));
        Check.True(CodexOAuthFlow.AccountIdFromIdToken("not-a-jwt") is null);
        Check.Equal(
            "http://localhost:1455/auth/callback",
            CodexOAuthFlow.RedirectUri(1455));

        var now = DateTimeOffset.Parse("2026-07-27T00:00:00Z", Invariant);
        var tokens = CodexOAuthFlow.ParseTokens(
            $$"""{"access_token":"codex-access","expires_in":600,"id_token":"{{idToken}}"}""",
            now);
        Check.Equal("codex-access", tokens.AccessToken);
        Check.Equal(string.Empty, tokens.RefreshToken);
        Check.Equal(accountId, tokens.AccountId);
        Check.Equal(now.AddMinutes(10), tokens.ExpiresAt);

        var url = CodexOAuthFlow.AuthorizeUrl(
            new Pkce("verifier", "challenge"),
            "state",
            CodexOAuthFlow.RedirectUri(1455));
        Check.True(url.Contains(
            "codex_cli_simplified_flow=true",
            StringComparison.Ordinal));
        Check.True(url.Contains(
            "originator=codex_cli_rs",
            StringComparison.Ordinal));
    }

    private static void FormattingPreservesRemainingSemantics()
    {
        Check.Equal("29%", UsageFormatting.RemainingPercent(29.9));
        Check.Equal("99%", UsageFormatting.RemainingPercent(99.9));
        Check.Equal("100%", UsageFormatting.RemainingPercent(200));
        Check.Equal("0%", UsageFormatting.RemainingPercent(-1));

        var fetchedAt = DateTimeOffset.Parse("2026-07-27T00:00:00Z", Invariant);
        var claude = AgentState.Fresh(
            new UsageSnapshot(
                [new UsageWindow("5-hour", 24, null)],
                fetchedAt));
        var codex = AgentState.Fresh(
            new UsageSnapshot(
                [new UsageWindow("5-hour", 12, null)],
                fetchedAt));
        Check.Equal(
            "C: 76% X: 88%",
            UsageFormatting.TraySummary(
            [
                (AgentRegistry.Get(AgentId.ClaudeCode), claude),
                (AgentRegistry.Get(AgentId.Codex), codex),
            ]));
        Check.Equal(
            "76%",
            UsageFormatting.TraySummary(
            [
                (AgentRegistry.Get(AgentId.ClaudeCode), claude),
                (AgentRegistry.Get(AgentId.Codex), AgentState.SignedOut),
            ]));
        Check.Equal(
            "—",
            UsageFormatting.TraySummary(
            [
                (AgentRegistry.Get(AgentId.ClaudeCode), AgentState.SignedOut),
                (AgentRegistry.Get(AgentId.Codex), AgentState.SignedOut),
            ]));

        var now = DateTimeOffset.Parse("2026-07-27T00:00:00Z", Invariant);
        Check.Equal(
            "2d 3h",
            UsageFormatting.CompactDuration(now.AddHours(51), now));
        Check.Equal(
            "4h 12m",
            UsageFormatting.CompactDuration(now.AddHours(4).AddMinutes(12), now));
        Check.Equal(
            "resets now",
            UsageFormatting.ResetCountdown(now.AddSeconds(-1), now));
        Check.Equal(
            "2h 5m ago",
            UsageFormatting.RelativeAge(now.AddHours(-2).AddMinutes(-5), now));
        Check.Equal("1.2M", UsageFormatting.CompactTokenCount(1_240_000));

        var usage = new TokenUsage
        {
            InputTokens = 10,
            OutputTokens = 5,
            CacheCreationTokens = 3,
            CacheReadTokens = 2,
            ResponseCount = 1,
        };
        Check.Equal(18L, usage.BillableTokens);
        Check.Equal(18L, usage.TotalTokens);
        Check.Equal(20L, usage.MeteredTokens);
        Check.True(UsageFormatting.TokenBreakdown(usage).Contains(
            "cache read",
            StringComparison.Ordinal));
    }

    private static void TokenMetricExcludesCacheReads()
    {
        var usage = new TokenUsage
        {
            InputTokens = 10,
            OutputTokens = 5,
            CacheWriteTokens = 3,
            CacheWrite1HourTokens = 7,
            CacheReadTokens = 100,
            ResponseCount = 1,
        };

        Check.Equal(25L, usage.BillableTokens);
        Check.Equal(25L, usage.TotalTokens);
        Check.Equal(125L, usage.MeteredTokens);
        Check.Equal(25L, usage.Breakdown.TokenMetricTotal);
        Check.Equal(125L, usage.Breakdown.MeteredTokenTotal);
    }

    private static void TokenOdometerKindsIncludeCacheReads()
    {
        var usage = new TokenUsage
        {
            InputTokens = 11,
            OutputTokens = 22,
            CacheWriteTokens = 13,
            CacheWrite1HourTokens = 20,
            CacheReadTokens = 44,
        };

        Check.Equal(11L, usage.Amount(TokenKind.DirectInput));
        Check.Equal(22L, usage.Amount(TokenKind.Output));
        Check.Equal(33L, usage.Amount(TokenKind.CacheWrite));
        Check.Equal(44L, usage.Amount(TokenKind.CacheRead));
        Check.Equal(66L, usage.BillableTokens);
        Check.Equal(110L, usage.OdometerTokens);
        Check.Equal("Today", TokenRange.Today.Label());
        Check.Equal("7 days", TokenRange.SevenDays.Label());
        Check.Equal("30 days", TokenRange.ThirtyDays.Label());

        var namedUnknown = ModelName.Named("unknown");
        Check.False(namedUnknown.IsUnattributed);
        Check.True(ModelName.Unattributed.IsUnattributed);
        Check.False(namedUnknown == ModelName.Unattributed);
    }

    private static void TokenSelectionsDriveTotalsAndFormatting()
    {
        var usage = new TokenUsage
        {
            InputTokens = 11,
            OutputTokens = 22,
            CacheWriteTokens = 13,
            CacheWrite1HourTokens = 20,
            CacheReadTokens = 44,
        };
        var inputAndCacheWrite =
            TokenKindSelection.DirectInput | TokenKindSelection.CacheWrite;

        Check.Equal(110L, usage.SelectedTotal(TokenKindSelection.All));
        Check.Equal(44L, usage.SelectedTotal(inputAndCacheWrite));
        Check.Equal(0L, usage.SelectedTotal(TokenKindSelection.None));
        Check.Equal(44L, usage.Breakdown.SelectedTotal(inputAndCacheWrite));
        Check.True(inputAndCacheWrite.Includes(TokenKind.DirectInput));
        Check.True(inputAndCacheWrite.Includes(TokenKind.CacheWrite));
        Check.False(inputAndCacheWrite.Includes(TokenKind.Output));
        Check.Equal(
            "IN + C·W",
            UsageFormatting.TokenKindSelectionLabel(inputAndCacheWrite));
        Check.Equal(
            "All",
            UsageFormatting.TokenKindSelectionLabel(TokenKindSelection.All));

        Check.Equal(
            "25",
            UsageFormatting.TokenCell(
                25,
                100,
                TokenValueDisplayMode.Value));
        Check.Equal(
            "25%",
            UsageFormatting.TokenCell(
                25,
                100,
                TokenValueDisplayMode.Percentage));
        Check.Equal(
            "25\n(25%)",
            UsageFormatting.TokenCell(
                25,
                100,
                TokenValueDisplayMode.ValueAndPercentage));
        Check.Equal(
            "12.5%",
            UsageFormatting.TokenCell(
                1,
                8,
                TokenValueDisplayMode.Percentage));
        foreach (var mode in Enum.GetValues<TokenValueDisplayMode>())
        {
            Check.Equal("–", UsageFormatting.TokenCell(0, 100, mode));
        }

        Check.Equal(
            "T: 44 · 7 days",
            UsageFormatting.TokenStatusSummary(
                usage,
                TokenRange.SevenDays,
                TodayMetricMode.Token,
                inputAndCacheWrite));
        Check.Equal(
            "T: 0 · Today",
            UsageFormatting.TokenStatusSummary(
                usage,
                TokenRange.Today,
                TodayMetricMode.Token,
                TokenKindSelection.CacheRead));

        var attributed = new TokenUsage();
        attributed.AddAttributed(
            AgentId.Codex,
            "gpt-5.6-sol",
            new TokenUsage
            {
                InputTokens = 1_000_000,
                OutputTokens = 1_000_000,
                ResponseCount = 1,
            });
        Check.Equal(
            "API: $5.00 · 30 days",
            UsageFormatting.TokenStatusSummary(
                attributed,
                TokenRange.ThirtyDays,
                TodayMetricMode.Usage,
                TokenKindSelection.DirectInput,
                new DateOnly(2026, 7, 27)));
    }

    private static void ApiPricingCatalogPricesKnownModelsAndDisclosesUnknown()
    {
        const long million = 1_000_000;
        var oneMillionOfEachCategory = new TokenUsage
        {
            InputTokens = million,
            OutputTokens = million,
            CacheWriteTokens = million,
            CacheWrite1HourTokens = million,
            CacheReadTokens = million,
            ResponseCount = 1,
        };
        var usage = new TokenUsage();
        usage.AddAttributed(
            AgentId.Codex,
            "gpt-5.6-sol-2026-07-27",
            oneMillionOfEachCategory);
        usage.AddAttributed(
            AgentId.ClaudeCode,
            "claude-sonnet-5-20260701",
            oneMillionOfEachCategory);
        usage.AddAttributed(
            AgentId.Codex,
            "future-unknown-model",
            new TokenUsage
            {
                InputTokens = 10,
                OutputTokens = 5,
                CacheReadTokens = 2,
                ResponseCount = 1,
            });

        var estimate = ApiPricingCatalog.Estimate(
            usage,
            new DateOnly(2026, 8, 31));
        Check.Equal(66.70m, estimate.CostUsd);
        Check.Equal(10_000_000L, estimate.PricedTokens);
        Check.Equal(17L, estimate.UnpricedTokens);
        Check.True(estimate.IsAvailable);
        Check.True(estimate.IsPartial);
        Check.Equal(1, estimate.UnpricedModels.Count);
        Check.Equal(
            "Codex: future-unknown-model",
            estimate.UnpricedModels[0]);

        Check.True(ApiPricingCatalog.TryResolve(
            AgentId.Codex,
            "gpt-5.6-sol",
            new DateOnly(2026, 7, 27),
            out var gpt56));
        Check.Equal(5m, gpt56.RawInput);
        Check.Equal(6.25m, gpt56.CacheWrite);
        Check.Equal(0.50m, gpt56.CacheRead);
        Check.Equal(30m, gpt56.Output);

        Check.True(ApiPricingCatalog.TryResolve(
            AgentId.ClaudeCode,
            "claude-sonnet-5",
            new DateOnly(2026, 9, 1),
            out var sonnetAfterIntro));
        Check.Equal(3m, sonnetAfterIntro.RawInput);
        Check.Equal(3.75m, sonnetAfterIntro.CacheWrite);
        Check.Equal(6m, sonnetAfterIntro.CacheWrite1Hour);
        Check.Equal(0.30m, sonnetAfterIntro.CacheRead);
        Check.Equal(15m, sonnetAfterIntro.Output);
        Check.False(ApiPricingCatalog.TryResolve(
            AgentId.Codex,
            "gpt-5.6-sol-future-tier",
            new DateOnly(2026, 7, 27),
            out _));
    }

    private static void ApiPricingCatalogFiltersSelectedKinds()
    {
        const long million = 1_000_000;
        var oneMillionOfEachCategory = new TokenUsage
        {
            InputTokens = million,
            OutputTokens = million,
            CacheWriteTokens = million,
            CacheWrite1HourTokens = million,
            CacheReadTokens = million,
            ResponseCount = 1,
        };
        var usage = new TokenUsage();
        usage.AddAttributed(
            AgentId.Codex,
            "gpt-5.6-sol",
            oneMillionOfEachCategory);
        usage.AddAttributed(
            AgentId.ClaudeCode,
            "claude-sonnet-5",
            oneMillionOfEachCategory);
        usage.AddAttributed(
            AgentId.Codex,
            "future-unknown-model",
            new TokenUsage
            {
                InputTokens = 10,
                OutputTokens = 5,
                CacheReadTokens = 2,
                ResponseCount = 1,
            });
        var pricingDate = new DateOnly(2026, 8, 31);

        var directInput = ApiPricingCatalog.Estimate(
            usage,
            pricingDate,
            TokenKindSelection.DirectInput);
        Check.Equal(7m, directInput.CostUsd);
        Check.Equal(2 * million, directInput.PricedTokens);
        Check.Equal(10L, directInput.UnpricedTokens);
        Check.True(directInput.IsPartial);

        var cacheWrite = ApiPricingCatalog.Estimate(
            usage,
            pricingDate,
            TokenKindSelection.CacheWrite);
        Check.Equal(19m, cacheWrite.CostUsd);
        Check.Equal(4 * million, cacheWrite.PricedTokens);
        Check.Equal(0L, cacheWrite.UnpricedTokens);
        Check.False(cacheWrite.IsPartial);
        Check.Equal(0, cacheWrite.UnpricedModels.Count);

        var cacheRead = ApiPricingCatalog.Estimate(
            usage,
            pricingDate,
            TokenKindSelection.CacheRead);
        Check.Equal(0.70m, cacheRead.CostUsd);
        Check.Equal(2 * million, cacheRead.PricedTokens);
        Check.Equal(2L, cacheRead.UnpricedTokens);

        var inputAndOutput = ApiPricingCatalog.Estimate(
            usage,
            pricingDate,
            TokenKindSelection.DirectInput | TokenKindSelection.Output);
        Check.Equal(47m, inputAndOutput.CostUsd);
        Check.Equal(4 * million, inputAndOutput.PricedTokens);
        Check.Equal(15L, inputAndOutput.UnpricedTokens);

        var none = ApiPricingCatalog.Estimate(
            usage,
            pricingDate,
            TokenKindSelection.None);
        Check.Equal(0m, none.CostUsd);
        Check.Equal(0L, none.PricedTokens);
        Check.Equal(0L, none.UnpricedTokens);
        Check.False(none.IsAvailable);
        Check.Equal(0, none.UnpricedModels.Count);
    }

    private static void RefreshPolicyAppliesCadenceAndBackoff()
    {
        var now = DateTimeOffset.Parse("2026-07-27T00:00:00Z", Invariant);

        var first = RefreshPolicy.Decide(
            RefreshTrigger.Timer,
            null,
            now,
            0);
        Check.True(first.ShouldFetch);
        Check.Equal(TimeSpan.FromMinutes(30), first.NextInterval);

        var recent = RefreshPolicy.Decide(
            RefreshTrigger.Timer,
            now.AddMinutes(-29),
            now,
            0);
        Check.False(recent.ShouldFetch);

        var failedOnce = RefreshPolicy.Decide(
            RefreshTrigger.Timer,
            now.AddMinutes(-31),
            now,
            1);
        Check.False(failedOnce.ShouldFetch);
        Check.Equal(TimeSpan.FromHours(1), failedOnce.NextInterval);

        foreach (var trigger in new[]
                 {
                     RefreshTrigger.Wake,
                     RefreshTrigger.PopoverOpen,
                     RefreshTrigger.Manual,
                 })
        {
            Check.True(RefreshPolicy.Decide(
                trigger,
                now,
                now,
                3).ShouldFetch);
        }

        Check.Equal(
            TimeSpan.FromHours(6),
            RefreshPolicy.Decide(
                RefreshTrigger.Timer,
                now,
                now,
                20).NextInterval);
    }

    private static void StateReducerDisclosesStaleData()
    {
        var state = AgentStateReducer.Reduce(
            AgentState.SignedOut,
            new AgentEvent(AgentEventKind.LoadingStarted));
        Check.Equal(AgentStateKind.Loading, state.Kind);

        var failedWithoutData = AgentStateReducer.Reduce(
            state,
            new AgentEvent(AgentEventKind.FetchFailed));
        Check.Equal(AgentStateKind.Loading, failedWithoutData.Kind);

        var snapshot = new UsageSnapshot(
            [new UsageWindow("5-hour", 24, null)],
            DateTimeOffset.Parse("2026-07-27T00:00:00Z", Invariant));
        state = AgentStateReducer.Reduce(
            state,
            new AgentEvent(AgentEventKind.FetchSucceeded, snapshot));
        Check.Equal(AgentStateKind.Fresh, state.Kind);
        Check.Equal(snapshot, state.Snapshot);

        var loadingOverData = AgentStateReducer.Reduce(
            state,
            new AgentEvent(AgentEventKind.LoadingStarted));
        Check.Equal(state, loadingOverData);

        state = AgentStateReducer.Reduce(
            state,
            new AgentEvent(AgentEventKind.FetchFailed));
        Check.Equal(AgentStateKind.StaleDisclosed, state.Kind);
        Check.Equal(snapshot, state.Snapshot);

        state = AgentStateReducer.Reduce(
            state,
            new AgentEvent(AgentEventKind.SignedOut));
        Check.Equal(AgentStateKind.SignedOut, state.Kind);
        Check.True(state.Snapshot is null);
    }

    private static async Task TokenCacheSignOutWinsInFlightRefresh()
    {
        var now = DateTimeOffset.Parse("2026-07-27T00:00:00Z", Invariant);
        var store = new MemoryTokenStore
        {
            Value = new OAuthTokens(
                "expired-access",
                "refresh",
                now.AddMinutes(-1)),
        };
        var refreshStarted = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var releaseRefresh = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var cache = new AgentTokenCache(
            store,
            async (_, cancellationToken) =>
            {
                refreshStarted.SetResult();
                await releaseRefresh.Task.WaitAsync(cancellationToken)
                    .ConfigureAwait(false);
                return new OAuthTokens(
                    "refreshed-access",
                    "refreshed-refresh",
                    now.AddHours(1));
            },
            () => now);

        var refresh = cache.ValidAccessTokenAsync();
        await refreshStarted.Task.ConfigureAwait(false);
        cache.SignOut();
        releaseRefresh.SetResult();

        var rejected = false;
        try
        {
            _ = await refresh.ConfigureAwait(false);
        }
        catch (UsageException)
        {
            rejected = true;
        }

        Check.True(rejected, "An in-flight refresh survived sign-out.");
        Check.True(store.Value is null);
        Check.False(cache.IsSignedIn);
    }

    private static async Task TokenCacheDoesNotPublishFailedAdoption()
    {
        var store = new MemoryTokenStore { FailSaves = true };
        var cache = new AgentTokenCache(
            store,
            (_, _) => Task.FromResult(
                new OAuthTokens(
                    "unused",
                    "unused",
                    DateTimeOffset.Now.AddHours(1))));
        var failed = false;
        try
        {
            await cache.AdoptAsync(
                    new OAuthTokens(
                        "access",
                        "refresh",
                        DateTimeOffset.Now.AddHours(1)))
                .ConfigureAwait(false);
        }
        catch (IOException)
        {
            failed = true;
        }

        Check.True(failed);
        Check.False(cache.IsSignedIn);
        Check.True(store.Value is null);
    }

    private static async Task OAuthHttpClientBuildsExpectedRequestsAndSurfacesErrors()
    {
        var handler = new RecordingHandler();
        handler.Enqueue(
            HttpStatusCode.OK,
            """{"access_token":"claude-access","refresh_token":"claude-refresh","expires_in":3600}""");
        handler.Enqueue(
            HttpStatusCode.OK,
            """{"access_token":"codex-access","refresh_token":"codex-refresh","expires_in":3600}""");
        handler.Enqueue(HttpStatusCode.Unauthorized, """{"error":"denied"}""");
        using var httpClient = new HttpClient(handler);
        var oauth = new OAuthHttpClient(httpClient);

        _ = await oauth.ExchangeClaudeCodeAsync(
                "approval",
                "verifier",
                "state")
            .ConfigureAwait(false);
        var claude = handler.Requests[0];
        Check.Equal(HttpMethod.Post, claude.Method);
        Check.Equal(ClaudeOAuthFlow.TokenEndpoint, claude.Uri.ToString());
        Check.Equal("application/json", claude.ContentType);
        using (var body = JsonDocument.Parse(claude.Body))
        {
            Check.Equal(
                "authorization_code",
                body.RootElement.GetProperty("grant_type").GetString());
            Check.Equal(
                "verifier",
                body.RootElement.GetProperty("code_verifier").GetString());
            Check.Equal(
                "state",
                body.RootElement.GetProperty("state").GetString());
        }

        _ = await oauth.ExchangeCodexAsync(
                "approval",
                "verifier",
                CodexOAuthFlow.RedirectUri(1455))
            .ConfigureAwait(false);
        var codex = handler.Requests[1];
        Check.Equal("application/x-www-form-urlencoded", codex.ContentType);
        Check.True(codex.Body.Contains(
            "grant_type=authorization_code",
            StringComparison.Ordinal));
        Check.True(codex.Body.Contains(
            $"client_id={CodexOAuthFlow.ClientId}",
            StringComparison.Ordinal));
        Check.True(codex.Body.Contains(
            "code_verifier=verifier",
            StringComparison.Ordinal));

        var surfaced = false;
        try
        {
            _ = await oauth.RefreshClaudeCodeAsync("refresh")
                .ConfigureAwait(false);
        }
        catch (UsageException exception)
        {
            surfaced = exception.Message.Contains(
                "HTTP 401",
                StringComparison.Ordinal);
        }

        Check.True(surfaced, "OAuth HTTP errors were not surfaced.");
    }

    private static async Task UsageProvidersSendExpectedHeadersAndRejectEmptyWindows()
    {
        var handler = new RecordingHandler();
        handler.Enqueue(
            HttpStatusCode.OK,
            """{"five_hour":{"utilization":25,"resets_at":null}}""");
        handler.Enqueue(
            HttpStatusCode.OK,
            """{"rate_limit":{"primary_window":{"used_percent":40,"reset_at":0}}}""");
        handler.Enqueue(HttpStatusCode.OK, "{}");
        handler.Enqueue(
            HttpStatusCode.OK,
            """{"plan_type":"pro","rate_limit":null}""");
        using var httpClient = new HttpClient(handler);

        var claude = new ClaudeUsageProvider(
            httpClient,
            _ => Task.FromResult("claude-token"));
        Check.Equal(
            1,
            (await claude.FetchUsageAsync().ConfigureAwait(false)).Count);
        var claudeRequest = handler.Requests[0];
        Check.Equal("Bearer claude-token", claudeRequest.Header("Authorization"));
        Check.True(claudeRequest.Header("Accept").Contains(
            "application/json",
            StringComparison.Ordinal));

        var codex = new CodexUsageProvider(
            httpClient,
            _ => Task.FromResult("codex-token"),
            () => "account-123");
        Check.Equal(
            1,
            (await codex.FetchUsageAsync().ConfigureAwait(false)).Count);
        var codexRequest = handler.Requests[1];
        Check.Equal("Bearer codex-token", codexRequest.Header("Authorization"));
        Check.Equal("account-123", codexRequest.Header("ChatGPT-Account-Id"));
        Check.True(codexRequest.Header("User-Agent").Contains(
            "TokenStats-Windows/0.1",
            StringComparison.Ordinal));

        var rejectedEmpty = false;
        try
        {
            _ = await claude.FetchUsageAsync().ConfigureAwait(false);
        }
        catch (UsageException)
        {
            rejectedEmpty = true;
        }

        Check.True(rejectedEmpty, "An empty usage payload was accepted.");
        Check.Equal(
            0,
            (await codex.FetchUsageAsync().ConfigureAwait(false)).Count);
    }

    private static async Task ClaudeTranscriptsDeduplicateByMessageIdAndUseLocalDay()
    {
        using var temp = new TemporaryDirectory();
        var timeZone = TimeZoneInfo.CreateCustomTimeZone(
            "TokenStats-Test-UTC+08",
            TimeSpan.FromHours(8),
            "TokenStats Test UTC+08",
            "TokenStats Test UTC+08");
        var now = DateTimeOffset.Parse(
            "2026-07-27T01:00:00+08:00",
            Invariant);
        var transcript = Path.Combine(temp.Path, "claude.jsonl");

        var current = ClaudeLine(
            "message-current",
            "2026-07-26T16:30:00.123Z",
            input: 10,
            output: 5,
            cacheCreation: 3,
            cacheRead: 2);
        var duplicate = ClaudeLine(
            "message-current",
            "2026-07-26T16:31:00Z",
            input: 999,
            output: 999,
            cacheCreation: 999,
            cacheRead: 999);
        var yesterday = ClaudeLine(
            "message-yesterday",
            "2026-07-26T15:30:00Z",
            input: 20,
            output: 4,
            cacheCreation: 0,
            cacheRead: 1);
        File.WriteAllText(
            transcript,
            string.Join('\n', current, duplicate, yesterday) + "\n");
        File.SetLastWriteTimeUtc(transcript, now.UtcDateTime);

        var reader = new TranscriptTokenReader(timeZone);
        var today = Check.NotNull(
            await reader.TodayUsageAsync(temp.Path, now).ConfigureAwait(false));
        Check.Equal(1, today.ResponseCount);
        Check.Equal(10L, today.InputTokens);
        Check.Equal(5L, today.OutputTokens);
        Check.Equal(3L, today.CacheCreationTokens);
        Check.Equal(2L, today.CacheReadTokens);
        Check.Equal(18L, today.TotalTokens);
        Check.Equal(20L, today.MeteredTokens);

        var all = Check.NotNull(reader.UsageForTranscript(transcript));
        Check.Equal(2, all.ResponseCount);
        Check.Equal(30L, all.InputTokens);
        Check.Equal(9L, all.OutputTokens);
        Check.Equal(3L, all.CacheCreationTokens);
        Check.Equal(3L, all.CacheReadTokens);
    }

    private static async Task ClaudeTranscriptsCaptureModelAndCacheWriteDurations()
    {
        using var temp = new TemporaryDirectory();
        var now = DateTimeOffset.Parse("2026-07-27T12:00:00Z", Invariant);
        var transcript = Path.Combine(temp.Path, "claude-model.jsonl");
        File.WriteAllText(
            transcript,
            string.Join(
                '\n',
                ClaudeLine(
                    "model-response",
                    "2026-07-27T10:00:00Z",
                    input: 10,
                    output: 5,
                    cacheCreation: 30,
                    cacheRead: 2,
                    model: "claude-sonnet-5-20260701",
                    cacheWrite5Minute: 10,
                    cacheWrite1Hour: 20),
                ClaudeLine(
                    "<synthetic>",
                    "2026-07-27T10:01:00Z",
                    input: 0,
                    output: 0,
                    model: "synthetic")) +
            "\n");
        File.SetLastWriteTimeUtc(transcript, now.UtcDateTime);

        var reader = new TranscriptTokenReader(TimeZoneInfo.Utc);
        var usage = Check.NotNull(
            await reader.TodayUsageAsync(temp.Path, now).ConfigureAwait(false));
        Check.Equal(10L, usage.InputTokens);
        Check.Equal(5L, usage.OutputTokens);
        Check.Equal(10L, usage.CacheWriteTokens);
        Check.Equal(20L, usage.CacheWrite1HourTokens);
        Check.Equal(2L, usage.CacheReadTokens);
        Check.Equal(45L, usage.TotalTokens);
        Check.Equal(47L, usage.MeteredTokens);

        Check.Equal(1, usage.ModelUsage.Count);
        var attributed = usage.ModelUsage[0];
        Check.Equal(AgentId.ClaudeCode, attributed.AgentId);
        Check.Equal("claude-sonnet-5-20260701", attributed.Model);
        Check.Equal(1, attributed.ResponseCount);
        Check.Equal(10L, attributed.Breakdown.RawInputTokens);
        Check.Equal(10L, attributed.Breakdown.CacheWriteTokens);
        Check.Equal(20L, attributed.Breakdown.CacheWrite1HourTokens);
        Check.Equal(2L, attributed.Breakdown.CacheReadTokens);
        Check.Equal(5L, attributed.Breakdown.OutputTokens);
    }

    private static async Task CodexTranscriptsSplitCachedInputAndScanRecursively()
    {
        using var temp = new TemporaryDirectory();
        var nested = Directory.CreateDirectory(
            Path.Combine(temp.Path, "2026", "07", "27")).FullName;
        var now = DateTimeOffset.Parse("2026-07-27T12:00:00Z", Invariant);
        var transcript = Path.Combine(nested, "rollout.jsonl");

        var first = CodexLine(
            "2026-07-27T10:00:00Z",
            input: 100,
            cachedInput: 40,
            output: 20);
        var cachedExceedsInput = CodexLine(
            "2026-07-27T10:01:00Z",
            input: 105,
            cachedInput: 45,
            output: 22);
        File.WriteAllText(
            transcript,
            string.Join('\n', first, cachedExceedsInput) + "\n");
        File.SetLastWriteTimeUtc(transcript, now.UtcDateTime);
        File.WriteAllText(
            Path.Combine(nested, "ignored.txt"),
            CodexLine("2026-07-27T10:02:00Z", 1000, 0, 1000));

        var reader = new TranscriptTokenReader(TimeZoneInfo.Utc);
        var usage = Check.NotNull(
            await reader.TodayUsageAsync(temp.Path, now).ConfigureAwait(false));
        Check.Equal(2, usage.ResponseCount);
        Check.Equal(60L, usage.InputTokens);
        Check.Equal(45L, usage.CacheReadTokens);
        Check.Equal(22L, usage.OutputTokens);
        Check.Equal(82L, usage.TotalTokens);
        Check.Equal(127L, usage.MeteredTokens);
    }

    private static async Task CodexTranscriptsTrackModelsCacheWritesAndUnknown()
    {
        using var temp = new TemporaryDirectory();
        var now = DateTimeOffset.Parse("2026-07-27T12:00:00Z", Invariant);
        var transcript = Path.Combine(temp.Path, "rollout-models.jsonl");
        File.WriteAllText(
            transcript,
            string.Join(
                '\n',
                CodexLine(
                    "2026-07-27T09:59:00Z",
                    input: 10,
                    cachedInput: 2,
                    output: 3,
                    cacheWrite: 1),
                CodexTurnContextLine("gpt-5.6-sol"),
                CodexLine(
                    "2026-07-27T10:00:00Z",
                    input: 110,
                    cachedInput: 32,
                    output: 23,
                    cacheWrite: 11),
                CodexTurnContextLine("gpt-5.6-terra"),
                CodexLine(
                    "2026-07-27T10:01:00Z",
                    input: 160,
                    cachedInput: 37,
                    output: 33,
                    cacheWrite: 16)) +
            "\n");
        File.SetLastWriteTimeUtc(transcript, now.UtcDateTime);

        var reader = new TranscriptTokenReader(TimeZoneInfo.Utc);
        var usage = Check.NotNull(
            await reader.TodayUsageAsync(temp.Path, now).ConfigureAwait(false));
        Check.Equal(3, usage.ResponseCount);
        Check.Equal(107L, usage.InputTokens);
        Check.Equal(33L, usage.OutputTokens);
        Check.Equal(16L, usage.CacheWriteTokens);
        Check.Equal(37L, usage.CacheReadTokens);
        Check.Equal(156L, usage.TotalTokens);
        Check.Equal(193L, usage.MeteredTokens);
        Check.Equal(2, usage.ModelUsage.Count);

        var sol = usage.ModelUsage.Single(
            item => item.Model == "gpt-5.6-sol");
        Check.Equal(67L, sol.Breakdown.RawInputTokens);
        Check.Equal(11L, sol.Breakdown.CacheWriteTokens);
        Check.Equal(32L, sol.Breakdown.CacheReadTokens);
        Check.Equal(23L, sol.Breakdown.OutputTokens);

        var terra = usage.ModelUsage.Single(
            item => item.Model == "gpt-5.6-terra");
        Check.Equal(40L, terra.Breakdown.RawInputTokens);
        Check.Equal(5L, terra.Breakdown.CacheWriteTokens);
        Check.Equal(5L, terra.Breakdown.CacheReadTokens);
        Check.Equal(10L, terra.Breakdown.OutputTokens);
    }

    private static Task CodexRunningTotalsDeduplicateAdvanceAndReset()
    {
        using var advancing = new TemporaryDirectory();
        var advancingTranscript = Path.Combine(
            advancing.Path,
            "rollout-running.jsonl");
        File.WriteAllText(
            advancingTranscript,
            string.Join(
                '\n',
                CodexLine(
                    "2026-07-27T10:00:00Z",
                    input: 1000,
                    cachedInput: 400,
                    output: 100),
                CodexLine(
                    "2026-07-27T10:00:01Z",
                    input: 1000,
                    cachedInput: 400,
                    output: 100),
                CodexLine(
                    "2026-07-27T10:01:00Z",
                    input: 1500,
                    cachedInput: 600,
                    output: 250)) +
            "\n");

        var reader = new TranscriptTokenReader(TimeZoneInfo.Utc);
        var advanced = Check.NotNull(
            reader.UsageForTranscript(advancingTranscript));
        Check.Equal(2, advanced.ResponseCount);
        Check.Equal(900L, advanced.InputTokens);
        Check.Equal(600L, advanced.CacheReadTokens);
        Check.Equal(250L, advanced.OutputTokens);
        Check.Equal(1750L, advanced.OdometerTokens);

        using var resetting = new TemporaryDirectory();
        var resettingTranscript = Path.Combine(
            resetting.Path,
            "rollout-reset.jsonl");
        File.WriteAllText(
            resettingTranscript,
            string.Join(
                '\n',
                CodexLine(
                    "2026-07-27T10:00:00Z",
                    input: 1000,
                    cachedInput: 400,
                    output: 100),
                CodexLine(
                    "2026-07-27T10:01:00Z",
                    input: 200,
                    cachedInput: 50,
                    output: 20),
                CodexLine(
                    "2026-07-27T10:02:00Z",
                    input: 500,
                    cachedInput: 100,
                    output: 60)) +
            "\n");

        var reset = Check.NotNull(
            reader.UsageForTranscript(resettingTranscript));
        Check.Equal(2, reset.ResponseCount);
        Check.Equal(850L, reset.InputTokens);
        Check.Equal(450L, reset.CacheReadTokens);
        Check.Equal(140L, reset.OutputTokens);
        Check.Equal(1440L, reset.OdometerTokens);
        return Task.CompletedTask;
    }

    private static Task CodexOpeningBaselineExcludesInheritedHead()
    {
        using var temp = new TemporaryDirectory();
        var transcript = Path.Combine(temp.Path, "rollout-resumed.jsonl");
        File.WriteAllText(
            transcript,
            CodexLine(
                "2026-07-27T10:00:00Z",
                input: 1000,
                cachedInput: 400,
                output: 100,
                lastInput: 200,
                lastCachedInput: 80,
                lastOutput: 20) +
            "\n");

        var reader = new TranscriptTokenReader(TimeZoneInfo.Utc);
        var usage = Check.NotNull(reader.UsageForTranscript(transcript));
        Check.Equal(1, usage.ResponseCount);
        Check.Equal(120L, usage.InputTokens);
        Check.Equal(80L, usage.CacheReadTokens);
        Check.Equal(20L, usage.OutputTokens);
        Check.Equal(220L, usage.OdometerTokens);
        return Task.CompletedTask;
    }

    private static async Task CodexModelAttributionBackfillsAndReadsThreadSettings()
    {
        using var temp = new TemporaryDirectory();
        var now = DateTimeOffset.Parse("2026-07-27T12:00:00Z", Invariant);
        var attributedTranscript = Path.Combine(
            temp.Path,
            "rollout-attributed.jsonl");
        File.WriteAllText(
            attributedTranscript,
            string.Join(
                '\n',
                CodexLine(
                    "2026-07-27T10:00:00Z",
                    input: 100,
                    cachedInput: 20,
                    output: 10),
                CodexThreadSettingsLine("gpt-5.6-sol"),
                CodexLine(
                    "2026-07-27T10:01:00Z",
                    input: 200,
                    cachedInput: 50,
                    output: 30),
                CodexTurnContextLine("unknown"),
                CodexLine(
                    "2026-07-27T10:02:00Z",
                    input: 250,
                    cachedInput: 60,
                    output: 40)) +
            "\n");
        File.SetLastWriteTimeUtc(attributedTranscript, now.UtcDateTime);

        var unattributedTranscript = Path.Combine(
            temp.Path,
            "rollout-unattributed.jsonl");
        File.WriteAllText(
            unattributedTranscript,
            CodexLine(
                "2026-07-27T11:00:00Z",
                input: 10,
                cachedInput: 2,
                output: 3) +
            "\n");
        File.SetLastWriteTimeUtc(unattributedTranscript, now.UtcDateTime);

        var reader = new TranscriptTokenReader(TimeZoneInfo.Utc);
        var usage = Check.NotNull(
            await reader.TodayUsageAsync(temp.Path, now).ConfigureAwait(false));

        var sol = usage.ModelUsage.Single(
            item => item.Model == "gpt-5.6-sol");
        Check.Equal(150L, sol.Breakdown.RawInputTokens);
        Check.Equal(50L, sol.Breakdown.CacheReadTokens);
        Check.Equal(30L, sol.Breakdown.OutputTokens);

        var namedUnknown = usage.ModelUsage.Single(
            item => item.Model == "unknown");
        Check.False(namedUnknown.Name.IsUnattributed);
        Check.Equal(40L, namedUnknown.Breakdown.RawInputTokens);
        Check.Equal(10L, namedUnknown.Breakdown.CacheReadTokens);
        Check.Equal(10L, namedUnknown.Breakdown.OutputTokens);

        var unattributed = usage.ModelUsage.Single(
            item => item.Name.IsUnattributed);
        Check.True(unattributed.Model is null);
        Check.Equal(8L, unattributed.Breakdown.RawInputTokens);
        Check.Equal(2L, unattributed.Breakdown.CacheReadTokens);
        Check.Equal(3L, unattributed.Breakdown.OutputTokens);
    }

    private static Task CodexTranscriptRetainsModelAcrossIncrementalAppends()
    {
        using var temp = new TemporaryDirectory();
        var transcript = Path.Combine(temp.Path, "rollout-incremental-model.jsonl");
        var reader = new TranscriptTokenReader(TimeZoneInfo.Utc);
        File.WriteAllText(
            transcript,
            CodexTurnContextLine("GPT-5.6-SOL") + "\n");
        Check.True(reader.UsageForTranscript(transcript) is null);

        File.AppendAllText(
            transcript,
            CodexLine(
                "2026-07-27T10:00:00Z",
                input: 100,
                cachedInput: 30,
                output: 20,
                cacheWrite: 10) +
            "\n");
        var attributed = Check.NotNull(reader.UsageForTranscript(transcript));
        Check.Equal(1, attributed.ModelUsage.Count);
        Check.Equal("GPT-5.6-SOL", attributed.ModelUsage[0].Model);

        File.AppendAllText(
            transcript,
            CodexLine(
                "2026-07-27T10:00:30Z",
                input: 150,
                cachedInput: 40,
                output: 30,
                cacheWrite: 15) +
            "\n");
        var advanced = Check.NotNull(reader.UsageForTranscript(transcript));
        Check.Equal(2, advanced.ResponseCount);
        Check.Equal(95L, advanced.InputTokens);
        Check.Equal(40L, advanced.CacheReadTokens);
        Check.Equal(15L, advanced.CacheWriteTokens);
        Check.Equal(30L, advanced.OutputTokens);
        Check.Equal("GPT-5.6-SOL", advanced.ModelUsage[0].Model);

        // Truncation replaces the parse state, including the remembered model.
        File.WriteAllText(
            transcript,
            CodexLine(
                "2026-07-27T10:01:00Z",
                input: 10,
                cachedInput: 2,
                output: 3) +
            "\n");
        var afterTruncation = Check.NotNull(
            reader.UsageForTranscript(transcript));
        Check.Equal(1, afterTruncation.ModelUsage.Count);
        Check.True(afterTruncation.ModelUsage[0].Model is null);
        return Task.CompletedTask;
    }

    private static async Task TokenRangesUseExactLocalCalendarDays()
    {
        using var temp = new TemporaryDirectory();
        var now = DateTimeOffset.Parse("2026-07-27T12:00:00Z", Invariant);
        var transcript = Path.Combine(temp.Path, "range.jsonl");
        File.WriteAllText(
            transcript,
            string.Join(
                '\n',
                ClaudeLine(
                    "today",
                    "2026-07-27T10:00:00Z",
                    input: 10,
                    output: 0,
                    model: "range-model"),
                ClaudeLine(
                    "day-3",
                    "2026-07-24T10:00:00Z",
                    input: 200,
                    output: 0,
                    model: "range-model"),
                ClaudeLine(
                    "day-9",
                    "2026-07-18T10:00:00Z",
                    input: 3000,
                    output: 0,
                    model: "range-model"),
                ClaudeLine(
                    "day-40",
                    "2026-06-17T10:00:00Z",
                    input: 40000,
                    output: 0,
                    model: "range-model")) +
            "\n");
        File.SetLastWriteTimeUtc(transcript, now.UtcDateTime);

        var reader = new TranscriptTokenReader(TimeZoneInfo.Utc);
        var today = Check.NotNull(
            await reader
                .RangeUsageAsync(
                    temp.Path,
                    TokenRange.Today,
                    now)
                .ConfigureAwait(false));
        var sevenDays = Check.NotNull(
            await reader
                .RangeUsageAsync(
                    temp.Path,
                    TokenRange.SevenDays,
                    now)
                .ConfigureAwait(false));
        var thirtyDays = Check.NotNull(
            await reader
                .RangeUsageAsync(
                    temp.Path,
                    TokenRange.ThirtyDays,
                    now)
                .ConfigureAwait(false));

        Check.Equal(10L, today.OdometerTokens);
        Check.Equal(210L, sevenDays.OdometerTokens);
        Check.Equal(3210L, thirtyDays.OdometerTokens);
        Check.Equal(
            new DateOnly(2026, 7, 27),
            TokenRange.Today.StartDate(now, TimeZoneInfo.Utc));
        Check.Equal(
            new DateOnly(2026, 7, 21),
            TokenRange.SevenDays.StartDate(now, TimeZoneInfo.Utc));
        Check.Equal(
            new DateOnly(2026, 6, 28),
            TokenRange.ThirtyDays.StartDate(now, TimeZoneInfo.Utc));
    }

    private static async Task TranscriptReadsOnlyAppendedBytesAndRetainsPartialLines()
    {
        using var temp = new TemporaryDirectory();
        var now = DateTimeOffset.Parse("2026-07-27T12:00:00Z", Invariant);
        var transcript = Path.Combine(temp.Path, "incremental.jsonl");
        var first = ClaudeLine(
            "first",
            "2026-07-27T10:00:00Z",
            input: 10,
            output: 1);
        var second = ClaudeLine(
            "second",
            "2026-07-27T10:01:00Z",
            input: 20,
            output: 2);
        var split = second.Length / 2;

        File.WriteAllText(
            transcript,
            "[]\nnull\n\"usage\"\n{\"usage\":true}\n" +
            first +
            "\n" +
            second[..split]);
        File.SetLastWriteTimeUtc(transcript, now.UtcDateTime);
        var reader = new TranscriptTokenReader(TimeZoneInfo.Utc);

        var initial = Check.NotNull(reader.TodayUsage(temp.Path, now));
        Check.Equal(1, initial.ResponseCount);
        Check.Equal(10L, initial.InputTokens);

        File.AppendAllText(transcript, second[split..] + "\n");
        File.SetLastWriteTimeUtc(transcript, now.UtcDateTime);
        var appended = Check.NotNull(
            await reader.TodayUsageAsync(temp.Path, now).ConfigureAwait(false));
        Check.Equal(2, appended.ResponseCount);
        Check.Equal(30L, appended.InputTokens);
        Check.Equal(3L, appended.OutputTokens);

        var unchanged = Check.NotNull(reader.TodayUsage(temp.Path, now));
        Check.Equal(2, unchanged.ResponseCount);
        Check.Equal(30L, unchanged.InputTokens);

        var replacement = CodexLine(
            "2026-07-27T11:00:00Z",
            input: 7,
            cachedInput: 2,
            output: 1);
        File.WriteAllText(transcript, replacement + "\n");
        File.SetLastWriteTimeUtc(transcript, now.UtcDateTime);
        var afterTruncation = Check.NotNull(reader.TodayUsage(temp.Path, now));
        Check.Equal(1, afterTruncation.ResponseCount);
        Check.Equal(5L, afterTruncation.InputTokens);
        Check.Equal(2L, afterTruncation.CacheReadTokens);
        Check.Equal(1L, afterTruncation.OutputTokens);

        var sameSizeReplacement = CodexLine(
            "2026-07-27T11:00:00Z",
            input: 9,
            cachedInput: 3,
            output: 2);
        Check.Equal(replacement.Length, sameSizeReplacement.Length);
        File.WriteAllText(transcript, sameSizeReplacement + "\n");
        File.SetLastWriteTimeUtc(
            transcript,
            now.AddMinutes(1).UtcDateTime);
        var afterSameSizeReplacement = Check.NotNull(
            reader.TodayUsage(temp.Path, now));
        Check.Equal(1, afterSameSizeReplacement.ResponseCount);
        Check.Equal(6L, afterSameSizeReplacement.InputTokens);
        Check.Equal(3L, afterSameSizeReplacement.CacheReadTokens);
        Check.Equal(2L, afterSameSizeReplacement.OutputTokens);
    }

    private static string ClaudeLine(
        string id,
        string timestamp,
        long input,
        long output,
        long cacheCreation = 0,
        long cacheRead = 0,
        string? model = null,
        long? cacheWrite5Minute = null,
        long? cacheWrite1Hour = null)
    {
        var usage = new Dictionary<string, object?>
        {
            ["input_tokens"] = input,
            ["output_tokens"] = output,
            ["cache_creation_input_tokens"] = cacheCreation,
            ["cache_read_input_tokens"] = cacheRead,
        };
        if (cacheWrite5Minute.HasValue || cacheWrite1Hour.HasValue)
        {
            usage["cache_creation"] = new Dictionary<string, long>
            {
                ["ephemeral_5m_input_tokens"] = cacheWrite5Minute ?? 0,
                ["ephemeral_1h_input_tokens"] = cacheWrite1Hour ?? 0,
            };
        }

        return JsonSerializer.Serialize(
            new Dictionary<string, object?>
            {
                ["timestamp"] = timestamp,
                ["message"] = new Dictionary<string, object?>
                {
                    ["id"] = id,
                    ["model"] = model,
                    ["usage"] = usage,
                },
            });
    }

    private static string CodexLine(
        string timestamp,
        long input,
        long cachedInput,
        long output,
        long cacheWrite = 0,
        long cacheWrite1Hour = 0,
        long? lastInput = null,
        long? lastCachedInput = null,
        long? lastOutput = null,
        long? lastCacheWrite = null,
        long? lastCacheWrite1Hour = null) =>
        JsonSerializer.Serialize(
            new Dictionary<string, object?>
            {
                ["timestamp"] = timestamp,
                ["type"] = "event_msg",
                ["payload"] = new Dictionary<string, object?>
                {
                    ["type"] = "token_count",
                    ["info"] = new Dictionary<string, object?>
                    {
                        ["total_token_usage"] = new Dictionary<string, long>
                        {
                            ["input_tokens"] = input,
                            ["cached_input_tokens"] = cachedInput,
                            ["cache_write_input_tokens"] = cacheWrite,
                            ["cache_write_1h_input_tokens"] = cacheWrite1Hour,
                            ["output_tokens"] = output,
                        },
                        ["last_token_usage"] = new Dictionary<string, long>
                        {
                            ["input_tokens"] = lastInput ?? input,
                            ["cached_input_tokens"] =
                                lastCachedInput ?? cachedInput,
                            ["cache_write_input_tokens"] =
                                lastCacheWrite ?? cacheWrite,
                            ["cache_write_1h_input_tokens"] =
                                lastCacheWrite1Hour ?? cacheWrite1Hour,
                            ["output_tokens"] = lastOutput ?? output,
                        },
                    },
                },
            });

    private static string CodexTurnContextLine(string? model) =>
        JsonSerializer.Serialize(
            new Dictionary<string, object?>
            {
                ["type"] = "turn_context",
                ["payload"] = new Dictionary<string, object?>
                {
                    ["model"] = model,
                },
            });

    private static string CodexThreadSettingsLine(string? model) =>
        JsonSerializer.Serialize(
            new Dictionary<string, object?>
            {
                ["type"] = "event_msg",
                ["payload"] = new Dictionary<string, object?>
                {
                    ["type"] = "thread_settings_applied",
                    ["thread_settings"] = new Dictionary<string, object?>
                    {
                        ["model"] = model,
                    },
                },
            });

    private sealed record TestCase(string Name, Func<Task> Run);

    private sealed class MemoryTokenStore : ITokenStore
    {
        private readonly object gate = new();

        public OAuthTokens? Value { get; set; }
        public bool FailSaves { get; set; }

        public OAuthTokens? Load()
        {
            lock (gate)
            {
                return Value;
            }
        }

        public void Save(OAuthTokens tokens)
        {
            lock (gate)
            {
                if (FailSaves)
                {
                    throw new IOException("Synthetic token-store failure.");
                }

                Value = tokens;
            }
        }

        public void Clear()
        {
            lock (gate)
            {
                Value = null;
            }
        }
    }

    private sealed record RequestSnapshot(
        HttpMethod Method,
        Uri Uri,
        string? ContentType,
        string Body,
        IReadOnlyDictionary<string, string> Headers)
    {
        public string Header(string name) =>
            Headers.TryGetValue(name, out var value) ? value : string.Empty;
    }

    private sealed class RecordingHandler : HttpMessageHandler
    {
        private readonly Queue<(HttpStatusCode Status, string Body)> responses = [];

        public List<RequestSnapshot> Requests { get; } = [];

        public void Enqueue(HttpStatusCode status, string body) =>
            responses.Enqueue((status, body));

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            if (!responses.TryDequeue(out var response))
            {
                throw new InvalidOperationException(
                    "No synthetic HTTP response was queued.");
            }

            var body = request.Content is null
                ? string.Empty
                : await request.Content
                    .ReadAsStringAsync(cancellationToken)
                    .ConfigureAwait(false);
            var headers = new Dictionary<string, string>(
                StringComparer.OrdinalIgnoreCase);
            foreach (var header in request.Headers)
            {
                headers[header.Key] = string.Join(" ", header.Value);
            }

            if (request.Content is not null)
            {
                foreach (var header in request.Content.Headers)
                {
                    headers[header.Key] = string.Join(" ", header.Value);
                }
            }

            Requests.Add(new RequestSnapshot(
                request.Method,
                request.RequestUri ??
                throw new InvalidOperationException("Synthetic request had no URI."),
                request.Content?.Headers.ContentType?.MediaType,
                body,
                headers));
            return new HttpResponseMessage(response.Status)
            {
                Content = new StringContent(
                    response.Body,
                    Encoding.UTF8,
                    "application/json"),
            };
        }
    }

    private sealed class TemporaryDirectory : IDisposable
    {
        public TemporaryDirectory()
        {
            Path = System.IO.Path.Combine(
                System.IO.Path.GetTempPath(),
                $"TokenStats.Core.Tests-{Guid.NewGuid():N}");
            Directory.CreateDirectory(Path);
        }

        public string Path { get; }

        public void Dispose()
        {
            if (Directory.Exists(Path))
            {
                Directory.Delete(Path, recursive: true);
            }
        }
    }
}

internal static class Check
{
    public static void True(bool condition, string? message = null)
    {
        if (!condition)
        {
            throw new InvalidOperationException(message ?? "Expected true.");
        }
    }

    public static void False(bool condition, string? message = null) =>
        True(!condition, message ?? "Expected false.");

    public static void Equal<T>(T expected, T actual)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            throw new InvalidOperationException(
                $"Expected <{expected}>, got <{actual}>.");
        }
    }

    public static void Near(
        double expected,
        double actual,
        double tolerance = 0.000_001)
    {
        if (Math.Abs(expected - actual) > tolerance)
        {
            throw new InvalidOperationException(
                $"Expected <{expected}>, got <{actual}>.");
        }
    }

    public static T NotNull<T>(T? value)
        where T : class =>
        value ?? throw new InvalidOperationException(
            $"Expected a non-null {typeof(T).Name}.");
}
