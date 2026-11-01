// Program.cs — entry point and mode dispatch.
//
// One binary, two personalities:
//   · app mode       — exe lives in %LOCALAPPDATA%\ScheutieOS (or --app) → the
//                      WebView2 window. Single instance, × hides to tray,
//                      Ctrl+Q fully quits.
//   · installer mode — exe runs from anywhere else (e.g. Downloads). Shows a
//                      small install window, copies itself to the install dir,
//                      creates shortcuts, registers an uninstall entry, then
//                      launches the installed copy. This is the "点击解压安装
//                      才能运行" flow: nothing runs until it is installed.
//
// Diagnostics:  ScheutieOS.exe --diag
// Silent setup: ScheutieOS-Setup.exe --install --silent
// Uninstall:    ScheutieOS.exe --uninstall   (or 帮助 menu / 「应用和功能」)

using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;

namespace ScheutieOS;

internal static class Program
{
    public const string AppName = "ScheutieOS";
    public const string VersionText = "8.4.1";
    public const string BuildText = "841";
    public const string Developer = "Lynne Scheutie & Wanchen Qian";
    public const string Tagline = "A quick launcher for DeepSeek";
    public const string StartUrl = "https://chat.deepseek.com/";

    /// <summary>Registered window message used to wake the first instance.</summary>
    public static uint ShowMainMessage;

    private static Mutex? _singleInstanceMutex;

    [STAThread]
    private static int Main(string[] args)
    {
        ApplicationConfiguration.Initialize();

        if (args.Contains("--diag"))
        {
            return RunDiag();
        }

        if (args.Contains("--uninstall-go"))
        {
            return Uninstaller.RunUninstallPhase();
        }

        if (args.Contains("--uninstall"))
        {
            Uninstaller.SpawnUninstaller();
            return 0;
        }

        bool wantInstall = args.Contains("--install");
        bool wantApp = args.Contains("--app") || args.Contains("--no-install");

        if (wantInstall || (!Paths.RunningFromInstallDir && !wantApp))
        {
            Diag.Init();
            Diag.Log("=== setup launch · exe=" + Paths.ExePath + " ===");
            if (args.Contains("--silent"))
            {
                Installer.RunSilent();
                return 0;
            }
            Application.Run(new InstallerForm());
            return 0;
        }

        // ---- app mode ----
        if (!TryAcquireSingleInstance())
        {
            // Already running → poke the existing window and leave.
            PostMessage((IntPtr)0xFFFF, ShowMainMessage, IntPtr.Zero, IntPtr.Zero);
            return 0;
        }

        Diag.Init();
        Diag.Log("=== app launch · version=" + VersionText + " exe=" + Paths.ExePath + " ===");
        Application.Run(new MainForm());
        return 0;
    }

    private static bool TryAcquireSingleInstance()
    {
        ShowMainMessage = RegisterWindowMessage("ScheutieOS_ShowMainWindow");
        _singleInstanceMutex = new Mutex(true, @"Local\ScheutieOS_SingleInstance", out bool created);
        return created;
    }

    private static int RunDiag()
    {
        Diag.Init();
        Diag.Log("--diag exe=" + Paths.ExePath);
        Diag.Log("--diag installDir=" + Paths.InstallDir);
        Diag.Log("--diag runningFromInstallDir=" + Paths.RunningFromInstallDir);
        Diag.Log("--diag version=" + VersionText);
        try
        {
            Diag.Log("--diag webview2=" + CoreWebView2Environment.GetAvailableBrowserVersionString());
        }
        catch (Exception ex)
        {
            Diag.Log("--diag webview2 MISSING: " + ex.Message);
        }
        Console.WriteLine("diag written to " + Paths.LogFile);
        return 0;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern uint RegisterWindowMessage(string lpString);

    [DllImport("user32.dll")]
    private static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
}
