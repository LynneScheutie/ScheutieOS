// Paths.cs — every location the app reads or writes, in one place.

using System;
using System.IO;

namespace ScheutieOS;

internal static class Paths
{
    /// <summary>Where the app installs itself: %LOCALAPPDATA%\ScheutieOS</summary>
    public static string InstallDir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ScheutieOS");

    public static string InstalledExe => Path.Combine(InstallDir, "ScheutieOS.exe");

    /// <summary>Roaming settings dir: %APPDATA%\ScheutieOS</summary>
    public static string AppDataDir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ScheutieOS");

    public static string SettingsFile => Path.Combine(AppDataDir, "settings.json");

    public static string LogFile => Path.Combine(AppDataDir, "ScheutieOS.log");

    /// <summary>Persistent WebView2 profile (cookies / login survive restarts).</summary>
    public static string WebView2Data => Path.Combine(AppDataDir, "WebView2");

    public static string ExePath =>
        Environment.ProcessPath ?? System.Windows.Forms.Application.ExecutablePath;

    /// <summary>True when this exe runs from the install directory (app mode).</summary>
    public static bool RunningFromInstallDir
    {
        get
        {
            string dir = Path.GetDirectoryName(ExePath) ?? "";
            return string.Equals(dir, InstallDir, StringComparison.OrdinalIgnoreCase);
        }
    }
}
