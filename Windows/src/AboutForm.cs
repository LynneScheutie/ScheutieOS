// AboutForm.cs — hand-drawn About window, mirroring the macOS About panel:
// large icon, name, version pill, tagline, divider, developer credit, footer.
//
// Borderless; Esc closes, dragging anywhere moves the window, Windows 11
// rounds the corners via DWM.

using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace ScheutieOS;

internal sealed class AboutForm : Form
{
    private const int W = 420;
    private const int H = 400;

    public AboutForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.CenterParent;
        ClientSize = new Size(W, H);
        ShowInTaskbar = false;
        KeyPreview = true;
        DoubleBuffered = true;

        KeyDown += (_, e) => { if (e.KeyCode == Keys.Escape) Close(); };
        Click += (_, _) => Close();

        TryRoundCorners(Handle);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

        bool dark = Theme.IsDark;
        Color top = dark ? Color.FromArgb(52, 52, 52) : Color.FromArgb(254, 254, 254);
        Color bottom = dark ? Color.FromArgb(37, 37, 37) : Color.FromArgb(241, 241, 241);
        Color mainText = dark ? Color.FromArgb(240, 240, 240) : Color.FromArgb(30, 30, 30);
        Color subText = dark ? Color.FromArgb(170, 170, 170) : Color.FromArgb(110, 110, 110);
        Color faintText = dark ? Color.FromArgb(130, 130, 130) : Color.FromArgb(150, 150, 150);
        Color accent = Color.FromArgb(77, 107, 254);

        using var bg = new LinearGradientBrush(ClientRectangle, top, bottom, 90f);
        g.FillRectangle(bg, ClientRectangle);

        int cx = W / 2;
        int y = 26;

        // icon with a soft shadow
        using (var big = AppIcons.Get(256).ToBitmap())
        {
            var dst = new Rectangle(cx - 56, y, 112, 112);
            using var shadowPath = new GraphicsPath();
            shadowPath.AddEllipse(dst.X + 4, dst.Y + 8, dst.Width, dst.Height);
            using var shadow = new PathGradientBrush(shadowPath);
            shadow.CenterColor = Color.FromArgb(60, 0, 0, 0);
            shadow.SurroundColors = new[] { Color.FromArgb(0, 0, 0, 0) };
            g.FillPath(shadow, shadowPath);
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.DrawImage(big, dst);
        }
        y += 132;

        // app name
        DrawCentered(g, Program.AppName, FontOf(18f, FontStyle.Bold), mainText, cx, ref y, 30);

        // version pill
        string pillText = "版本 " + Program.VersionText + " (build " + Program.BuildText + ")";
        DrawPill(g, pillText, accent, cx, y + 8);
        y += 40;

        // tagline
        DrawCentered(g, Program.Tagline, FontOf(9.5f, FontStyle.Regular), subText, cx, ref y, 22);

        // divider
        y += 12;
        using (var pen = new Pen(dark ? Color.FromArgb(70, 70, 70) : Color.FromArgb(215, 215, 215)))
        {
            g.DrawLine(pen, cx - 110, y, cx + 110, y);
        }
        y += 16;

        // developer caption + name
        DrawCentered(g, "开  发  者", FontOf(8f, FontStyle.Bold), faintText, cx, ref y, 16);
        DrawCentered(g, Program.Developer, FontOf(10.5f, FontStyle.Bold), mainText, cx, ref y, 22);

        // footer
        y += 10;
        DrawCentered(g, "基于 WebView2 构建 · chat.deepseek.com", FontOf(8.5f), faintText, cx, ref y, 18);
        DrawCentered(g, "© 2026 " + Program.Developer, FontOf(8.5f), faintText, cx, ref y, 18);

        // close hint
        DrawCentered(g, "点击任意位置或按 Esc 关闭", FontOf(8f), Color.FromArgb(dark ? 90 : 170, 128, 128, 128), cx, ref y, 16);
    }

    private static Font FontOf(float size, FontStyle style) =>
        new("Microsoft YaHei UI", size, style, GraphicsUnit.Pixel);

    private static void DrawCentered(Graphics g, string text, Font font, Color color, int cx, ref int y, int lineHeight)
    {
        using var b = new SolidBrush(color);
        var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
        var rect = new RectangleF(20, y, W - 40, lineHeight);
        g.DrawString(text, font, b, rect, sf);
        y += lineHeight;
    }

    private void DrawPill(Graphics g, string text, Color accent, int cx, int y)
    {
        using var font = FontOf(9f, FontStyle.Bold);
        SizeF size = g.MeasureString(text, font);
        var rect = new RectangleF(cx - size.Width / 2 - 12, y, size.Width + 24, 24);
        using var path = RoundedRect(rect, 12);
        using (var fill = new SolidBrush(Color.FromArgb(34, accent)))
        {
            g.FillPath(fill, path);
        }
        using (var pen = new Pen(Color.FromArgb(60, accent)))
        {
            g.DrawPath(pen, path);
        }
        using var textBrush = new SolidBrush(accent);
        var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
        g.DrawString(text, font, textBrush, rect, sf);
    }

    private static GraphicsPath RoundedRect(RectangleF r, float radius)
    {
        var path = new GraphicsPath();
        float d = radius * 2;
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    private static void TryRoundCorners(IntPtr handle)
    {
        try
        {
            // DWMWA_WINDOW_CORNER_PREFERENCE = 33, DWMWCP_ROUND = 2 (Windows 11+)
            int preference = 2;
            DwmSetWindowAttribute(handle, 33, ref preference, sizeof(int));
        }
        catch { /* Windows 10: square corners, fine */ }
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= 0x80; // WS_EX_TOOLWINDOW: don't flash in the taskbar / alt-tab
            return cp;
        }
    }
}

internal static class Theme
{
    public static bool IsDark
    {
        get
        {
            try
            {
                var v = Microsoft.Win32.Registry.GetValue(
                    @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
                    "AppsUseLightTheme", 1);
                return v is int i && i == 0;
            }
            catch
            {
                return false;
            }
        }
    }
}
