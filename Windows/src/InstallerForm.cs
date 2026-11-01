// InstallerForm.cs — the window you see when double-clicking the downloaded
// exe. Explains where the app goes, offers shortcuts, runs the install, then
// hands over to the installed copy.

using System;
using System.Drawing;
using System.Windows.Forms;

namespace ScheutieOS;

internal sealed class InstallerForm : Form
{
    private readonly CheckBox _desktopBox;
    private readonly CheckBox _startMenuBox;
    private readonly Button _installButton;
    private readonly Button _runButton;
    private readonly Button _uninstallButton;
    private readonly Label _progress;
    private bool _busy;

    public InstallerForm()
    {
        Text = "ScheutieOS 安装程序";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(470, 336);
        Font = new Font("Microsoft YaHei UI", 9f);
        Icon = AppIcons.Get(32);

        bool already = Installer.Installed;

        var iconBox = new PictureBox
        {
            Image = AppIcons.Get(64).ToBitmap(),
            Left = 20, Top = 20, Size = new Size(64, 64)
        };
        Controls.Add(iconBox);

        var title = new Label
        {
            Text = Program.AppName,
            Font = new Font("Microsoft YaHei UI", 16f, FontStyle.Bold),
            Left = 100, Top = 22, Size = new Size(350, 34)
        };
        Controls.Add(title);

        var subtitle = new Label
        {
            Text = "版本 " + Program.VersionText + " · " + Program.Tagline,
            ForeColor = Color.DimGray,
            Left = 100, Top = 56, Size = new Size(350, 22)
        };
        Controls.Add(subtitle);

        var pathLabel = new Label
        {
            Text = "安装位置：%LOCALAPPDATA%\\ScheutieOS（约 200 MB，含内置运行时，安装后可离线使用）",
            Left = 20, Top = 100, Size = new Size(430, 22)
        };
        Controls.Add(pathLabel);

        _desktopBox = new CheckBox
        {
            Text = "创建桌面快捷方式",
            Checked = true,
            Left = 24, Top = 136, Size = new Size(220, 22)
        };
        Controls.Add(_desktopBox);

        _startMenuBox = new CheckBox
        {
            Text = "创建开始菜单快捷方式",
            Checked = true,
            Left = 24, Top = 162, Size = new Size(220, 22)
        };
        Controls.Add(_startMenuBox);

        _installButton = new Button
        {
            Text = already ? "重新安装" : "安装",
            Left = 244, Top = 210, Size = new Size(100, 32),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Right
        };
        _installButton.Click += (_, _) => RunInstall();
        Controls.Add(_installButton);

        _runButton = new Button
        {
            Text = "运行",
            Left = 352, Top = 210, Size = new Size(100, 32),
            Visible = already
        };
        _runButton.Click += (_, _) =>
        {
            Installer.LaunchInstalled();
            Close();
        };
        Controls.Add(_runButton);

        _uninstallButton = new Button
        {
            Text = "卸载…",
            Left = 136, Top = 210, Size = new Size(100, 32),
            Visible = already
        };
        _uninstallButton.Click += (_, _) =>
        {
            Uninstaller.SpawnUninstaller();
            Close();
        };
        Controls.Add(_uninstallButton);

        _progress = new Label
        {
            Text = already ? "检测到已安装的版本，可以重新安装或直接运行。" : "点击「安装」开始。",
            ForeColor = Color.DimGray,
            Left = 20, Top = 262, Size = new Size(430, 44),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right
        };
        Controls.Add(_progress);

        AcceptButton = _installButton;
    }

    private async void RunInstall()
    {
        if (_busy) return;
        _busy = true;
        _installButton.Enabled = _runButton.Enabled = _uninstallButton.Enabled = false;
        try
        {
            await System.Threading.Tasks.Task.Run(() =>
                Installer.DoInstall(_desktopBox.Checked, _startMenuBox.Checked,
                    s => BeginInvoke((MethodInvoker)(() => _progress.Text = s))));
            Installer.LaunchInstalled();
            Close();
        }
        catch (Exception ex)
        {
            _progress.Text = "安装失败：" + ex.Message;
            MessageBox.Show(this, ex.Message, "安装失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
            _installButton.Enabled = _runButton.Enabled = _uninstallButton.Enabled = true;
        }
        finally
        {
            _busy = false;
        }
    }
}
