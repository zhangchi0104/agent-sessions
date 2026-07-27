using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using TokenStats.Core;

namespace TokenStats.App.Infrastructure;

/// <summary>
/// Stores one OAuth token pair as a generic credential owned by the current
/// Windows user. Claude and Codex use different target names.
/// </summary>
public sealed class CredentialTokenStore : ITokenStore
{
    private const uint CredTypeGeneric = 1;
    private const uint CredPersistLocalMachine = 2;
    private const int ErrorNotFound = 1168;
    private const int MaximumBlobBytes = 5 * 512;
    private const int MaximumChunks = 16;
    private const int ManifestVersion = 1;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly string _targetName;

    public CredentialTokenStore(string account)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(account);
        _targetName = $"dev.otakuma.TokenStats.Windows.oauth.{account}";
    }

    public OAuthTokens? Load()
    {
        var primary = ReadCredential(_targetName);
        if (primary is null)
        {
            return null;
        }

        try
        {
            var manifest = ParseManifest(primary);
            if (manifest is null)
            {
                // Compatibility with pre-manifest development builds.
                return DeserializeTokens(primary);
            }

            return LoadChunked(manifest);
        }
        catch (Exception exception) when (
            exception is JsonException or InvalidDataException or FormatException)
        {
            // A corrupt item is unusable, but still distinct from an OS read
            // failure; treat it like an absent account.
            return null;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(primary);
        }
    }

    public void Save(OAuthTokens tokens)
    {
        ArgumentNullException.ThrowIfNull(tokens);
        var payload = JsonSerializer.SerializeToUtf8Bytes(tokens, JsonOptions);
        if (payload.Length > MaximumBlobBytes * MaximumChunks)
        {
            throw new InvalidOperationException(
                "The OAuth credential is too large for Windows Credential Manager.");
        }

        var generation = Guid.NewGuid().ToString("N");
        var writtenTargets = new List<string>();
        var committed = false;
        try
        {
            var chunkCount = (payload.Length + MaximumBlobBytes - 1) /
                             MaximumBlobBytes;
            for (var index = 0; index < chunkCount; index++)
            {
                var length = Math.Min(
                    MaximumBlobBytes,
                    payload.Length - index * MaximumBlobBytes);
                var chunk = payload
                    .AsSpan(index * MaximumBlobBytes, length)
                    .ToArray();
                var target = ChunkTarget(generation, index);
                try
                {
                    WriteCredential(target, chunk);
                    writtenTargets.Add(target);
                }
                finally
                {
                    CryptographicOperations.ZeroMemory(chunk);
                }
            }

            var manifest = new CredentialManifest(
                ManifestVersion,
                generation,
                chunkCount,
                payload.Length,
                Convert.ToHexString(SHA256.HashData(payload)));
            var manifestBytes = JsonSerializer.SerializeToUtf8Bytes(
                manifest,
                JsonOptions);
            try
            {
                WriteCredential(_targetName, manifestBytes);
                committed = true;
            }
            finally
            {
                CryptographicOperations.ZeroMemory(manifestBytes);
            }
        }
        catch
        {
            if (!committed)
            {
                foreach (var target in writtenTargets)
                {
                    TryDeleteCredential(target);
                }
            }

            throw;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(payload);
        }

        CleanupChunkCredentials(keepGeneration: generation);
    }

    public void Clear()
    {
        DeleteCredential(_targetName);
        CleanupChunkCredentials(keepGeneration: null);
    }

    private OAuthTokens? LoadChunked(CredentialManifest manifest)
    {
        ValidateManifest(manifest);
        var payload = new byte[manifest.PayloadLength];
        try
        {
            var offset = 0;
            for (var index = 0; index < manifest.ChunkCount; index++)
            {
                var chunk = ReadCredential(ChunkTarget(manifest.Generation, index)) ??
                            throw new InvalidDataException(
                                "A credential chunk is missing.");
                try
                {
                    var expectedLength = Math.Min(
                        MaximumBlobBytes,
                        manifest.PayloadLength - offset);
                    if (chunk.Length != expectedLength)
                    {
                        throw new InvalidDataException(
                            "A credential chunk has an invalid length.");
                    }

                    chunk.CopyTo(payload, offset);
                    offset += chunk.Length;
                }
                finally
                {
                    CryptographicOperations.ZeroMemory(chunk);
                }
            }

            var expectedHash = Convert.FromHexString(manifest.Sha256);
            var actualHash = SHA256.HashData(payload);
            try
            {
                if (!CryptographicOperations.FixedTimeEquals(
                        expectedHash,
                        actualHash))
                {
                    throw new InvalidDataException(
                        "The OAuth credential failed its integrity check.");
                }
            }
            finally
            {
                CryptographicOperations.ZeroMemory(expectedHash);
                CryptographicOperations.ZeroMemory(actualHash);
            }

            return DeserializeTokens(payload);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(payload);
        }
    }

    private static CredentialManifest? ParseManifest(byte[] bytes)
    {
        try
        {
            using var document = JsonDocument.Parse(bytes);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object ||
                (!root.TryGetProperty("generation", out _) &&
                 !root.TryGetProperty("chunkCount", out _)))
            {
                return null;
            }

            var manifest = JsonSerializer.Deserialize<CredentialManifest>(
                bytes,
                JsonOptions) ??
                throw new InvalidDataException(
                    "The OAuth credential manifest is empty.");

            ValidateManifest(manifest);
            return manifest;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static OAuthTokens? DeserializeTokens(byte[] bytes)
    {
        var tokens = JsonSerializer.Deserialize<OAuthTokens>(bytes, JsonOptions);
        if (tokens is null ||
            string.IsNullOrWhiteSpace(tokens.AccessToken) ||
            string.IsNullOrWhiteSpace(tokens.RefreshToken) ||
            tokens.ExpiresAt.Year is < 2000 or > 2100)
        {
            return null;
        }

        return tokens;
    }

    private static void ValidateManifest(CredentialManifest manifest)
    {
        if (manifest.Version != ManifestVersion ||
            string.IsNullOrWhiteSpace(manifest.Generation) ||
            !Guid.TryParseExact(manifest.Generation, "N", out _) ||
            manifest.ChunkCount is < 1 or > MaximumChunks ||
            manifest.PayloadLength is < 1 or > MaximumBlobBytes * MaximumChunks ||
            manifest.ChunkCount !=
            (manifest.PayloadLength + MaximumBlobBytes - 1) / MaximumBlobBytes ||
            string.IsNullOrWhiteSpace(manifest.Sha256) ||
            manifest.Sha256.Length != SHA256.HashSizeInBytes * 2)
        {
            throw new InvalidDataException(
                "The OAuth credential manifest is invalid.");
        }
    }

    private string ChunkTarget(string generation, int index) =>
        $"{_targetName}.chunk.{generation}.{index}";

    private void CleanupChunkCredentials(string? keepGeneration)
    {
        try
        {
            var keepPrefix = keepGeneration is null
                ? null
                : $"{_targetName}.chunk.{keepGeneration}.";
            foreach (var target in EnumerateChunkTargets())
            {
                if (keepPrefix is null ||
                    !target.StartsWith(keepPrefix, StringComparison.Ordinal))
                {
                    TryDeleteCredential(target);
                }
            }
        }
        catch (Win32Exception)
        {
            // The primary manifest is the commit point. Orphan cleanup is
            // retried after the next save or clear and cannot be loaded.
        }
    }

    private IReadOnlyList<string> EnumerateChunkTargets()
    {
        var filter = $"{_targetName}.chunk.*";
        if (!CredEnumerate(filter, 0, out var count, out var credentials))
        {
            var error = Marshal.GetLastWin32Error();
            if (error == ErrorNotFound)
            {
                return [];
            }

            throw new Win32Exception(
                error,
                "Windows Credential Manager could not enumerate TokenStats credentials.");
        }

        try
        {
            var targets = new List<string>(checked((int)count));
            for (var index = 0; index < count; index++)
            {
                var pointer = Marshal.ReadIntPtr(
                    credentials,
                    checked((int)index * IntPtr.Size));
                var credential = Marshal.PtrToStructure<NativeCredential>(pointer);
                if (!string.IsNullOrWhiteSpace(credential.TargetName))
                {
                    targets.Add(credential.TargetName);
                }
            }

            return targets;
        }
        finally
        {
            CredFree(credentials);
        }
    }

    private static byte[]? ReadCredential(string target)
    {
        if (!CredRead(target, CredTypeGeneric, 0, out var credentialPointer))
        {
            var error = Marshal.GetLastWin32Error();
            if (error == ErrorNotFound)
            {
                return null;
            }

            throw new Win32Exception(
                error,
                "Windows Credential Manager could not read TokenStats credentials.");
        }

        try
        {
            var credential = Marshal.PtrToStructure<NativeCredential>(
                credentialPointer);
            if (credential.CredentialBlob == IntPtr.Zero ||
                credential.CredentialBlobSize == 0)
            {
                return null;
            }

            if (credential.CredentialBlobSize > MaximumBlobBytes)
            {
                throw new InvalidDataException(
                    "A Windows credential exceeded the supported size.");
            }

            var bytes = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length);
            return bytes;
        }
        finally
        {
            CredFree(credentialPointer);
        }
    }

    private static void WriteCredential(string target, byte[] bytes)
    {
        if (bytes.Length is < 1 or > MaximumBlobBytes)
        {
            throw new ArgumentOutOfRangeException(
                nameof(bytes),
                "Credential chunks must fit inside the Windows blob limit.");
        }

        var blob = Marshal.AllocCoTaskMem(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, blob, bytes.Length);
            var credential = new NativeCredential
            {
                Type = CredTypeGeneric,
                TargetName = target,
                CredentialBlobSize = (uint)bytes.Length,
                CredentialBlob = blob,
                Persist = CredPersistLocalMachine,
                UserName = Environment.UserName,
                Comment = "TokenStats independent OAuth session",
            };

            if (!CredWrite(ref credential, 0))
            {
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "Windows Credential Manager could not save TokenStats credentials.");
            }
        }
        finally
        {
            ZeroAndFree(blob, bytes.Length);
        }
    }

    private static void DeleteCredential(string target)
    {
        if (CredDelete(target, CredTypeGeneric, 0))
        {
            return;
        }

        var error = Marshal.GetLastWin32Error();
        if (error != ErrorNotFound)
        {
            throw new Win32Exception(
                error,
                "Windows Credential Manager could not delete TokenStats credentials.");
        }
    }

    private static void TryDeleteCredential(string target)
    {
        try
        {
            DeleteCredential(target);
        }
        catch (Win32Exception)
        {
            // A committed manifest never points at old chunks. Cleanup is
            // best-effort so a stale chunk cannot break a successful sign-in.
        }
    }

    private static void ZeroAndFree(IntPtr pointer, int length)
    {
        if (pointer == IntPtr.Zero)
        {
            return;
        }

        for (var index = 0; index < length; index++)
        {
            Marshal.WriteByte(pointer, index, 0);
        }

        Marshal.FreeCoTaskMem(pointer);
    }

    private sealed record CredentialManifest(
        int Version,
        string Generation,
        int ChunkCount,
        int PayloadLength,
        string Sha256);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NativeCredential
    {
        public uint Flags;
        public uint Type;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string TargetName;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string? Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string? TargetAlias;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredRead(
        string target,
        uint type,
        uint flags,
        out IntPtr credential);

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredWrite(
        ref NativeCredential credential,
        uint flags);

    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredDelete(string target, uint type, uint flags);

    [DllImport("advapi32.dll", EntryPoint = "CredEnumerateW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredEnumerate(
        string filter,
        uint flags,
        out uint count,
        out IntPtr credentials);

    [DllImport("advapi32.dll")]
    private static extern void CredFree(IntPtr credential);
}
