// Installer.cs — the actual copy-out-and-register steps, shared by the
// interactive window and --install --silent.

using System;
using System.Diagnostics;
using System.IO;
using System.Threading;

namespace ScheutieOS;

internal static class Installer
{
    public static bool Installed => File.Exists(Paths.InstalledExe);

    public static void RunSilent()
    {
        DoInstall(createDesktop: true, createStartMenu: true, progress: s => Diag.Log(s));
        LaunchInstalled();
    }

    public static void DoInstall(bool createDesktop, bool createStartMenu, Action<string> progress)
    {
        progress("正在关闭已运行的 ScheutieOS…");
        CloseRunningApp();

        progress("正在解压安装文件…");
        Directory.CreateDirectory(Paths.InstallDir);

        // Copy self → install dir, with retries in case Windows still holds a lock.
        Exception? lastError = null;
        for (int attempt = 1; attempt <= 6; attempt++)
        {
            try
            {
                File.Copy(Paths.ExePath, Paths.InstalledExe, overwrite: true);
                lastError = null;
                break;
            }
            catch (Exception ex)
            {
                lastError = ex;
                Thread.Sleep(600);
            }
        }
        if (lastError != null)
        {
            throw new IOException("无法写入安装目录 " + Paths.InstallDir + "\n\n" + lastError.Message);
        }

        if (createDesktop)
        {
            progress("正在创建桌面快捷方式…");
            Shortcuts.CreateDesktop();
        }
        if (createStartMenu)
        {
            progress("正在创建开始菜单快捷方式…");
            Shortcuts.CreateStartMenu();
        }

        progress("正在注册卸载信息…");
        Shortcuts.RegisterUninstallEntry();

        progress("安装完成 ✓");
        Diag.Log("install complete → " + Paths.InstallDir);
    }

    public static void LaunchInstalled()
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = Paths.InstalledExe,
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            Diag.Log("launch installed failed: " + ex.Message);
        }
    }

    private static void CloseRunningApp()
    {
        try
        {
            int self = Environment.ProcessId;
            foreach (Process p in Process.GetProcessesByName("ScheutieOS"))
            {
                if (p.Id == self) continue;
                try
                {
                    p.CloseMainWindow();
                    if (!p.WaitForExit(2500)) p.Kill();
                }
                catch { /* already gone */ }
                finally { p.Dispose(); }
            }
        }
        catch (Exception ex)
        {
            Diag.Log("close running app: " + ex.Message);
        }
    }
}
