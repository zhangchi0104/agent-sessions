using System.Net;
using System.Net.Sockets;
using System.Text;

namespace TokenStats.App.Infrastructure;

public sealed record OAuthCallback(string Code, string State);

public sealed class LoopbackAuthListener : IAsyncDisposable
{
    public const int PreferredPort = 1455;
    public const int FallbackPort = 1457;
    private const int MaximumRequestBytes = 64 * 1024;
    private static readonly TimeSpan DefaultTimeout = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan ConnectionTimeout = TimeSpan.FromSeconds(10);
    private readonly TimeSpan _timeout;
    private TcpListener? _listener;

    public LoopbackAuthListener(TimeSpan? timeout = null)
    {
        _timeout = timeout ?? DefaultTimeout;
    }

    public int Port { get; private set; }

    public Task<int> StartAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (_listener is not null)
        {
            return Task.FromResult(Port);
        }

        _listener = TryStart(PreferredPort) ?? TryStart(FallbackPort) ??
            throw new InvalidOperationException(
                "Codex sign-in needs local port 1455 or 1457, but both are in use.");
        Port = ((IPEndPoint)_listener.LocalEndpoint).Port;
        return Task.FromResult(Port);
    }

    public async Task<OAuthCallback> WaitForCallbackAsync(
        string expectedState,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(expectedState);
        var listener = _listener ??
            throw new InvalidOperationException("The loopback listener has not been started.");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(_timeout);

        while (true)
        {
            TcpClient client;
            try
            {
                client = await listener.AcceptTcpClientAsync(timeout.Token)
                    .ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (
                !cancellationToken.IsCancellationRequested)
            {
                throw new TimeoutException(
                    "Sign-in timed out. Approve in the browser, then try again.");
            }

            using (client)
            {
                using var connectionTimeout =
                    CancellationTokenSource.CreateLinkedTokenSource(timeout.Token);
                connectionTimeout.CancelAfter(ConnectionTimeout);
                string request;
                try
                {
                    request = await ReadRequestAsync(
                            client,
                            connectionTimeout.Token)
                        .ConfigureAwait(false);
                }
                catch (OperationCanceledException) when (
                    !timeout.IsCancellationRequested)
                {
                    continue;
                }
                catch (OperationCanceledException) when (
                    timeout.IsCancellationRequested &&
                    !cancellationToken.IsCancellationRequested)
                {
                    throw new TimeoutException(
                        "Sign-in timed out. Approve in the browser, then try again.");
                }
                catch (InvalidOperationException)
                {
                    await RespondBestEffortAsync(
                            client,
                            FailureHtml,
                            "413 Payload Too Large",
                            timeout.Token)
                        .ConfigureAwait(false);
                    continue;
                }

                var result = ParseRequest(request);
                if (result.Callback is { } callback)
                {
                    if (!string.Equals(
                            callback.State,
                            expectedState,
                            StringComparison.Ordinal))
                    {
                        await RespondBestEffortAsync(
                                client,
                                FailureHtml,
                                "400 Bad Request",
                                timeout.Token)
                            .ConfigureAwait(false);
                        continue;
                    }

                    await RespondBestEffortAsync(
                            client,
                            SuccessHtml,
                            "200 OK",
                            timeout.Token)
                        .ConfigureAwait(false);
                    return callback;
                }

                var expectedError =
                    !string.IsNullOrWhiteSpace(result.Error) &&
                    string.Equals(
                        result.State,
                        expectedState,
                        StringComparison.Ordinal);
                await RespondBestEffortAsync(
                        client,
                        FailureHtml,
                        expectedError ? "400 Bad Request" : "404 Not Found",
                        timeout.Token)
                    .ConfigureAwait(false);
                if (expectedError)
                {
                    throw new InvalidOperationException(result.Error);
                }
            }
        }
    }

    public ValueTask DisposeAsync()
    {
        _listener?.Stop();
        _listener = null;
        return ValueTask.CompletedTask;
    }

    public static (OAuthCallback? Callback, string? Error, string? State)
        ParseRequest(string request)
    {
        var firstLine = request.Split(["\r\n", "\n"], StringSplitOptions.None)
            .FirstOrDefault();
        if (string.IsNullOrWhiteSpace(firstLine))
        {
            return (null, null, null);
        }

        var parts = firstLine.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2 ||
            !string.Equals(parts[0], "GET", StringComparison.OrdinalIgnoreCase) ||
            !Uri.TryCreate($"http://localhost{parts[1]}", UriKind.Absolute, out var uri) ||
            !string.Equals(uri.AbsolutePath, "/auth/callback", StringComparison.Ordinal))
        {
            return (null, null, null);
        }

        var query = ParseQuery(uri.Query);
        if (query.TryGetValue("error", out var error))
        {
            var description = query.GetValueOrDefault("error_description");
            return (
                null,
                string.IsNullOrWhiteSpace(description)
                    ? error
                    : $"{error}: {description}",
                query.GetValueOrDefault("state"));
        }

        if (!query.TryGetValue("code", out var code) ||
            string.IsNullOrWhiteSpace(code) ||
            !query.TryGetValue("state", out var state) ||
            string.IsNullOrWhiteSpace(state))
        {
            return (
                null,
                "The sign-in redirect did not contain an authorization code.",
                query.GetValueOrDefault("state"));
        }

        return (new OAuthCallback(code, state), null, state);
    }

    private static TcpListener? TryStart(int port)
    {
        try
        {
            var listener = new TcpListener(IPAddress.Loopback, port);
            listener.Server.SetSocketOption(
                SocketOptionLevel.Socket,
                SocketOptionName.ReuseAddress,
                false);
            listener.Start(backlog: 1);
            return listener;
        }
        catch (SocketException)
        {
            return null;
        }
    }

    private static async Task<string> ReadRequestAsync(
        TcpClient client,
        CancellationToken cancellationToken)
    {
        var stream = client.GetStream();
        using var memory = new MemoryStream();
        var buffer = new byte[4096];
        while (memory.Length < MaximumRequestBytes)
        {
            var count = await stream.ReadAsync(buffer, cancellationToken)
                .ConfigureAwait(false);
            if (count == 0)
            {
                break;
            }

            memory.Write(buffer, 0, count);
            if (ContainsHeaderTerminator(memory.GetBuffer().AsSpan(0, (int)memory.Length)))
            {
                break;
            }
        }

        if (memory.Length >= MaximumRequestBytes)
        {
            throw new InvalidOperationException("The sign-in redirect was too large.");
        }

        return Encoding.ASCII.GetString(memory.GetBuffer(), 0, (int)memory.Length);
    }

    private static bool ContainsHeaderTerminator(ReadOnlySpan<byte> bytes) =>
        bytes.IndexOf("\r\n\r\n"u8) >= 0 || bytes.IndexOf("\n\n"u8) >= 0;

    private static async Task RespondBestEffortAsync(
        TcpClient client,
        string html,
        string status,
        CancellationToken cancellationToken)
    {
        try
        {
            await RespondAsync(client, html, status, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (IOException)
        {
            // The browser may close the callback socket immediately after
            // sending the authorization code. The code remains usable.
        }
        catch (SocketException)
        {
        }
    }

    private static async Task RespondAsync(
        TcpClient client,
        string html,
        string status,
        CancellationToken cancellationToken)
    {
        var body = Encoding.UTF8.GetBytes(html);
        var header = Encoding.ASCII.GetBytes(
            $"HTTP/1.1 {status}\r\n" +
            "Content-Type: text/html; charset=utf-8\r\n" +
            $"Content-Length: {body.Length}\r\n" +
            "Cache-Control: no-store\r\n" +
            "Connection: close\r\n\r\n");
        var stream = client.GetStream();
        await stream.WriteAsync(header, cancellationToken).ConfigureAwait(false);
        await stream.WriteAsync(body, cancellationToken).ConfigureAwait(false);
        await stream.FlushAsync(cancellationToken).ConfigureAwait(false);
    }

    private static Dictionary<string, string> ParseQuery(string query)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var item in query.TrimStart('?').Split(
                     '&',
                     StringSplitOptions.RemoveEmptyEntries))
        {
            var parts = item.Split('=', 2);
            var key = Decode(parts[0]);
            var value = parts.Length == 2 ? Decode(parts[1]) : string.Empty;
            result[key] = value;
        }

        return result;
    }

    private static string Decode(string value) =>
        Uri.UnescapeDataString(value.Replace("+", " ", StringComparison.Ordinal));

    private const string SuccessHtml = """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><title>TokenStats</title>
        <meta name="viewport" content="width=device-width,initial-scale=1"></head>
        <body style="font-family:Segoe UI,sans-serif;text-align:center;padding:3rem;color:#202124">
        <h2>Authorization received</h2>
        <p>TokenStats is finishing sign-in. Return to the app to confirm it completed.</p></body></html>
        """;

    private const string FailureHtml = """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><title>TokenStats</title>
        <meta name="viewport" content="width=device-width,initial-scale=1"></head>
        <body style="font-family:Segoe UI,sans-serif;text-align:center;padding:3rem;color:#202124">
        <h2>Sign-in failed</h2>
        <p>No authorization code was found. Return to TokenStats and try again.</p></body></html>
        """;
}
