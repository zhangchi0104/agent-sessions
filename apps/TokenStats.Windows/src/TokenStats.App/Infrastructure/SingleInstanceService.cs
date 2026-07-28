using System.Diagnostics;
using System.IO.Pipes;
using System.Security.Principal;
using System.Text;

namespace TokenStats.App.Infrastructure;

public sealed class SingleInstanceService : IDisposable
{
    private static readonly string InstanceScope = BuildInstanceScope();
    private static readonly string MutexName =
        $"Local\\dev.otakuma.TokenStats.Windows.{InstanceScope}";
    private static readonly string PipeName =
        $"dev.otakuma.TokenStats.Windows.activate.{InstanceScope}";
    private readonly Mutex _mutex;
    private readonly CancellationTokenSource _cancellation = new();
    private Task? _serverTask;
    private bool _disposed;

    public SingleInstanceService()
    {
        _mutex = new Mutex(initiallyOwned: true, MutexName, out var isPrimary);
        IsPrimary = isPrimary;
    }

    public bool IsPrimary { get; }

    public event EventHandler? ActivationRequested;

    public void StartListening()
    {
        if (!IsPrimary || _serverTask is not null)
        {
            return;
        }

        _serverTask = ListenAsync(_cancellation.Token);
    }

    public static async Task SignalPrimaryAsync()
    {
        try
        {
            await using var client = new NamedPipeClientStream(
                ".",
                PipeName,
                PipeDirection.Out,
                PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(2));
            await client.ConnectAsync(timeout.Token).ConfigureAwait(false);
            await client.WriteAsync(Encoding.UTF8.GetBytes("activate"), timeout.Token)
                .ConfigureAwait(false);
        }
        catch (IOException)
        {
            // The first process may still be starting. It is already protected
            // by the mutex, so the second process can safely retire.
        }
        catch (OperationCanceledException)
        {
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _cancellation.Cancel();
        _cancellation.Dispose();
        if (IsPrimary)
        {
            try
            {
                _mutex.ReleaseMutex();
            }
            catch (ApplicationException)
            {
            }
        }

        _mutex.Dispose();
    }

    private async Task ListenAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await using var server = new NamedPipeServerStream(
                    PipeName,
                    PipeDirection.In,
                    1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                await server.WaitForConnectionAsync(cancellationToken).ConfigureAwait(false);
                var buffer = new byte[32];
                _ = await server.ReadAsync(buffer, cancellationToken).ConfigureAwait(false);
                ActivationRequested?.Invoke(this, EventArgs.Empty);
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (IOException)
            {
                if (!cancellationToken.IsCancellationRequested)
                {
                    await Task.Delay(250, cancellationToken).ConfigureAwait(false);
                }
            }
        }
    }

    private static string BuildInstanceScope()
    {
        using var identity = WindowsIdentity.GetCurrent();
        var user = identity.User?.Value ??
                   throw new InvalidOperationException(
                       "Windows did not provide the current user SID.");
        return $"{user}.{Process.GetCurrentProcess().SessionId}";
    }
}
