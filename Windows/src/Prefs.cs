// Prefs.cs — settings persisted as JSON at %APPDATA%\ScheutieOS\settings.json.
// Mirrors the macOS app's UserDefaults keys one to one.

using System;
using System.IO;
using System.Text.Encodings.Web;
using System.Text.Json;

namespace ScheutieOS;

internal enum AppearanceMode
{
    System = 0,
    Dark = 1,
    Light = 2
}

internal static class AppearanceExtensions
{
    public static string Title(this AppearanceMode m) => m switch
    {
        AppearanceMode.Dark => "强制暗色",
        AppearanceMode.Light => "强制亮色",
        _ => "跟随系统"
    };
}

internal sealed class Prefs
{
    public int AppearanceModeValue { get; set; } = (int)AppearanceMode.System;
    public int UaIndex { get; set; } = 0;
    public string CustomUA { get; set; } = "";
    public bool HideScrollbar { get; set; }
    public bool NoAnimation { get; set; }
    public string CustomCSS { get; set; } = "";
    public double PageZoom { get; set; } = 1.0;
    public int ExportCount { get; set; }
    public bool TrayNoticeShown { get; set; }

    // Main window bounds (RestoreBounds when maximized).
    public int WindowX { get; set; }
    public int WindowY { get; set; }
    public int WindowW { get; set; }
    public int WindowH { get; set; }
    public bool WindowMaximized { get; set; }

    [System.Text.Json.Serialization.JsonIgnore]
    public AppearanceMode AppearanceMode
    {
        get => Enum.IsDefined(typeof(AppearanceMode), AppearanceModeValue)
            ? (AppearanceMode)AppearanceModeValue : AppearanceMode.System;
        set => AppearanceModeValue = (int)value;
    }

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    public static Prefs Load()
    {
        try
        {
            string path = Paths.SettingsFile;
            if (File.Exists(path))
            {
                Prefs p = JsonSerializer.Deserialize<Prefs>(File.ReadAllText(path)) ?? new Prefs();
                if (p.PageZoom < 0.4) p.PageZoom = 1.0;
                if (p.PageZoom > 3.0) p.PageZoom = 3.0;
                return p;
            }
        }
        catch (Exception ex)
        {
            Diag.Log("prefs load failed: " + ex.Message);
        }
        return new Prefs();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Paths.AppDataDir);
            File.WriteAllText(Paths.SettingsFile, JsonSerializer.Serialize(this, JsonOpts));
        }
        catch (Exception ex)
        {
            Diag.Log("prefs save failed: " + ex.Message);
        }
    }

    /// <summary>CSS assembled from the toggles + the user's custom rules.</summary>
    [System.Text.Json.Serialization.JsonIgnore]
    public string CombinedCSS
    {
        get
        {
            var parts = new System.Collections.Generic.List<string>();
            if (HideScrollbar)
            {
                parts.Add(@"
html, body, * { scrollbar-width: none !important; -ms-overflow-style: none !important; }
::-webkit-scrollbar { width: 0 !important; height: 0 !important; display: none !important; }
");
            }
            if (NoAnimation)
            {
                parts.Add(@"
*, *::before, *::after {
  animation-duration: 0.001ms !important;
  animation-delay: 0ms !important;
  animation-iteration-count: 1 !important;
  transition-duration: 0.001ms !important;
  transition-delay: 0ms !important;
  scroll-behavior: auto !important;
}
");
            }
            string custom = (CustomCSS ?? "").Trim();
            if (custom.Length > 0) parts.Add(custom);
            return string.Join("\n\n", parts);
        }
    }

    public bool HasAnyStyle =>
        HideScrollbar || NoAnimation || !string.IsNullOrWhiteSpace(CustomCSS);
}
