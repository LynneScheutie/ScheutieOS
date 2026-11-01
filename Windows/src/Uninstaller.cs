// Uninstaller.cs — two-phase uninstall.
//
// Phase 1 (--uninstall): the installed exe copies itself to %TEMP% and starts
//                        the copy with --uninstall-go, so the file being
//                        deleted is not the file doing the deleting.
// Phase 2 (--uninstall-go): confirm, close the app, remove shortcuts, the
//                           registry entry and the install dir (optional:
//                           user data), then self-clean the temp copy.

using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Windows.Forms;

namespace ScheutieOS;

internal static class Uninstaller
{
    public static void SpawnUninstaller()
    {
        try
        {
            string temp = Path.Combine(Path.GetTempPath(), "ScheutieOS-uninstall.exe");
            File.Copy(Paths.ExePath, temp, overwrite: true);
            Process.Start(new ProcessStartInfo
            {
                FileName = temp,
                Arguments = "--uninstall-go",
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            Diag.Log("spawn uninstaller failed: " + ex.Message);
            MessageBox.Show("无法启动卸载程序：" + ex.Message, "卸载 ScheutieOS",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    public static int RunUninstallPhase()
    {
        try
        {
            var confirm = MessageBox.Show(
                "确定要卸载 ScheutieOS 吗？",
                "卸载 ScheutieOS",
                MessageBoxButtons.YesNo, MessageBoxIcon.Question,
                MessageBoxDefaultButton.Button1);
            if (confirm != DialogResult.Yes) return 1;

            CloseRunningApp();

            Shortcuts.DeleteAll();
            Shortcuts.RemoveUninstallEntry();

            var wipeData = MessageBox.Show(
                "是否同时删除登录数据与所有设置？\n\n选择「否」则保留，下次安装可继续使用。",
                "卸载 ScheutieOS",
                MessageBoxButtons.YesNo, MessageBoxIcon.Question,
                MessageBoxDefaultButton.Button2);

            RemoveDirectoryWithRetry(Paths.InstallDir);
            if (wipeData == DialogResult.Yes)
            {
                RemoveDirectoryWithRetry(Paths.AppDataDir);
            }

            MessageBox.Show("ScheutieOS 已卸载。", "卸载 ScheutieOS",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            SelfDeleteTempCopy();
            return 0;
        }
        catch (Exception ex)
        {
            Diag.Log("uninstall failed: " + ex);
            MessageBox.Show("卸载失败：" + ex.Message, "卸载 ScheutieOS",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
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
                    if (!p.WaitForExit(3000)) p.Kill();
                    p.WaitForExit(2000);
                }
                catch { /* already gone */ }
                finally { p.Dispose(); }
            }
        }
        catch (Exception ex)
        {
            Diag.Log("uninstall close app: " + ex.Message);
        }
    }

    private static void RemoveDirectoryWithRetry(string dir)
    {
        for (int attempt = 1; attempt <= 6; attempt++)
        {
            try
            {
                if (!Directory.Exists(dir)) return;
                Directory.Delete(dir, recursive: true);
                return;
            }
            catch when (attempt < 6)
            {
                Thread.Sleep(700);
            }
        }
        throw new IOException("无法删除目录 " + dir + "（可能仍有文件被占用）");
    }

    private static void SelfDeleteTempCopy()
    {
        try
        {
            string self = Paths.ExePath;
            if (!self.StartsWith(Path.GetTempPath(), StringComparison.OrdinalIgnoreCase)) return;
            // Give this process a moment to exit, then remove the temp binary.
            Process.Start(new ProcessStartInfo
            {
                FileName = "cmd.exe",
                Arguments = "/C ping -n 3 127.0.0.1 > nul & del \"" + self + "\"",
                CreateNoWindow = true,
                UseShellExecute = false
            });
        }
        catch { /* cosmetic only */ }
    }
}
