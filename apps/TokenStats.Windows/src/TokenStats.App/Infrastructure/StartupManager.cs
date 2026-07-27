using Microsoft.Win32;

namespace TokenStats.App.Infrastructure;

public static class StartupManager
{
    private const string RunKeyPath =
        @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "TokenStats";

    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
            return key?.GetValue(ValueName) is string;
        }
        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true);
            if (!value)
            {
                key.DeleteValue(ValueName, throwOnMissingValue: false);
                return;
            }

            var executable = Environment.ProcessPath ??
                             throw new InvalidOperationException(
                                 "The running executable path is unavailable.");
            key.SetValue(
                ValueName,
                $"\"{executable}\" --background",
                RegistryValueKind.String);
        }
    }
}
