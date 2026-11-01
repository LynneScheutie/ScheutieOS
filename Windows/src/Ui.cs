// Ui.cs — small native input dialogs (mirrors Prompts in the macOS build).

using System;
using System.Drawing;
using System.Windows.Forms;

namespace ScheutieOS;

internal static class Ui
{
    public static string? PromptText(IWin32Window? owner, string title, string message, string value = "")
    {
        using var form = MakePromptForm(title, message, 480, 168);

        var box = new TextBox
        {
            Left = 14, Top = 64, Width = 452,
            Font = new Font("Consolas", 9.5f),
            Text = value,
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
        };
        form.Controls.Add(box);
        AddButtons(form, box);
        form.ActiveControl = box;
        return form.ShowDialog(owner) == DialogResult.OK ? box.Text : null;
    }

    public static string? PromptMultiline(IWin32Window? owner, string title, string message, string value = "")
    {
        using var form = MakePromptForm(title, message, 520, 340);

        var box = new TextBox
        {
            Left = 14, Top = 64, Width = 492, Height = 190,
            Multiline = true,
            ScrollBars = ScrollBars.Both,
            WordWrap = false,
            Font = new Font("Consolas", 9.5f),
            Text = value,
            Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right
        };
        form.Controls.Add(box);
        AddButtons(form, box);
        form.ActiveControl = box;
        return form.ShowDialog(owner) == DialogResult.OK ? box.Text : null;
    }

    private static Form MakePromptForm(string title, string message, int width, int height)
    {
        var form = new Form
        {
            Text = title,
            FormBorderStyle = FormBorderStyle.FixedDialog,
            MaximizeBox = false,
            MinimizeBox = false,
            StartPosition = FormStartPosition.CenterParent,
            ClientSize = new Size(width, height),
            ShowInTaskbar = false,
            Font = new Font("Microsoft YaHei UI", 9f)
        };

        var label = new Label
        {
            Text = message,
            Left = 14, Top = 12, Width = width - 28, Height = 46,
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
        };
        form.Controls.Add(label);
        return form;
    }

    private static void AddButtons(Form form, TextBox anchor)
    {
        var ok = new Button
        {
            Text = "保存",
            DialogResult = DialogResult.OK,
            Size = new Size(88, 28),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Right
        };
        var cancel = new Button
        {
            Text = "取消",
            DialogResult = DialogResult.Cancel,
            Size = new Size(88, 28),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Right
        };
        // Position from the form's current size; anchors keep them put if resized.
        ok.Left = form.ClientSize.Width - 200;
        cancel.Left = form.ClientSize.Width - 102;
        ok.Top = cancel.Top = form.ClientSize.Height - 34;
        form.Controls.Add(ok);
        form.Controls.Add(cancel);
        form.AcceptButton = ok;
        form.CancelButton = cancel;
        _ = anchor; // kept for symmetry with earlier revision
    }
}
