// MainForm.cs — the main window: WebView2 hosting chat.deepseek.com plus the
// full 增强 menu set, mirroring the macOS build feature by feature.
//
// Behaviour notes:
//   · Ctrl+/- / Ctrl+mousewheel / pinch zoom are disabled (same as macOS) —
//     zoom lives in the 显示 menu only.
//   · Ctrl+C/V/X/Z/A are left to WebView2 (editing keys still work); the
//     编辑 menu items are conveniences for mouse users.
//   · The × button hides the window to the notification area; Ctrl+Q (菜单
//     文件 → 退出) is the only full quit. A second launch of the exe wakes
//     the hidden window via a broadcast message.

using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Text.Json;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace ScheutieOS;

internal sealed class MainForm : Form
{
    private readonly Prefs _prefs = Prefs.Load();

    private WebView2 _web = null!;
    private MenuStrip _menu = null!;
    private StatusStrip _status = null!;
    private ToolStripStatusLabel _statusLabel = null!;
    private ToolStrip _findBar = null!;
    private ToolStripTextBox _findBox = null!;
    private ToolStripLabel _findStatus = null!;
    private NotifyIcon _tray = null!;

    private ToolStripMenuItem _appearanceMenu = null!;
    private ToolStripMenuItem _uaMenu = null!;
    private ToolStripMenuItem _styleMenu = null!;
    private ToolStripMenuItem _backItem = null!;
    private ToolStripMenuItem _forwardItem = null!;

    private readonly Timer _statusTimer = new() { Interval = 3200 };
    private bool _webReady;
    private bool _exiting;

    public MainForm()
    {
        Text = Program.AppName;
        Icon = AppIcons.Get(32);
        StartPosition = FormStartPosition.Manual;
        MinimumSize = new Size(440, 440);
        RestoreBoundsOrCenter();

        BuildMenu();
        BuildStatusBar();
        BuildFindBar();
        BuildLayout();
        BuildTray();
        Program.ShowMainMessage = Program.ShowMainMessage; // already registered in Main

        _statusTimer.Tick += (_, _) => { _statusLabel.Text = ""; _statusTimer.Stop(); };
    }

    // ---------------------------------------------------------------- layout

    private void RestoreBoundsOrCenter()
    {
        if (_prefs.WindowW > 200 && _prefs.WindowH > 200)
        {
            var bounds = new Rectangle(_prefs.WindowX, _prefs.WindowY, _prefs.WindowW, _prefs.WindowH);
            bool onScreen = false;
            foreach (Screen s in Screen.AllScreens)
            {
                if (s.WorkingArea.IntersectsWith(bounds)) { onScreen = true; break; }
            }
            if (onScreen)
            {
                Bounds = bounds;
                if (_prefs.WindowMaximized) WindowState = FormWindowState.Maximized;
                return;
            }
        }
        StartPosition = FormStartPosition.CenterScreen;
        Size = new Size(1120, 780);
    }

    private void BuildLayout()
    {
        _web = new WebView2 { Dock = DockStyle.Fill };

        // A table layout keeps the dock-order question out of the picture:
        // menu (auto) / find bar (auto, collapses when hidden) / web (fill) / status (auto).
        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 4
        };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.Controls.Add(_menu, 0, 0);
        layout.Controls.Add(_findBar, 0, 1);
        layout.Controls.Add(_web, 0, 2);
        layout.Controls.Add(_status, 0, 3);

        Controls.Add(layout);
    }

    private void BuildStatusBar()
    {
        _statusLabel = new ToolStripStatusLabel("");
        _status = new StatusStrip();
        _status.Items.Add(_statusLabel);
    }

    private void BuildTray()
    {
        _tray = new NotifyIcon
        {
            Icon = AppIcons.Get(16),
            Text = Program.AppName,
            Visible = true
        };
        _tray.DoubleClick += (_, _) => ShowMain();

        var trayMenu = new ContextMenuStrip();
        trayMenu.Items.Add("显示主窗口", null, (_, _) => ShowMain());
        trayMenu.Items.Add(new ToolStripSeparator());
        trayMenu.Items.Add("退出", null, (_, _) => ReallyExit());
        _tray.ContextMenuStrip = trayMenu;
    }

    // ------------------------------------------------------------------ menu

    private void BuildMenu()
    {
        _menu = new MenuStrip();
        _menu.Font = new Font("Microsoft YaHei UI", 9f);

        // ---- 文件
        var fileMenu = new ToolStripMenuItem("文件(&F)");
        fileMenu.DropDownItems.Add(Item("导出对话为 Markdown(&E)…", Keys.Control | Keys.Shift | Keys.S, (_, _) => ExportMarkdownToFile()));
        fileMenu.DropDownItems.Add(Item("复制对话为 Markdown(&C)", Keys.Control | Keys.Shift | Keys.C, (_, _) => CopyConversationMarkdown()));
        fileMenu.DropDownItems.Add(Item("复制全文（纯文本）(&T)", Keys.None, (_, _) => CopyPlainText()));
        fileMenu.DropDownItems.Add(new ToolStripSeparator());
        fileMenu.DropDownItems.Add(Item("打印 / 存储为 PDF(&P)…", Keys.Control | Keys.P, (_, _) => PrintPage()));
        fileMenu.DropDownItems.Add(new ToolStripSeparator());
        fileMenu.DropDownItems.Add(Item("退出(&Q)", Keys.Control | Keys.Q, (_, _) => ReallyExit()));
        _menu.Items.Add(fileMenu);

        // ---- 编辑
        var editMenu = new ToolStripMenuItem("编辑(&E)");
        editMenu.DropDownItems.Add(Item("撤销(&U)", Keys.None, (_, _) => ExecJs("undo")));
        editMenu.DropDownItems.Add(Item("重做(&R)", Keys.None, (_, _) => ExecJs("redo")));
        editMenu.DropDownItems.Add(new ToolStripSeparator());
        editMenu.DropDownItems.Add(Item("剪切(&T)", Keys.None, (_, _) => ExecJs("cut")));
        editMenu.DropDownItems.Add(Item("复制(&C)", Keys.None, (_, _) => ExecJs("copy")));
        editMenu.DropDownItems.Add(Item("粘贴(&P)", Keys.None, (_, _) => { if (_webReady) _web.Focus(); SendKeys.Send("^v"); }));
        editMenu.DropDownItems.Add(Item("全选(&A)", Keys.None, (_, _) => ExecJs("selectAll")));
        editMenu.DropDownItems.Add(new ToolStripSeparator());
        editMenu.DropDownItems.Add(Item("查找(&F)…", Keys.Control | Keys.F, (_, _) => ShowFind()));
        _menu.Items.Add(editMenu);

        // ---- 显示
        var viewMenu = new ToolStripMenuItem("显示(&V)");
        viewMenu.DropDownItems.Add(Item("重新载入(&R)", Keys.F5, (_, _) => Reload()));
        viewMenu.DropDownItems.Add(Item("回到首页(&H)", Keys.Control | Keys.Shift | Keys.R, (_, _) => GoHome()));
        viewMenu.DropDownItems.Add(new ToolStripSeparator());
        // Zoom deliberately has NO keyboard shortcuts: one stray Ctrl press left
        // the window stuck at the wrong size on macOS too. Menu only.
        viewMenu.DropDownItems.Add(Item("放大(&I)", Keys.None, (_, _) => SetZoom(_prefs.PageZoom + 0.1)));
        viewMenu.DropDownItems.Add(Item("缩小(&O)", Keys.None, (_, _) => SetZoom(_prefs.PageZoom - 0.1)));
        viewMenu.DropDownItems.Add(Item("实际大小(&A)", Keys.None, (_, _) => SetZoom(1.0)));
        viewMenu.DropDownItems.Add(new ToolStripSeparator());
        viewMenu.DropDownItems.Add(Item("进入全屏幕(&F)", Keys.F11, (_, _) =>
        {
            if (WindowState == FormWindowState.Normal) WindowState = FormWindowState.Maximized;
            else WindowState = FormWindowState.Normal;
        }));
        _menu.Items.Add(viewMenu);

        // ---- 增强
        var enhanceMenu = new ToolStripMenuItem("增强(&N)");
        _appearanceMenu = new ToolStripMenuItem("外观(&P)");
        foreach (AppearanceMode mode in new[] { AppearanceMode.System, AppearanceMode.Dark, AppearanceMode.Light })
        {
            var item = Item(mode.Title(), Keys.None, (_, _) => SetAppearance(mode));
            item.Tag = mode;
            _appearanceMenu.DropDownItems.Add(item);
        }
        _appearanceMenu.DropDownOpening += (_, _) => SyncAppearanceChecks();
        enhanceMenu.DropDownItems.Add(_appearanceMenu);

        _uaMenu = new ToolStripMenuItem("浏览器标识(&U)");
        _uaMenu.DropDownOpening += (_, _) => SyncUaChecks();
        enhanceMenu.DropDownItems.Add(_uaMenu);

        _styleMenu = new ToolStripMenuItem("页面样式(&S)");
        _styleMenu.DropDownItems.Add(Item("隐藏滚动条(&H)", Keys.None, (_, _) => { _prefs.HideScrollbar = !_prefs.HideScrollbar; _prefs.Save(); ApplyStyles(); }));
        _styleMenu.DropDownItems.Add(Item("禁用动画与过渡(&A)", Keys.None, (_, _) => { _prefs.NoAnimation = !_prefs.NoAnimation; _prefs.Save(); ApplyStyles(); }));
        _styleMenu.DropDownItems.Add(new ToolStripSeparator());
        _styleMenu.DropDownItems.Add(Item("自定义 CSS(&C)…", Keys.None, (_, _) => EditCustomCSS()));
        _styleMenu.DropDownItems.Add(Item("清除自定义 CSS(&L)", Keys.None, (_, _) => { _prefs.CustomCSS = ""; _prefs.Save(); ApplyStyles(); Flash("自定义 CSS 已清除"); }));
        _styleMenu.DropDownItems.Add(new ToolStripSeparator());
        _styleMenu.DropDownItems.Add(Item("重新应用样式(&R)", Keys.None, (_, _) => { ApplyStyles(); Flash("样式已重新应用"); }));
        _styleMenu.DropDownOpening += (_, _) => SyncStyleChecks();
        enhanceMenu.DropDownItems.Add(_styleMenu);

        enhanceMenu.DropDownItems.Add(new ToolStripSeparator());
        enhanceMenu.DropDownItems.Add(Item("重置所有增强设置(&R)", Keys.None, (_, _) => ResetAllEnhancements()));
        _menu.Items.Add(enhanceMenu);

        // ---- 历史记录
        var historyMenu = new ToolStripMenuItem("历史记录(&S)");
        _backItem = Item("后退(&B)", Keys.Alt | Keys.Left, (_, _) => { if (_webReady && _web.CoreWebView2.CanGoBack) _web.CoreWebView2.GoBack(); });
        _forwardItem = Item("前进(&W)", Keys.Alt | Keys.Right, (_, _) => { if (_webReady && _web.CoreWebView2.CanGoForward) _web.CoreWebView2.GoForward(); });
        historyMenu.DropDownItems.Add(_backItem);
        historyMenu.DropDownItems.Add(_forwardItem);
        historyMenu.DropDownItems.Add(new ToolStripSeparator());
        historyMenu.DropDownItems.Add(Item("回到首页(&H)", Keys.None, (_, _) => GoHome()));
        historyMenu.DropDownOpening += (_, _) =>
        {
            _backItem.Enabled = _webReady && _web.CoreWebView2.CanGoBack;
            _forwardItem.Enabled = _webReady && _web.CoreWebView2.CanGoForward;
        };
        _menu.Items.Add(historyMenu);

        // ---- 窗口
        var windowMenu = new ToolStripMenuItem("窗口(&W)");
        windowMenu.DropDownItems.Add(Item("最小化(&N)", Keys.None, (_, _) => WindowState = FormWindowState.Minimized));
        windowMenu.DropDownItems.Add(Item("关闭窗口(&C)", Keys.Control | Keys.W, (_, _) => Close()));
        windowMenu.DropDownItems.Add(new ToolStripSeparator());
        windowMenu.DropDownItems.Add(Item("显示主窗口(&S)", Keys.None, (_, _) => ShowMain()));
        _menu.Items.Add(windowMenu);

        // ---- 帮助
        var helpMenu = new ToolStripMenuItem("帮助(&H)");
        helpMenu.DropDownItems.Add(Item("关于 ScheutieOS(&A)…", Keys.None, (_, _) => ShowAbout()));
        helpMenu.DropDownItems.Add(new ToolStripSeparator());
        helpMenu.DropDownItems.Add(Item("打开诊断日志(&L)", Keys.None, (_, _) => OpenLogFile()));
        helpMenu.DropDownItems.Add(Item("卸载 ScheutieOS(&U)…", Keys.None, (_, _) => AskUninstall()));
        _menu.Items.Add(helpMenu);
    }

    private static ToolStripMenuItem Item(string text, Keys keys, EventHandler onClick)
    {
        var item = new ToolStripMenuItem(text);
        if (keys != Keys.None) item.ShortcutKeys = keys;
        item.Click += onClick;
        return item;
    }

    // ---------------------------------------------------------- UA presets

    private static readonly (string Name, string Value)[] UaPresets =
    {
        ("Chrome (Windows) — 默认",
         "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"),
        ("Chrome (macOS)",
         "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"),
        ("Safari (macOS)",
         "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"),
        ("Safari (iPhone)",
         "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
        ("Safari (iPad)",
         "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1")
    };

    // ------------------------------------------------------------- web init

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        _ = InitWebAsync();
    }

    private async System.Threading.Tasks.Task InitWebAsync()
    {
        CoreWebView2Environment env;
        try
        {
            env = await CoreWebView2Environment.CreateAsync(null, Paths.WebView2Data);
        }
        catch (Exception ex)
        {
            Diag.Log("webview2 environment failed: " + ex.Message);
            ShowRuntimeMissing();
            return;
        }

        try
        {
            await _web.EnsureCoreWebView2Async(env);
        }
        catch (Exception ex)
        {
            Diag.Log("webview2 init failed: " + ex.Message);
            ShowRuntimeMissing();
            return;
        }

        var core = _web.CoreWebView2;
        _webReady = true;

        // No accidental zoom, no browser chrome shortcuts (Ctrl+P / F5 / Ctrl+-
        // are re-bound to our own menu), no status bar.
        core.Settings.IsZoomControlEnabled = false;
        core.Settings.AreBrowserAcceleratorKeysEnabled = false;
        core.Settings.IsStatusBarEnabled = false;
        core.Settings.UserAgent = EffectiveUA();

        try
        {
            core.Profile.DefaultDownloadFolderPath =
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
        }
        catch (Exception ex)
        {
            Diag.Log("download folder: " + ex.Message);
        }

        ApplyAppearance();
        await core.AddScriptToExecuteOnDocumentCreatedAsync(InjectedJs.Runtime);

        core.DocumentTitleChanged += (_, _) => UpdateTitle();
        core.NavigationCompleted += (_, _) => { ApplyStyles(); Diag.Log("page loaded → " + core.Source); };
        core.NavigationStarting += (_, e) => HandleNavigationStarting(e);
        core.NewWindowRequested += (_, e) => HandleNewWindow(e);
        _web.ZoomFactorChanged += (_, _) => { _prefs.PageZoom = _web.ZoomFactor; _prefs.Save(); };

        _web.ZoomFactor = ClampZoom(_prefs.PageZoom);
        _web.Source = new Uri(Program.StartUrl);
        Diag.Log("webview ready · ua=" + EffectiveUA());
    }

    private string EffectiveUA()
    {
        if (_prefs.UaIndex >= 0 && _prefs.UaIndex < UaPresets.Length) return UaPresets[_prefs.UaIndex].Value;
        string custom = (_prefs.CustomUA ?? "").Trim();
        return custom.Length > 0 ? custom : UaPresets[0].Value;
    }

    private void ShowRuntimeMissing()
    {
        var result = MessageBox.Show(this,
            "未检测到 Microsoft Edge WebView2 运行时。\n\n" +
            "ScheutieOS 需要它来显示网页（Windows 11 与较新的 Windows 10 一般已内置）。\n\n" +
            "是否打开官方下载页面？",
            "ScheutieOS", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
        if (result == DialogResult.Yes)
        {
            OpenExternally("https://go.microsoft.com/fwlink/p/?LinkId=2124703");
        }
        Application.Exit();
    }

    // ----------------------------------------------------------- navigation

    private static bool IsInternalScheme(Uri uri)
    {
        string scheme = uri.Scheme.ToLowerInvariant();
        return scheme is "http" or "https" or "about" or "data" or "blob" or "file";
    }

    private static bool IsDeepSeekHost(Uri uri) =>
        uri.Host.EndsWith("deepseek.com", StringComparison.OrdinalIgnoreCase);

    private void HandleNavigationStarting(CoreWebView2NavigationStartingEventArgs e)
    {
        if (!Uri.TryCreate(e.Uri, UriKind.Absolute, out var uri)) return;
        if (!IsInternalScheme(uri))
        {
            e.Cancel = true;
            OpenExternally(e.Uri);
        }
    }

    private void HandleNewWindow(CoreWebView2NewWindowRequestedEventArgs e)
    {
        e.Handled = true;
        if (Uri.TryCreate(e.Uri, UriKind.Absolute, out var uri))
        {
            if (IsDeepSeekHost(uri))
            {
                _web.CoreWebView2.Navigate(e.Uri);
                return;
            }
        }
        OpenExternally(e.Uri);
    }

    internal static void OpenExternally(string url)
    {
        try
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
            Diag.Log("external → " + url);
        }
        catch (Exception ex)
        {
            Diag.Log("external failed (" + url + "): " + ex.Message);
        }
    }

    private void UpdateTitle()
    {
        if (!_webReady) return;
        string t = (_web.CoreWebView2.DocumentTitle ?? "").Trim();
        if (t.Length == 0 || t.Contains("deepseek.com") || t.Equals("DeepSeek", StringComparison.OrdinalIgnoreCase))
        {
            Text = Program.AppName;
        }
        else
        {
            Text = t + " — " + Program.AppName;
        }
    }

    // ------------------------------------------------------------- actions

    private void Reload() { if (_webReady) _web.CoreWebView2.Reload(); }
    private void GoHome() { if (_webReady) _web.CoreWebView2.Navigate(Program.StartUrl); }

    private static double ClampZoom(double z) => Math.Min(Math.Max(z, 0.4), 3.0);

    private void SetZoom(double z)
    {
        double clamped = ClampZoom(z);
        if (_webReady) _web.ZoomFactor = clamped;
        _prefs.PageZoom = clamped;
        _prefs.Save();
        Flash("缩放 " + Math.Round(clamped * 100) + "%");
    }

    private void SetAppearance(AppearanceMode mode)
    {
        _prefs.AppearanceMode = mode;
        _prefs.Save();
        ApplyAppearance();
        Flash("外观已切换为：" + mode.Title());
    }

    private void ApplyAppearance()
    {
        if (!_webReady) return;
        try
        {
            _web.CoreWebView2.Profile.PreferredColorScheme = _prefs.AppearanceMode switch
            {
                AppearanceMode.Dark => CoreWebView2PreferredColorScheme.Dark,
                AppearanceMode.Light => CoreWebView2PreferredColorScheme.Light,
                _ => CoreWebView2PreferredColorScheme.Auto
            };
        }
        catch (Exception ex)
        {
            Diag.Log("appearance: " + ex.Message);
        }
    }

    private void ExecJs(string editCommand)
    {
        if (!_webReady) return;
        _ = _web.CoreWebView2.ExecuteScriptAsync("document.execCommand('" + editCommand + "', false, null)");
    }

    // ------------------------------------------------------- 增强 · UA 菜单

    private void SyncUaChecks()
    {
        _uaMenu.DropDownItems.Clear();
        for (int i = 0; i < UaPresets.Length; i++)
        {
            int index = i;
            var item = Item(UaPresets[i].Name, Keys.None, (_, _) => SetUaIndex(index));
            item.Checked = _prefs.UaIndex == index;
            _uaMenu.DropDownItems.Add(item);
        }
        _uaMenu.DropDownItems.Add(new ToolStripSeparator());
        var custom = Item("自定义…", Keys.None, (_, _) => SetCustomUA());
        custom.Checked = _prefs.UaIndex < 0;
        custom.Text = _prefs.UaIndex < 0 ? "自定义…（当前已启用）" : "自定义…";
        _uaMenu.DropDownItems.Add(custom);
        _uaMenu.DropDownItems.Add(Item("重置为默认", Keys.None, (_, _) =>
        {
            _prefs.UaIndex = 0;
            _prefs.CustomUA = "";
            _prefs.Save();
            ApplyUA();
        }));
    }

    private void SetUaIndex(int index)
    {
        _prefs.UaIndex = index;
        _prefs.Save();
        ApplyUA();
    }

    private void SetCustomUA()
    {
        string current = _prefs.UaIndex < 0 ? _prefs.CustomUA : EffectiveUA();
        string? value = Ui.PromptText(this, "自定义 User-Agent",
            "留空则回退到默认 Chrome (Windows) 标识。修改后会重新载入页面。", current);
        if (string.IsNullOrWhiteSpace(value)) return;
        _prefs.CustomUA = value.Trim();
        _prefs.UaIndex = -1;
        _prefs.Save();
        ApplyUA();
    }

    private void ApplyUA()
    {
        if (!_webReady) return;
        _web.CoreWebView2.Settings.UserAgent = EffectiveUA();
        _web.CoreWebView2.Reload();
    }

    // ---------------------------------------------------- 增强 · 页面样式

    private void SyncStyleChecks()
    {
        foreach (ToolStripItem item in _styleMenu.DropDownItems)
        {
            if (item is ToolStripMenuItem mi)
            {
                if (mi.Text.StartsWith("隐藏滚动条")) mi.Checked = _prefs.HideScrollbar;
                if (mi.Text.StartsWith("禁用动画")) mi.Checked = _prefs.NoAnimation;
                if (mi.Text.StartsWith("清除自定义 CSS"))
                {
                    mi.Enabled = !string.IsNullOrWhiteSpace(_prefs.CustomCSS);
                }
                if (mi.Text.StartsWith("自定义 CSS"))
                {
                    mi.Text = string.IsNullOrWhiteSpace(_prefs.CustomCSS) ? "自定义 CSS…" : "自定义 CSS…（已设置）";
                }
            }
        }
    }

    private void EditCustomCSS()
    {
        string? css = Ui.PromptMultiline(this, "自定义 CSS",
            "直接写下要注入的 CSS 规则，会应用到站点的所有页面。", _prefs.CustomCSS);
        if (css == null) return;
        _prefs.CustomCSS = css;
        _prefs.Save();
        ApplyStyles();
    }

    private void ApplyStyles()
    {
        if (!_webReady) return;
        string js = "(function(){ " +
                    "if (window.__scheutiePendingCSS !== undefined) { window.__scheutiePendingCSS = " +
                    JsonSerializer.Serialize(_prefs.CombinedCSS) + "; } " +
                    "if (typeof window.__scheutieApplyCSS === 'function') { return window.__scheutieApplyCSS(" +
                    JsonSerializer.Serialize(_prefs.CombinedCSS) + "); } " +
                    "return 'not-ready'; })();";
        _ = _web.CoreWebView2.ExecuteScriptAsync(js);
    }

    private void ResetAllEnhancements()
    {
        _prefs.AppearanceMode = AppearanceMode.System;
        _prefs.UaIndex = 0;
        _prefs.CustomUA = "";
        _prefs.HideScrollbar = false;
        _prefs.NoAnimation = false;
        _prefs.CustomCSS = "";
        _prefs.Save();
        ApplyAppearance();
        ApplyUA();
        Flash("已重置所有增强设置");
    }

    // ----------------------------------------------------- 增强 · 对话导出

    private async System.Threading.Tasks.Task<string?> ExportMarkdownAsync()
    {
        if (!_webReady) return null;
        string raw = await _web.CoreWebView2.ExecuteScriptAsync(
            "window.__scheutieExportMarkdown ? window.__scheutieExportMarkdown() : null");
        if (raw == "null" || raw.Length == 0) return null;
        try
        {
            return JsonSerializer.Deserialize<string>(raw);
        }
        catch (Exception ex)
        {
            Diag.Log("export deserialize failed: " + ex.Message);
            return null;
        }
    }

    private async void CopyConversationMarkdown()
    {
        string? md = await ExportMarkdownAsync();
        if (string.IsNullOrEmpty(md))
        {
            ShowExportEmpty();
            return;
        }
        try
        {
            Clipboard.SetText(md);
            Flash("已复制 " + md.Length + " 字符的 Markdown 到剪贴板");
        }
        catch (Exception ex)
        {
            Flash("复制失败：" + ex.Message);
        }
    }

    private async void ExportMarkdownToFile()
    {
        string? md = await ExportMarkdownAsync();
        if (string.IsNullOrEmpty(md))
        {
            ShowExportEmpty();
            return;
        }

        using var dialog = new SaveFileDialog
        {
            Title = "导出对话为 Markdown",
            Filter = "Markdown (*.md)|*.md|所有文件 (*.*)|*.*",
            FileName = SuggestedFilename(),
            CheckFileExists = false,
            OverwritePrompt = true
        };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;

        try
        {
            string target = dialog.FileName;
            if (!target.EndsWith(".md", StringComparison.OrdinalIgnoreCase)
                && !target.EndsWith(".markdown", StringComparison.OrdinalIgnoreCase))
            {
                target += ".md";
            }
            File.WriteAllText(target, md, System.Text.Encoding.UTF8);
            _prefs.ExportCount++;
            _prefs.Save();
            Flash("已导出到 " + Path.GetFileName(target));
            try
            {
                Process.Start("explorer.exe", "/select,\"" + target + "\"");
            }
            catch { /* cosmetic */ }
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "导出失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private async void CopyPlainText()
    {
        if (!_webReady) return;
        string raw = await _web.CoreWebView2.ExecuteScriptAsync(
            "document.body ? document.body.innerText : ''");
        string text = raw == "null" ? "" : JsonSerializer.Deserialize<string>(raw) ?? "";
        if (text.Length == 0) return;
        try
        {
            Clipboard.SetText(text);
            Flash("已复制全文（" + text.Length + " 字符）");
        }
        catch (Exception ex)
        {
            Flash("复制失败：" + ex.Message);
        }
    }

    private void PrintPage()
    {
        if (!_webReady) return;
        try
        {
            _web.CoreWebView2.ShowPrintUI();
        }
        catch (Exception ex)
        {
            Diag.Log("ShowPrintUI failed, fallback: " + ex.Message);
            _ = _web.CoreWebView2.ExecuteScriptAsync("window.print()");
        }
    }

    private void ShowExportEmpty()
    {
        MessageBox.Show(this,
            "没能从当前页面提取到对话内容。\n可能页面还没加载完，或站点结构有变化。",
            "导出失败", MessageBoxButtons.OK, MessageBoxIcon.Warning);
    }

    private string SuggestedFilename()
    {
        string title = "";
        if (_webReady) title = _web.CoreWebView2.DocumentTitle ?? "";
        if (title.EndsWith(" — " + Program.AppName, StringComparison.Ordinal))
        {
            title = title[..^(" — " + Program.AppName).Length];
        }
        foreach (char c in Path.GetInvalidFileNameChars()) title = title.Replace(c, '-');
        if (string.IsNullOrWhiteSpace(title)) title = "对话";
        return title + "-" + DateTime.Now.ToString("yyyyMMdd-HHmm") + ".md";
    }

    // ---------------------------------------------------------------- find

    private void ShowFind()
    {
        _findBar.Visible = true;
        _findBox.Focus();
        _findBox.TextBox.SelectAll();
    }

    private void BuildFindBar()
    {
        _findBar = new ToolStrip { Dock = DockStyle.Fill, Visible = false, GripStyle = ToolStripGripStyle.Hidden };
        _findBar.Font = new Font("Microsoft YaHei UI", 9f);
        _findBar.Items.Add(new ToolStripLabel("查找："));
        _findBox = new ToolStripTextBox { Width = 220 };
        _findBox.TextBox.KeyDown += (_, e) =>
        {
            if (e.KeyCode == Keys.Enter)
            {
                e.SuppressKeyPress = true;
                FindNext(e.Shift);
            }
            else if (e.KeyCode == Keys.Escape)
            {
                e.SuppressKeyPress = true;
                HideFind();
            }
        };
        _findBar.Items.Add(_findBox);
        _findBar.Items.Add(Item("上一个", Keys.None, (_, _) => FindNext(true)));
        _findBar.Items.Add(Item("下一个", Keys.None, (_, _) => FindNext(false)));
        _findStatus = new ToolStripLabel("");
        _findBar.Items.Add(_findStatus);
        _findBar.Items.Add(Item("关闭", Keys.None, (_, _) => HideFind()));
    }

    private void HideFind()
    {
        _findBar.Visible = false;
        if (_webReady) _web.Focus();
    }

    private async void FindNext(bool backwards)
    {
        if (!_webReady) return;
        string query = _findBox.Text ?? "";
        if (query.Length == 0)
        {
            _findStatus.Text = "";
            return;
        }

        string qJson = JsonSerializer.Serialize(query);
        string js = "(function(){ var q=" + qJson + ";" +
                    " if(!q){return 'empty:0';}" +
                    " if(window.__sq!==q){window.__sq=q;}" +
                    " var ok=window.find(q,false," + (backwards ? "true" : "false") + ",true,false,false,false);" +
                    " var n=q?document.body.innerText.split(q).length-1:0;" +
                    " return (ok?'hit':'miss')+':'+n; })();";

        try
        {
            string raw = await _web.CoreWebView2.ExecuteScriptAsync(js);
            string result = raw == "null" ? "" : JsonSerializer.Deserialize<string>(raw) ?? "";
            string[] parts = result.Split(':');
            int count = parts.Length > 1 && int.TryParse(parts[1], out int n) ? n : 0;
            _findStatus.Text = parts.Length > 0 && parts[0] == "hit"
                ? "共 " + count + " 处"
                : (count > 0 ? "已到结尾，共 " + count + " 处" : "未找到");
        }
        catch (Exception ex)
        {
            _findStatus.Text = "查找失败";
            Diag.Log("find failed: " + ex.Message);
        }
    }

    // ------------------------------------------------------------ plumbing

    private void Flash(string message)
    {
        Diag.Log(message);
        _statusLabel.Text = message;
        _statusTimer.Stop();
        _statusTimer.Start();
    }

    private void OpenLogFile()
    {
        try
        {
            Directory.CreateDirectory(Paths.AppDataDir);
            if (!File.Exists(Paths.LogFile)) File.WriteAllText(Paths.LogFile, "");
            Process.Start(new ProcessStartInfo(Paths.LogFile) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            Flash("无法打开日志：" + ex.Message);
        }
    }

    private void ShowAbout()
    {
        using var about = new AboutForm();
        about.ShowDialog(this);
    }

    private void AskUninstall()
    {
        if (MessageBox.Show(this,
                "要卸载 ScheutieOS 吗？\n应用将关闭，随后会弹出卸载确认窗口。",
                "卸载 ScheutieOS", MessageBoxButtons.YesNo, MessageBoxIcon.Question)
            != DialogResult.Yes)
        {
            return;
        }
        Uninstaller.SpawnUninstaller();
        ReallyExit();
    }

    private void ShowMain()
    {
        if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
        Show();
        Activate();
    }

    private void ReallyExit()
    {
        _exiting = true;
        SaveBounds();
        _tray.Visible = false;
        Application.Exit();
    }

    private void SaveBounds()
    {
        Rectangle r = WindowState == FormWindowState.Normal ? Bounds : RestoreBounds;
        _prefs.WindowX = r.X;
        _prefs.WindowY = r.Y;
        _prefs.WindowW = r.Width;
        _prefs.WindowH = r.Height;
        _prefs.WindowMaximized = WindowState == FormWindowState.Maximized;
        _prefs.Save();
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (!_exiting && e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;
            SaveBounds();
            Hide();
            if (!_prefs.TrayNoticeShown)
            {
                _prefs.TrayNoticeShown = true;
                _prefs.Save();
                _tray.ShowBalloonTip(4000, "ScheutieOS 仍在运行",
                    "窗口已收到通知区域，双击托盘图标可重新打开。\n完全退出：菜单「文件 → 退出」或 Ctrl+Q。",
                    ToolTipIcon.Info);
            }
            return;
        }
        SaveBounds();
        _tray.Visible = false;
        base.OnFormClosing(e);
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == (int)Program.ShowMainMessage)
        {
            ShowMain();
            return;
        }
        base.WndProc(ref m);
    }

    private static IReadOnlyList<string> UnusedKeepAlive => Array.Empty<string>();
}
