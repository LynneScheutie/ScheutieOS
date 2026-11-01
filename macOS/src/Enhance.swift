// Enhance.swift — ScheutieOS enhancement layer
// Appearance override, custom User-Agent, injected CSS, conversation -> Markdown export.

import Cocoa
import WebKit

// MARK: - Preferences (persisted in UserDefaults)

enum AppearanceMode: Int, CaseIterable {
    case system = 0
    case dark = 1
    case light = 2

    var title: String {
        switch self {
        case .system: return L.t("跟随系统")
        case .dark:   return L.t("强制暗色")
        case .light:  return L.t("强制亮色")
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .dark:   return NSAppearance(named: .darkAqua)
        case .light:  return NSAppearance(named: .aqua)
        }
    }
}

struct UserAgentPreset {
    /// Chinese source string used as the L10n key — resolve with `L.t(name)`
    /// wherever it is displayed, never store the resolved text.
    let name: String
    let value: String
}

let kUserAgentPresets: [UserAgentPreset] = [
    UserAgentPreset(
        name: "Safari (macOS) — 默认",
        value: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Safari/605.1.15"
    ),
    UserAgentPreset(
        name: "Chrome (macOS)",
        value: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
    ),
    UserAgentPreset(
        name: "Chrome (Windows)",
        value: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
    ),
    UserAgentPreset(
        name: "Safari (iPhone)",
        value: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    ),
    UserAgentPreset(
        name: "Safari (iPad)",
        value: "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    )
]

final class Prefs {
    static let shared = Prefs()
    private let d = UserDefaults.standard
    private let kCustomUAIndex = -1

    private init() {
        d.register(defaults: [
            "appearanceMode": AppearanceMode.system.rawValue,
            "language": AppLanguage.chinese.rawValue,
            "uaIndex": 0,
            "customUA": "",
            "hideScrollbar": false,
            "noAnimation": false,
            "customCSS": "",
            "pageZoom": 1.0,
            "exportCount": 0
        ])
    }

    /// Interface language of the app chrome (menus / dialogs / About).
    var language: AppLanguage {
        get { AppLanguage(rawValue: d.integer(forKey: "language")) ?? .chinese }
        set { d.set(newValue.rawValue, forKey: "language") }
    }

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: d.integer(forKey: "appearanceMode")) ?? .system }
        set { d.set(newValue.rawValue, forKey: "appearanceMode") }
    }

    /// -1 means "custom UA is in use"
    var uaIndex: Int {
        get { d.integer(forKey: "uaIndex") }
        set { d.set(newValue, forKey: "uaIndex") }
    }

    var customUA: String {
        get { d.string(forKey: "customUA") ?? "" }
        set { d.set(newValue, forKey: "customUA") }
    }

    var effectiveUA: String {
        if uaIndex >= 0 && uaIndex < kUserAgentPresets.count {
            return kUserAgentPresets[uaIndex].value
        }
        let c = customUA.trimmingCharacters(in: .whitespacesAndNewlines)
        return c.isEmpty ? kUserAgentPresets[0].value : c
    }

    var hideScrollbar: Bool {
        get { d.bool(forKey: "hideScrollbar") }
        set { d.set(newValue, forKey: "hideScrollbar") }
    }

    var noAnimation: Bool {
        get { d.bool(forKey: "noAnimation") }
        set { d.set(newValue, forKey: "noAnimation") }
    }

    var customCSS: String {
        get { d.string(forKey: "customCSS") ?? "" }
        set { d.set(newValue, forKey: "customCSS") }
    }

    var pageZoom: Double {
        get { d.double(forKey: "pageZoom") }
        set { d.set(newValue, forKey: "pageZoom") }
    }

    var exportCount: Int {
        get { d.integer(forKey: "exportCount") }
        set { d.set(newValue, forKey: "exportCount") }
    }

    /// CSS assembled from the toggles + user's custom rules.
    var combinedCSS: String {
        var parts: [String] = []
        if hideScrollbar {
            parts.append("""
            html, body, * { scrollbar-width: none !important; -ms-overflow-style: none !important; }
            ::-webkit-scrollbar { width: 0 !important; height: 0 !important; display: none !important; }
            """)
        }
        if noAnimation {
            parts.append("""
            *, *::before, *::after {
              animation-duration: 0.001ms !important;
              animation-delay: 0ms !important;
              animation-iteration-count: 1 !important;
              transition-duration: 0.001ms !important;
              transition-delay: 0ms !important;
              scroll-behavior: auto !important;
            }
            """)
        }
        let custom = customCSS.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { parts.append(custom) }
        return parts.joined(separator: "\n\n")
    }

    var hasAnyStyle: Bool {
        return hideScrollbar || noAnimation
            || !customCSS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Local diagnostic log
//
// NSLog output is unreadable from a sandboxed shell (`log` refuses to run), so we
// mirror everything to ~/Library/Logs/ScheutieOS.log — inspect it any time with
// `tail -f ~/Library/Logs/ScheutieOS.log`.

enum Diag {
    private static let maxBytes = 256 * 1024

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Logs/ScheutieOS.log")
    }

    /// Written synchronously on purpose: an async append loses the last lines
    /// whenever the process exits right after logging (which is exactly what the
    /// self-test does), and a diagnostic log that drops its last line is worse
    /// than useless. Volume is a handful of lines per launch.
    static func log(_ message: String) {
        NSLog("[ScheutieOS] %@", message)
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        let line = "[\(f.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let fm = FileManager.default
        let url = fileURL
        try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        if let attrs = try? fm.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int, size > maxBytes {
            try? fm.removeItem(at: url)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    /// Kept for callers that want to make sure everything is on disk.
    static func flush() {}
}

// MARK: - Injected JavaScript

enum InjectedJS {

    /// Installed once per page load. Provides `__scheutieApplyCSS` and
    /// `__scheutieExportMarkdown`.
    static let runtime = #"""
    (function () {
      if (window.__scheutieInstalled) { return; }
      window.__scheutieInstalled = true;

      // ---------- CSS injection (CSP-proof: constructed stylesheet first) ----------
      function sheet() {
        try {
          if (!window.__scheutieSheet && 'adoptedStyleSheets' in document) {
            window.__scheutieSheet = new CSSStyleSheet();
            document.adoptedStyleSheets = document.adoptedStyleSheets.concat([window.__scheutieSheet]);
          }
        } catch (e) { window.__scheutieSheet = null; }
        return window.__scheutieSheet || null;
      }

      window.__scheutieApplyCSS = function (css) {
        css = css || '';
        var s = sheet();
        if (s) {
          try { s.replaceSync(css); return 'adopted'; } catch (e) { }
        }
        try {
          var el = document.getElementById('__scheutie_style');
          if (!el) {
            el = document.createElement('style');
            el.id = '__scheutie_style';
            (document.head || document.documentElement).appendChild(el);
          }
          el.textContent = css;
          return 'inline';
        } catch (e) { return 'failed: ' + e.message; }
      };

      // ---------- Markdown export ----------
      function tagOf(el) { return (el.tagName || '').toLowerCase(); }

      // innerText is layout-aware and preferred; textContent is the fallback so the
      // converter also works in DOM implementations without innerText (e.g. tests).
      function textOf(el) {
        if (!el) { return ''; }
        if (typeof el.innerText === 'string') { return el.innerText; }
        return el.textContent || '';
      }

      var SKIP = { script: 1, style: 1, noscript: 1, svg: 1, button: 1, select: 1, textarea: 1, iframe: 1, canvas: 1 };
      var BLOCK = { p: 1, div: 1, section: 1, article: 1, main: 1, ul: 1, ol: 1, li: 1, table: 1,
                    thead: 1, tbody: 1, tr: 1, td: 1, th: 1, pre: 1, blockquote: 1, header: 1,
                    footer: 1, aside: 1, nav: 1, figure: 1, figcaption: 1, h1: 1, h2: 1, h3: 1,
                    h4: 1, h5: 1, h6: 1, hr: 1, form: 1 };

      function clean(s) {
        return (s || '')
          .replace(/[ \t\u00a0]+/g, ' ')
          .replace(/[ ]+\n/g, '\n')
          .trim();
      }

      function hasBlockChild(el) {
        var kids = el.children || [];
        for (var i = 0; i < kids.length; i++) {
          if (BLOCK[tagOf(kids[i])]) { return true; }
        }
        return false;
      }

      function inline(el) {
        var out = '';
        var kids = el.childNodes;
        for (var i = 0; i < kids.length; i++) {
          var n = kids[i];
          if (n.nodeType === 3) { out += n.nodeValue; continue; }
          if (n.nodeType !== 1) { continue; }
          var t = tagOf(n);
          if (SKIP[t]) { continue; }
          if (n.getAttribute && n.getAttribute('aria-hidden') === 'true') { continue; }
          if (t === 'br') { out += '\n'; continue; }
          if (n.getAttribute && n.getAttribute('data-url') && !textOf(n).trim()) { continue; }
          if (t === 'strong' || t === 'b') {
            var a = clean(inline(n)); if (a) { out += '**' + a.replace(/\n/g, ' ') + '**'; } continue;
          }
          if (t === 'em' || t === 'i') {
            var b = clean(inline(n)); if (b) { out += '*' + b.replace(/\n/g, ' ') + '*'; } continue;
          }
          if (t === 'del' || t === 's') {
            var c = clean(inline(n)); if (c) { out += '~~' + c.replace(/\n/g, ' ') + '~~'; } continue;
          }
          if (t === 'code') {
            var d = clean(textOf(n));
            if (d) { out += '`' + d.replace(/\n/g, ' ') + '`'; } continue;
          }
          if (t === 'a') {
            var href = n.getAttribute('href') || '';
            var tx = clean(inline(n)).replace(/\n/g, ' ');
            if (!tx) { continue; }
            out += (href && href.indexOf('javascript:') !== 0) ? '[' + tx + '](' + href + ')' : tx;
            continue;
          }
          out += inline(n);
        }
        return out;
      }

      function walk(node, out, depth) {
        var kids = node.childNodes;
        for (var i = 0; i < kids.length; i++) {
          var n = kids[i];
          if (n.nodeType === 3) {
            var tt = clean(n.nodeValue);
            if (tt) { out.push(tt); }
            continue;
          }
          if (n.nodeType !== 1) { continue; }
          var t = tagOf(n);
          if (SKIP[t]) { continue; }
          if (n.getAttribute && n.getAttribute('aria-hidden') === 'true') { continue; }
          if (n.getAttribute && n.getAttribute('role') === 'toolbar') { continue; }

          if (t === 'br') { out.push('\n'); continue; }
          if (t === 'hr') { out.push('\n---\n'); continue; }

          if (/^h[1-6]$/.test(t)) {
            var lv = parseInt(t.slice(1), 10);
            var ht = clean(inline(n)).replace(/\n/g, ' ');
            if (ht) { out.push('\n' + new Array(lv + 1).join('#') + ' ' + ht + '\n'); }
            continue;
          }

          if (t === 'pre') {
            var cEl = n.querySelector('code');
            var cls = (cEl && cEl.className) ? String(cEl.className) : '';
            var m = cls.match(/language-([\w+#.-]+)/i);
            var lang = m ? m[1] : '';
            var code = textOf(cEl || n).replace(/\s+$/, '');
            if (code.trim()) { out.push('\n```' + lang + '\n' + code + '\n```\n'); }
            continue;
          }

          if (t === 'blockquote') {
            var bt = clean(inline(n));
            if (bt) {
              out.push('\n' + bt.split('\n').map(function (x) { return '> ' + x; }).join('\n') + '\n');
            }
            continue;
          }

          if (t === 'li') {
            var pad = new Array((depth || 0) + 1).join('  ');
            // Text of the item itself, plus any nested lists emitted separately.
            var own = '';
            var subLists = [];
            for (var q = 0; q < n.childNodes.length; q++) {
              var cn = n.childNodes[q];
              if (cn.nodeType === 3) { own += cn.nodeValue; continue; }
              if (cn.nodeType !== 1) { continue; }
              var ct = tagOf(cn);
              if (ct === 'ul' || ct === 'ol') { subLists.push(cn); continue; }
              own += inline(cn);
            }
            var lt = clean(own);
            if (lt) { out.push(pad + '- ' + lt.replace(/\n/g, '\n' + pad + '  ') + '\n'); }
            for (var s = 0; s < subLists.length; s++) {
              walk(subLists[s], out, (depth || 0) + 1);
            }
            continue;
          }

          if (t === 'tr') {
            var cells = [];
            var hasHeader = false;
            for (var k = 0; k < n.children.length; k++) {
              if (tagOf(n.children[k]) === 'th') { hasHeader = true; }
              cells.push(clean(inline(n.children[k])).replace(/\n/g, ' '));
            }
            if (cells.join('').length) {
              out.push('| ' + cells.join(' | ') + ' |\n');
              if (hasHeader) {
                out.push('|' + cells.map(function () { return ' --- '; }).join('|') + '|\n');
              }
            }
            continue;
          }

          if (t === 'table') {
            out.push('\n');
            walk(n, out, depth);
            out.push('\n');
            continue;
          }

          if (BLOCK[t] || t === 'span') {
            if (hasBlockChild(n)) {
              // List depth is applied by the `li` handler, not here — otherwise a
              // top-level <ul> would indent every one of its items.
              walk(n, out, depth);
            } else {
              var pt = clean(inline(n));
              if (pt) { out.push(pt + '\n'); }
            }
            continue;
          }

          walk(n, out, depth);
        }
      }

      // Descend into the child that still holds most of the text — finds the
      // tightest container wrapping the whole conversation.
      //
      // The guard matters: when one reply is much longer than the question, the
      // plain ">=60% of text" rule happily descends into that single bubble and
      // silently drops the rest of the conversation. So refuse to descend into
      // anything that looks like one message.
      var SINGLE_MESSAGE = /(^|[-_\s])(message|msg|bubble|markdown|prose|reply|response|answer|turn|chat-item|conversation-item)([-_\s]|$)/i;

      function looksLikeOneMessage(el) {
        var cls = (typeof el.className === 'string') ? el.className : '';
        if (SINGLE_MESSAGE.test(cls)) { return true; }
        if (!el.getAttribute) { return false; }
        if (el.getAttribute('role') === 'article') { return true; }
        if (el.hasAttribute && (el.hasAttribute('data-message-id') || el.hasAttribute('data-msg-id'))) {
          return true;
        }
        var tid = el.getAttribute('data-testid') || '';
        if (/message|chat-item/i.test(tid)) { return true; }
        return false;
      }

      function pickRoot() {
        var cur = document.body;
        if (!cur) { return null; }
        for (var depth = 0; depth < 30; depth++) {
          var curLen = textOf(cur).length;
          if (curLen < 200) { break; }
          var next = null, nextLen = 0;
          var kids = cur.children || [];
          for (var i = 0; i < kids.length; i++) {
            var k = kids[i];
            var kt = tagOf(k);
            if (SKIP[kt] || kt === 'nav' || kt === 'aside') { continue; }
            var l = textOf(k).length;
            if (l > nextLen) { nextLen = l; next = k; }
          }
          if (!next || nextLen < curLen * 0.6) { break; }
          if (looksLikeOneMessage(next)) { break; }
          cur = next;
        }
        return cur;
      }

      // Blocks are emitted with their own trailing newline and then joined with
      // "\n\n", which over-separates consecutive list items and table rows. Pull
      // those back together so Markdown renders them as one list / one table.
      function tighten(s) {
        var prev;
        for (var i = 0; i < 12; i++) {
          prev = s;
          s = s.replace(/(^[ \t]*- .*)$\n\n(?=^[ \t]*- )/gm, '$1\n');
          s = s.replace(/(^[ \t]*\|.*\|)$\n\n(?=^[ \t]*\|)/gm, '$1\n');
          if (s === prev) { break; }
        }
        return s;
      }

      window.__scheutieExportMarkdown = function () {
        try {
          var root = pickRoot() || document.body;
          var out = [];
          walk(root, out, 0);
          var md = out.join('\n')
            .replace(/[ \t]+$/gm, '')
            .replace(/\n{3,}/g, '\n\n')
            .trim();
          md = tighten(md);

          if (md.replace(/\s/g, '').length < 40) {
            md = clean(textOf(root));
          }

          var title = (document.title || '对话').replace(/\s*[-—]\s*ScheutieOS\s*$/, '');
          var now = new Date();
          function p2(x) { return (x < 10 ? '0' : '') + x; }
          var stamp = now.getFullYear() + '-' + p2(now.getMonth() + 1) + '-' + p2(now.getDate())
                    + ' ' + p2(now.getHours()) + ':' + p2(now.getMinutes());

          var header = '# ' + title + '\n\n'
                     + '> 来源: ' + location.href + '\n'
                     + '> 导出时间: ' + stamp + '\n\n---\n\n';

          return header + md;
        } catch (e) {
          return '# 导出失败\n\n' + (e && e.message ? e.message : String(e));
        }
      };

      // ---------- plain text / selection / stats ----------
      function rootFor() { return pickRoot() || document.body; }

      window.__scheutieExportPlainText = function () {
        try {
          return clean(textOf(rootFor()));
        } catch (e) { return ''; }
      };

      // Markdown for just the current selection — the common case of wanting one
      // answer rather than the whole conversation. Reuses the same walker by
      // parking a clone of the selection in a detached container.
      window.__scheutieExportSelection = function () {
        try {
          var sel = window.getSelection();
          if (!sel || sel.rangeCount === 0 || sel.isCollapsed) { return ''; }
          var holder = document.createElement('div');
          for (var i = 0; i < sel.rangeCount; i++) {
            holder.appendChild(sel.getRangeAt(i).cloneContents());
          }
          var out = [];
          walk(holder, out, 0);
          var md = out.join('\n')
            .replace(/[ \t]+$/gm, '')
            .replace(/\n{3,}/g, '\n\n')
            .trim();
          md = tighten(md);
          if (md.replace(/\s/g, '').length < 2) { md = clean(textOf(holder)); }
          return md;
        } catch (e) { return ''; }
      };

      window.__scheutieCountText = function () {
        try {
          var t = clean(textOf(rootFor())) || '';
          var cjk = (t.match(/[\u3400-\u4dbf\u4e00-\u9fff]/g) || []).length;
          var words = (t.match(/[A-Za-z0-9]+/g) || []).length;
          return JSON.stringify({
            chars: t.replace(/\s/g, '').length,
            cjk: cjk,
            words: words,
            raw: t.length
          });
        } catch (e) { return '{}'; }
      };

      // Called by the host right after load so CSS survives reloads.
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function () {
          if (window.__scheutiePendingCSS !== undefined) {
            window.__scheutieApplyCSS(window.__scheutiePendingCSS);
          }
        });
      }
    })();
    """#
}

// MARK: - Native input prompts

enum Prompts {

    static func text(title: String, message: String, defaultValue: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L.t("保存"))
        alert.addButton(withTitle: L.t("取消"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 460, height: 24))
        field.stringValue = defaultValue
        field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    static func multiline(title: String, message: String, defaultValue: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L.t("保存"))
        alert.addButton(withTitle: L.t("取消"))

        let box = NSRect(x: 0, y: 0, width: 480, height: 220)
        let scroll = NSScrollView(frame: box)
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let tv = NSTextView(frame: box)
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.string = defaultValue
        scroll.documentView = tv
        alert.accessoryView = scroll
        alert.window.initialFirstResponder = tv
        return alert.runModal() == .alertFirstButtonReturn ? tv.string : nil
    }
}
