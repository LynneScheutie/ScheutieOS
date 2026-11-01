// AppIcons.cs — loads the embedded multi-resolution .ico at real sizes.

using System;
using System.Drawing;

namespace ScheutieOS;

internal static class AppIcons
{
    private const string ResourceName = "ScheutieOS.AppIcon.ico";
    private static Icon? _cached;

    /// <summary>Best-sized icon for the given square size (16 / 32 / 256 …).</summary>
    public static Icon Get(int size)
    {
        if (size == 32 && _cached != null) return _cached;
        Icon icon = Load(size);
        if (size == 32) _cached = icon;
        return icon;
    }

    private static Icon Load(int size)
    {
        try
        {
            using var stream = typeof(AppIcons).Assembly.GetManifestResourceStream(ResourceName);
            if (stream != null) return new Icon(stream, size, size);
        }
        catch { /* fall through to exe icon */ }
        try
        {
            return Icon.ExtractAssociatedIcon(Paths.ExePath) ?? SystemIcons.Application;
        }
        catch
        {
            return SystemIcons.Application;
        }
    }
}
