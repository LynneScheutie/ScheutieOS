// Diag.cs — synchronous local diagnostic log.
//
// Same idea as the macOS build: everything interesting is mirrored to a plain
// file the user (or support) can read with any editor:
//   %APPDATA%\ScheutieOS\ScheutieOS.log
// Written synchronously on purpose — the self-test and installer flows exit
// right after logging, and an async append would silently drop those lines.

using System;
using System.IO;
using System.Text;

namespace ScheutieOS;

internal static class Diag
{
    private const long MaxBytes = 256 * 1024;
    private static readonly object Gate = new();

    public static void Init()
    {
        try { Directory.CreateDirectory(Paths.AppDataDir); } catch { /* best effort */ }
    }

    public static void Log(string message)
    {
        try
        {
            var line = new StringBuilder();
            line.Append('[').Append(DateTime.Now.ToString("HH:mm:ss.fff")).Append("] ").Append(message).Append('\n');
            byte[] data = Encoding.UTF8.GetBytes(line.ToString());
            lock (Gate)
            {
                Directory.CreateDirectory(Paths.AppDataDir);
                if (File.Exists(Paths.LogFile))
                {
                    var info = new FileInfo(Paths.LogFile);
                    if (info.Length > MaxBytes) File.Delete(Paths.LogFile);
                }
                using var stream = new FileStream(Paths.LogFile, FileMode.Append, FileAccess.Write, FileShare.Read);
                stream.Write(data, 0, data.Length);
            }
        }
        catch { /* logging must never take the app down */ }
    }
}
