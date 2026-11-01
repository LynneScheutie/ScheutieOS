// ScheutieOS
// A minimal native macOS window app that hosts chat.deepseek.com in a WKWebView.
// Gives a real windowed app: Dock icon, own session, no browser chrome.

import Cocoa
import WebKit

let kAppName = "ScheutieOS"
let kStartURL = "https://chat.deepseek.com/"
let kHomeURL  = URL(string: "https://chat.deepseek.com/")!

/// One window with exactly one web view.
///
/// The app has no tabs on purpose: a new chat means a new window (⌘N), and every
/// window owns exactly one page, so there is never a tab strip to manage. This
/// type is what lets a single AppDelegate serve N windows.
final class WindowSession: NSObject {
    let window: NSWindow
    let webView: WKWebView
    var titleObservation: NSKeyValueObservation?

    init(window: NSWindow, webView: WKWebView) {
        self.window = window
        self.webView = webView
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate,
                         NSMenuItemValidation, NSWindowDelegate,
                         WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate {

    /// Every open window, in creation order. A window is dropped from the list
    /// the moment it closes, so the Window menu never accumulates dead entries.
    private(set) var sessions: [WindowSession] = []

    var loadCount = 0

    /// The window that menu commands act on.
    ///
    /// `keyWindow` can be an auxiliary panel (About, find), which is not one of
    /// ours, so `mainWindow` gets first say before falling back to the last
    /// window created.
    var keySession: WindowSession? {
        if let w = NSApp.mainWindow, let s = session(for: w) { return s }
        if let w = NSApp.keyWindow,  let s = session(for: w) { return s }
        return sessions.last
    }

    /// Computed rather than stored: every existing `self.window` / `self.webView`
    /// call site keeps working, but now resolves against the frontmost window
    /// instead of one global object.
    var window: NSWindow! { keySession?.window }
    var webView: WKWebView! { keySession?.webView }

    /// Where the last window that closed was pointing. Bringing a window back
    /// after all of them are gone restores that page instead of dumping the user
    /// on a blank start screen.
    private var lastClosedURL: URL?

    func session(for window: NSWindow) -> WindowSession? {
        sessions.first { $0.window === window }
    }

    // 增强 menu
    var appearanceMenu: NSMenu!
    var languageMenu: NSMenu!
    var uaMenu: NSMenu!
    var styleMenu: NSMenu!
    /// Held as a reference because `menuNeedsUpdate` has to recognise it and strip
    /// the tab commands macOS injects into the View menu.
    var viewMenu: NSMenu!

    // Style items are held as references, never looked up by title: titles are
    // localized, so a title lookup would silently stop matching after a
    // language switch.
    var styleHideScrollbar: NSMenuItem!
    var styleNoAnimation: NSMenuItem!
    var styleCustomCSS: NSMenuItem!
    var styleClearCustomCSS: NSMenuItem!

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diag.log("argv → [\(CommandLine.arguments.dropFirst().joined(separator: " "))]")

        // macOS 的 automatic window tabbing 会往「显示」菜单里注入「显示标签页栏 /
        // 显示所有标签页 / 移至新窗口」等一整族命令。本 app 的模型是「一窗一页、
        // ⌘N 开新窗口」，压根不存在标签页，那族命令只会误导人以为有标签页功能。
        // 文档要求在任何窗口创建之前关掉，所以放在最前面。
        NSWindow.allowsAutomaticWindowTabbing = false

        // Language must be resolved before the menu is built: menu titles are
        // localized at construction time.
        let prefs = Prefs.shared
        L.set(prefs.language)
        buildMenuBar()

        openWindow(restoring: URL(string: kStartURL))

        NSApp.activate(ignoringOtherApps: true)
        Diag.log("=== ScheutieOS launch · appearance=\(prefs.appearanceMode.title) "
                 + "ua=\(prefs.effectiveUA.prefix(48)) zoom=\(prefs.pageZoom) "
                 + "automaticTabbing=\(NSWindow.allowsAutomaticWindowTabbing) ===")

        if CommandLine.arguments.contains("--self-test-close") {
            runCloseBehaviourSelfTest()
        }
        if CommandLine.arguments.contains("--self-test-windows") {
            runMultiWindowSelfTest()
        }
        if CommandLine.arguments.contains("--self-test-tabs") {
            runTabSuppressionSelfTest()
        }
        if CommandLine.arguments.contains("--dump-menu") {
            runMenuDump()
        }
    }

    // MARK: - Windows
    //
    // One window = one page. ⌘N adds a window, and nothing in the app ever adds a
    // tab, so the "how many tabs" question never comes up.

    /// Builds one window + web view, registers the session and returns it.
    /// Everything that used to live in `applicationDidFinishLaunching` and had to
    /// happen exactly once now happens once *per window*.
    @discardableResult
    private func openWindow(restoring url: URL?) -> WindowSession {
        let prefs = Prefs.shared

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()            // persistent cookies / login
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.isElementFullscreenEnabled = true

        // Enhancement runtime: CSS injection + Markdown export helpers.
        let ucc = WKUserContentController()
        ucc.addUserScript(WKUserScript(source: InjectedJS.runtime,
                                       injectionTime: .atDocumentEnd,
                                       forMainFrameOnly: true))
        config.userContentController = ucc

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = prefs.effectiveUA
        wv.uiDelegate = self
        wv.navigationDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        // Pinch-to-zoom also disabled — same accidental-zoom problem as ⌘+/-.
        wv.allowsMagnification = false
        wv.appearance = prefs.appearanceMode.appearance

        let isFirst = sessions.isEmpty

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = kAppName
        win.minSize = NSSize(width: 440, height: 440)
        // Critical: a programmatically created NSWindow is released when closed by
        // default. Without this, the session would keep a dangling window.
        win.isReleasedWhenClosed = false
        // Automatic tabbing is off app-wide, but state it per window too so a
        // window can never be pulled into a native tab group.
        win.tabbingMode = .disallowed
        win.contentView = wv
        win.delegate = self

        let session = WindowSession(window: win, webView: wv)
        sessions.append(session)

        session.titleObservation = wv.observe(\.title, options: [.new]) { [weak win] wv, _ in
            guard let win = win else { return }
            let t = (wv.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty || t.contains("deepseek.com") || t.lowercased() == "deepseek" {
                win.title = kAppName
            } else {
                win.title = "\(t) — \(kAppName)"
            }
        }

        // Only the first window remembers its frame; the rest cascade off the
        // previous one so a new window never lands exactly on top of the old.
        if isFirst {
            win.setFrameAutosaveName("ScheutieOSMainWindow")
            if !win.setFrameUsingName("ScheutieOSMainWindow") { win.center() }
        } else if let prev = sessions.dropLast().last?.window, prev.isVisible {
            var f = win.frame
            f.origin = NSPoint(x: prev.frame.origin.x + 28, y: prev.frame.origin.y - 28)
            win.setFrame(f, display: false)
        } else {
            win.center()
        }
        win.makeKeyAndOrderFront(nil)

        // Restore remembered zoom
        let z = prefs.pageZoom
        if z > 0.01 { wv.pageZoom = CGFloat(min(max(z, 0.4), 3.0)) }

        if let url = url { wv.load(URLRequest(url: url)) }
        Diag.log("openWindow → sessions=\(sessions.count) url=\(url?.absoluteString ?? "-")")
        return session
    }

    /// ⌘N — always a brand new chat window.
    @objc private func newWindow() {
        openWindow(restoring: URL(string: kStartURL))
        NSApp.activate(ignoringOtherApps: true)
    }

    /// NSWindowDelegate: drop the session so the Window menu stays truthful.
    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow,
              let idx = sessions.firstIndex(where: { $0.window === w }) else { return }
        let s = sessions[idx]
        if let u = s.webView.url, u.host?.hasSuffix("deepseek.com") == true {
            lastClosedURL = u
        }
        s.titleObservation?.invalidate()
        sessions.remove(at: idx)
        Diag.log("windowWillClose → sessions=\(sessions.count) "
                 + "remembered=\(lastClosedURL?.absoluteString ?? "-")")
    }

    /// Verifies that closing the last window does not terminate the process and
    /// that a window comes back afterwards. Needs the app running, so it is
    /// driven from the real app rather than from an external tool.
    private func runCloseBehaviourSelfTest() {
        let step = 3.0
        DispatchQueue.main.asyncAfter(deadline: .now() + step) {
            guard let first = self.sessions.first else {
                Diag.log("selftest FAIL: no window at launch")
                exit(1)
            }
            Diag.log("selftest[1] before close: sessions=\(self.sessions.count) "
                     + "windowVisible=\(first.window.isVisible)")
            let remembered = first.webView.url
            first.window.performClose(nil)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // If applicationShouldTerminateAfterLastWindowClosed were true the
                // process would already be gone and this line would never appear.
                let goneCount = self.sessions.count
                let survived = goneCount == 0
                Diag.log("selftest[2] after performClose: sessions=\(goneCount) "
                         + "closedWindowRemoved=\(survived)")
                guard survived else {
                    Diag.log("selftest FAIL: closed window still registered")
                    exit(1)
                }
                self.showMainWindow()

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard let back = self.sessions.first else {
                        Diag.log("selftest FAIL: reopen produced no window")
                        exit(1)
                    }
                    let reopened = back.window.isVisible
                    let sessionAlive = back.webView.superview != nil
                    Diag.log("selftest[3] after reopen: sessions=\(self.sessions.count) "
                             + "windowVisible=\(reopened) webViewAlive=\(sessionAlive) "
                             + "url=\(back.webView.url?.absoluteString ?? "-")")
                    let pass = reopened && sessionAlive
                    Diag.log("selftest \(pass ? "PASS" : "FAIL"): "
                             + "close-removes-window=\(survived) "
                             + "app-survived-close=true reopen-ok=\(reopened) "
                             + "remembered=\(remembered?.absoluteString ?? "-")")
                    exit(pass ? 0 : 1)
                }
            }
        }
    }

    /// Verifies the multi-window model end to end: ⌘N adds a window, every window
    /// owns exactly one web view, closing a window retires exactly that session,
    /// and no command ever asks for a tab.
    ///   ./ScheutieOS --self-test-windows
    private func runMultiWindowSelfTest() {
        let report: (String) -> Void = { Diag.log($0) }
        var failures: [String] = []

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            let atLaunch = self.sessions.count
            report("selftest-win[1] at launch: sessions=\(atLaunch)")
            if atLaunch != 1 { failures.append("launch should open exactly 1 window, got \(atLaunch)") }

            self.newWindow()
            self.newWindow()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let after = self.sessions.count
                report("selftest-win[2] after 2× ⌘N: sessions=\(after)")
                if after != 3 { failures.append("expected 3 windows after 2× new, got \(after)") }

                // Each window must own its own web view — that is what "one window
                // one page" means, and it is the mechanical opposite of tabs.
                let ids = Set(self.sessions.map { ObjectIdentifier($0.webView) })
                let windows = Set(self.sessions.map { ObjectIdentifier($0.window) })
                report("selftest-win[3] distinct webViews=\(ids.count) distinct windows=\(windows.count)")
                if ids.count != after { failures.append("web views are shared between windows") }
                if windows.count != after { failures.append("windows are not distinct") }
                for s in self.sessions where s.webView.superview == nil {
                    failures.append("a web view is not attached to any window")
                }

                // The frontmost window must be the one commands act on.
                let expected = self.sessions.last!
                if self.keySession?.window !== expected.window {
                    failures.append("keySession did not follow the newest window")
                }

                // Closing one window must retire exactly one session.
                expected.window.performClose(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let left = self.sessions.count
                    report("selftest-win[4] after closing the front window: sessions=\(left)")
                    if left != after - 1 {
                        failures.append("closing one window changed the count by \(after - left)")
                    }
                    // No tabs anywhere: the app must not expose a tab API, and no
                    // window may carry an NSTabView-based content view.
                    let tabViews = self.sessions.filter { s in
                        s.window.contentView?.subviews.contains { $0 is NSTabView } ?? false
                    }
                    report("selftest-win[5] windows containing a tab view=\(tabViews.count)")
                    if !tabViews.isEmpty { failures.append("a window grew a tab strip") }

                    if failures.isEmpty {
                        Diag.log("selftest-win PASS: \(left) window(s) left, "
                                 + "one web view each, no tabs")
                        exit(0)
                    } else {
                        Diag.log("selftest-win FAIL: \(failures.joined(separator: " ;; "))")
                        exit(1)
                    }
                }
            }
        }
    }

    /// Proves the tab feature is off at the source, and that the menu items macOS
    /// injects are gone even when AppKit only injects them at menu-open time.
    ///   ./ScheutieOS --self-test-tabs
    private func runTabSuppressionSelfTest() {
        var failures: [String] = []

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            // 1) The app-wide switch. Must be read *after* a window exists, since
            //    any window creation is what would re-arm tabbing.
            let appWide = NSWindow.allowsAutomaticWindowTabbing
            Diag.log("selftest-tabs[1] allowsAutomaticWindowTabbing=\(appWide)")
            if appWide { failures.append("automatic window tabbing is still enabled app-wide") }

            // 2) Per window, so a window can never join a tab group.
            for (i, s) in self.sessions.enumerated() {
                let raw = s.window.tabbingMode.rawValue
                Diag.log("selftest-tabs[2] window#\(i) tabbingMode=\(raw) (2 == disallowed)")
                if s.window.tabbingMode != .disallowed {
                    failures.append("window#\(i) tabbingMode=\(raw), expected disallowed")
                }
            }

            // 3) Injection is lazy, so add a real AppKit-shaped tab command by hand
            //    and confirm the stripper removes it. Without this the check would
            //    pass vacuously whenever AppKit happens not to inject.
            let fake = NSMenuItem(title: "显示标签页栏",
                                  action: NSSelectorFromString("toggleTabBar:"),
                                  keyEquivalent: "")
            self.viewMenu.addItem(fake)
            let stripped = self.stripTabCommands(from: self.viewMenu)
            Diag.log("selftest-tabs[3] injected toggleTabBar: → stripped \(stripped)")
            if stripped < 1 { failures.append("tab stripper did not remove an injected tab command") }

            // 4) Full flow: let AppKit update the menu, then run the delegate hook
            //    exactly as AppKit does before showing it, then look for survivors.
            self.viewMenu.update()
            self.menuNeedsUpdate(self.viewMenu)
            let survivors = self.viewMenu.items.compactMap { item -> String? in
                guard let a = item.action else { return nil }
                return AppDelegate.tabCommandNames.contains(NSStringFromSelector(a))
                    ? item.title : nil
            }
            Diag.log("selftest-tabs[4] tab commands left in 显示 menu=\(survivors.count) \(survivors)")
            if !survivors.isEmpty {
                failures.append("tab command(s) survived: \(survivors.joined(separator: ","))")
            }

            if failures.isEmpty {
                Diag.log("selftest-tabs PASS: tabbing disallowed, 显示 menu carries no tab commands")
                exit(0)
            } else {
                Diag.log("selftest-tabs FAIL: \(failures.joined(separator: " ;; "))")
                exit(1)
            }
        }
    }

    // Closing the window must NOT quit the app — ⌘Q is the only way out.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Clicking the Dock icon with no window open brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Every window shares one zoom preference, so the frontmost live value wins.
        for s in sessions {
            s.titleObservation?.invalidate()
            if s.webView.pageZoom > 0.01 {
                Prefs.shared.pageZoom = Double(s.webView.pageZoom)
            }
        }
    }

    // MARK: - About

    @objc private func showAbout() {
        AboutWindowController.shared.present()
    }

    // MARK: - Main window (re)opening

    @objc func showMainWindow() {
        guard let s = sessions.last(where: { $0.window.isVisible }) ?? sessions.last else {
            // Every window was closed: bring one back where the user left off
            // rather than on a blank start page.
            openWindow(restoring: lastClosedURL ?? URL(string: kStartURL))
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if s.window.isMiniaturized { s.window.deminiaturize(nil) }
        s.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Diag.log("showMainWindow visible=\(s.window.isVisible) sessions=\(sessions.count)")
    }

    // MARK: - Menu bar

    private func buildMenuBar() {
        let mainMenu = NSMenu()

        // Application menu
        let appMenuItem = NSMenuItem(title: kAppName, action: nil, keyEquivalent: "")
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        let appName = kAppName
        let aboutItem = NSMenuItem(title: L.t("关于 \(appName)"),
                                   action: #selector(showAbout),
                                   keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L.t("隐藏 \(appName)"),
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: L.t("隐藏其他"),
                                    action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: L.t("显示全部"),
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L.t("退出 \(appName)"),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit menu — required for Cmd+C/V/X/A to reach the web view
        let editMenuItem = NSMenuItem(title: L.t("编辑"), action: nil, keyEquivalent: "")
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: L.t("编辑"))
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: L.t("撤销"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: L.t("重做"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L.t("剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L.t("拷贝"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L.t("粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L.t("全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let findItem = NSMenuItem(title: L.t("查找…"), action: #selector(AppDelegate.showFind), keyEquivalent: "f")
        findItem.target = self
        editMenu.addItem(findItem)

        // 对话 menu — the export features live here, on their own, instead of
        // being buried inside 增强. This is the part of the app the browser
        // can't replace, so it gets a first-class entry in the menu bar.
        let convMenuItem = NSMenuItem(title: L.t("对话"), action: nil, keyEquivalent: "")
        mainMenu.addItem(convMenuItem)
        let convMenu = NSMenu(title: L.t("对话"))
        convMenuItem.submenu = convMenu

        // Shortcuts run top to bottom: ⇧⌘W ⇧⌘E ⇧⌘R ⇧⌘T ⇧⌘Y ⇧⌘U, then ⌘P to print.
        // Letters are consecutive on purpose — the whole column is one keyboard
        // row, so the export family is memorable rather than arbitrary.
        let exportMD = NSMenuItem(title: L.t("导出对话为 Markdown…"),
                                  action: #selector(exportConversationMarkdown),
                                  keyEquivalent: "w")
        exportMD.keyEquivalentModifierMask = [.command, .shift]
        exportMD.target = self
        convMenu.addItem(exportMD)

        let copyMD = NSMenuItem(title: L.t("复制对话为 Markdown"),
                                action: #selector(copyConversationMarkdown),
                                keyEquivalent: "e")
        copyMD.keyEquivalentModifierMask = [.command, .shift]
        copyMD.target = self
        convMenu.addItem(copyMD)

        let copySel = NSMenuItem(title: L.t("复制选中内容为 Markdown"),
                                 action: #selector(copySelectionMarkdown),
                                 keyEquivalent: "r")
        copySel.keyEquivalentModifierMask = [.command, .shift]
        copySel.target = self
        convMenu.addItem(copySel)

        convMenu.addItem(.separator())

        let copyText = NSMenuItem(title: L.t("复制全文（纯文本）"),
                                  action: #selector(copyPlainText),
                                  keyEquivalent: "t")
        copyText.keyEquivalentModifierMask = [.command, .shift]
        copyText.target = self
        convMenu.addItem(copyText)

        let exportTxt = NSMenuItem(title: L.t("导出为纯文本文件…（.txt）"),
                                   action: #selector(exportPlainText),
                                   keyEquivalent: "y")
        exportTxt.keyEquivalentModifierMask = [.command, .shift]
        exportTxt.target = self
        convMenu.addItem(exportTxt)

        convMenu.addItem(.separator())

        let stats = NSMenuItem(title: L.t("统计对话字数"),
                               action: #selector(showTextStats),
                               keyEquivalent: "u")
        stats.keyEquivalentModifierMask = [.command, .shift]
        stats.target = self
        convMenu.addItem(stats)

        let printItem = NSMenuItem(title: L.t("打印 / 存储为 PDF…"),
                                   action: #selector(printPage),
                                   keyEquivalent: "p")
        printItem.target = self
        convMenu.addItem(printItem)

        // View menu
        let viewMenuItem = NSMenuItem(title: L.t("显示"), action: nil, keyEquivalent: "")
        mainMenu.addItem(viewMenuItem)
        viewMenu = NSMenu(title: L.t("显示"))
        viewMenu.delegate = self
        viewMenuItem.submenu = viewMenu
        let reload = NSMenuItem(title: L.t("重新载入"), action: #selector(AppDelegate.reloadPage), keyEquivalent: "r")
        reload.target = self
        viewMenu.addItem(reload)
        // ⇧⌘H rather than ⇧⌘R: the latter now belongs to 对话 → 复制选中内容为
        // Markdown, and Safari already trains ⇧⌘H as "go home".
        let home = NSMenuItem(title: L.t("回到首页"), action: #selector(AppDelegate.goHome), keyEquivalent: "h")
        home.keyEquivalentModifierMask = [.command, .shift]
        home.target = self
        viewMenu.addItem(home)
        viewMenu.addItem(.separator())
        // Zoom is deliberately NOT bound to ⌘+ / ⌘- / ⌘0 any more: they are easy to
        // hit by accident while typing, and the zoom level is remembered, so one
        // stray key press left the window stuck at the wrong size. The menu items
        // stay so zooming is still possible, just never accidental.
        let zoomIn = NSMenuItem(title: L.t("放大"), action: #selector(AppDelegate.zoomIn), keyEquivalent: "")
        zoomIn.target = self
        viewMenu.addItem(zoomIn)
        let zoomOut = NSMenuItem(title: L.t("缩小"), action: #selector(AppDelegate.zoomOut), keyEquivalent: "")
        zoomOut.target = self
        viewMenu.addItem(zoomOut)
        let zoomReset = NSMenuItem(title: L.t("实际大小"), action: #selector(AppDelegate.zoomReset), keyEquivalent: "")
        zoomReset.target = self
        viewMenu.addItem(zoomReset)
        viewMenu.addItem(.separator())
        let fullscreen = NSMenuItem(title: L.t("进入全屏幕"),
                                    action: #selector(NSWindow.toggleFullScreen(_:)),
                                    keyEquivalent: "f")
        fullscreen.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fullscreen)

        // 增强 menu
        let enhanceMenuItem = NSMenuItem(title: L.t("增强"), action: nil, keyEquivalent: "")
        mainMenu.addItem(enhanceMenuItem)
        let enhanceMenu = NSMenu(title: L.t("增强"))
        enhanceMenuItem.submenu = enhanceMenu

        // -- 外观
        let appearanceItem = NSMenuItem(title: L.t("外观"), action: nil, keyEquivalent: "")
        enhanceMenu.addItem(appearanceItem)
        appearanceMenu = NSMenu(title: L.t("外观"))
        appearanceMenu.delegate = self
        appearanceItem.submenu = appearanceMenu
        for mode in AppearanceMode.allCases {
            let it = NSMenuItem(title: mode.title,
                                action: #selector(setAppearanceMode(_:)),
                                keyEquivalent: "")
            it.target = self
            it.tag = mode.rawValue
            appearanceMenu.addItem(it)
        }

        // -- 语言 (interface language of the app chrome only)
        let languageItem = NSMenuItem(title: L.t("语言"), action: nil, keyEquivalent: "")
        enhanceMenu.addItem(languageItem)
        languageMenu = NSMenu(title: L.t("语言"))
        languageMenu.delegate = self
        languageItem.submenu = languageMenu
        for language in AppLanguage.allCases {
            let it = NSMenuItem(title: language.title,
                                action: #selector(setLanguage(_:)),
                                keyEquivalent: "")
            it.target = self
            it.tag = language.rawValue
            languageMenu.addItem(it)
        }

        // -- User-Agent
        let uaItem = NSMenuItem(title: L.t("浏览器标识 (User-Agent)"), action: nil, keyEquivalent: "")
        enhanceMenu.addItem(uaItem)
        uaMenu = NSMenu(title: L.t("浏览器标识 (User-Agent)"))
        uaMenu.delegate = self
        uaItem.submenu = uaMenu
        for (i, p) in kUserAgentPresets.enumerated() {
            let it = NSMenuItem(title: L.t(p.name), action: #selector(setUserAgentPreset(_:)), keyEquivalent: "")
            it.target = self
            it.tag = i
            uaMenu.addItem(it)
        }
        uaMenu.addItem(.separator())
        let customUA = NSMenuItem(title: L.t("自定义…"), action: #selector(setCustomUserAgent), keyEquivalent: "")
        customUA.target = self
        uaMenu.addItem(customUA)
        let resetUA = NSMenuItem(title: L.t("重置为默认"), action: #selector(resetUserAgent), keyEquivalent: "")
        resetUA.target = self
        uaMenu.addItem(resetUA)

        // -- 页面样式
        let styleItem = NSMenuItem(title: L.t("页面样式"), action: nil, keyEquivalent: "")
        enhanceMenu.addItem(styleItem)
        styleMenu = NSMenu(title: L.t("页面样式"))
        styleMenu.delegate = self
        styleItem.submenu = styleMenu
        styleHideScrollbar = NSMenuItem(title: L.t("隐藏滚动条"), action: #selector(toggleHideScrollbar), keyEquivalent: "")
        styleHideScrollbar.target = self
        styleMenu.addItem(styleHideScrollbar)
        styleNoAnimation = NSMenuItem(title: L.t("禁用动画与过渡"), action: #selector(toggleNoAnimation), keyEquivalent: "")
        styleNoAnimation.target = self
        styleMenu.addItem(styleNoAnimation)
        styleMenu.addItem(.separator())
        styleCustomCSS = NSMenuItem(title: L.t("自定义 CSS…"), action: #selector(editCustomCSS), keyEquivalent: "")
        styleCustomCSS.target = self
        styleMenu.addItem(styleCustomCSS)
        styleClearCustomCSS = NSMenuItem(title: L.t("清除自定义 CSS"), action: #selector(clearCustomCSS), keyEquivalent: "")
        styleClearCustomCSS.target = self
        styleMenu.addItem(styleClearCustomCSS)
        styleMenu.addItem(.separator())
        let applyCSS = NSMenuItem(title: L.t("重新应用样式"), action: #selector(reapplyCSS), keyEquivalent: "")
        applyCSS.target = self
        styleMenu.addItem(applyCSS)

        // -- reset
        enhanceMenu.addItem(.separator())
        let resetAll = NSMenuItem(title: L.t("重置所有增强设置"),
                                  action: #selector(resetAllEnhancements),
                                  keyEquivalent: "")
        resetAll.target = self
        enhanceMenu.addItem(resetAll)

        // History menu
        let historyMenuItem = NSMenuItem(title: L.t("历史记录"), action: nil, keyEquivalent: "")
        mainMenu.addItem(historyMenuItem)
        let historyMenu = NSMenu(title: L.t("历史记录"))
        historyMenuItem.submenu = historyMenu
        let back = NSMenuItem(title: L.t("后退"), action: #selector(AppDelegate.goBack), keyEquivalent: "[")
        back.target = self
        historyMenu.addItem(back)
        let forward = NSMenuItem(title: L.t("前进"), action: #selector(AppDelegate.goForward), keyEquivalent: "]")
        forward.target = self
        historyMenu.addItem(forward)

        // Window menu
        let windowMenuItem = NSMenuItem(title: L.t("窗口"), action: nil, keyEquivalent: "")
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: L.t("窗口"))
        windowMenuItem.submenu = windowMenu
        // ⌘N opens another window — never another tab. Each window is a complete,
        // independent conversation, which is why the app has no tab strip at all.
        let newWin = NSMenuItem(title: L.t("新建窗口"),
                                action: #selector(newWindow),
                                keyEquivalent: "n")
        newWin.target = self
        windowMenu.addItem(newWin)
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: L.t("最小化"),
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        // Closing the window keeps the app alive, so make it explicit and give it
        // the conventional ⌘W binding.
        windowMenu.addItem(withTitle: L.t("关闭窗口"),
                           action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: L.t("缩放"),
                           action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        let showMain = NSMenuItem(title: L.t("显示主窗口"),
                                  action: #selector(showMainWindow),
                                  keyEquivalent: "")
        showMain.target = self
        windowMenu.addItem(showMain)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu

        Diag.log("menu shortcuts → \(AppDelegate.describeShortcuts(mainMenu))")
    }

    /// Flattens every keyboard shortcut in the menu tree into one log line, so
    /// bindings can be verified from the log instead of by eye.
    private static func describeShortcuts(_ menu: NSMenu) -> String {
        var out: [String] = []
        for item in menu.items {
            if let sub = item.submenu {
                let inner = describeShortcuts(sub)
                if !inner.isEmpty { out.append(inner) }
            } else if !item.keyEquivalent.isEmpty {
                var mods = ""
                let m = item.keyEquivalentModifierMask
                if m.contains(.control)  { mods += "^" }
                if m.contains(.option)   { mods += "⌥" }
                if m.contains(.shift)    { mods += "⇧" }
                if m.contains(.command)  { mods += "⌘" }
                // AppKit adds dictation / emoji items bound to the Fn key, which
                // would otherwise render as a bogus unmodified shortcut here.
                if m.contains(.function) { mods += "fn" }
                out.append("\(item.title)=\(mods)\(item.keyEquivalent)")
            }
        }
        return out.joined(separator: " ")
    }

    /// Dumps the *entire* live menu tree, including items that carry no shortcut.
    ///
    /// `describeShortcuts` only reports items with a key equivalent, so anything
    /// AppKit injects at runtime without a binding — the automatic window-tabbing
    /// items are the prime example — is invisible there. This mode exists to see
    /// those, and to prove they are gone afterwards.
    ///   ./ScheutieOS --dump-menu
    private func runMenuDump() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            guard let mainMenu = NSApp.mainMenu else {
                Diag.log("dump-menu FAIL: no main menu")
                exit(1)
            }
            AppDelegate.dumpMenu(mainMenu, depth: 0)
            Diag.log("dump-menu DONE sessions=\(self.sessions.count) "
                     + "allowsAutomaticWindowTabbing=\(NSWindow.allowsAutomaticWindowTabbing) "
                     + "tabbingMode=\(self.sessions.first?.window.tabbingMode.rawValue ?? -1)")
            exit(0)
        }
    }

    private static func dumpMenu(_ menu: NSMenu, depth: Int) {
        let pad = String(repeating: "  ", count: depth)
        Diag.log("dump-menu \(pad)<\(menu.title)>")
        for item in menu.items {
            if item.isSeparatorItem {
                Diag.log("dump-menu \(pad)  ---")
                continue
            }
            let key = item.keyEquivalent.isEmpty
                ? ""
                : " key=\(item.keyEquivalent) mods=\(item.keyEquivalentModifierMask.rawValue)"
            if let sub = item.submenu {
                Diag.log("dump-menu \(pad)  [\(item.title)]\(key)")
                dumpMenu(sub, depth: depth + 1)
            } else {
                Diag.log("dump-menu \(pad)  - \(item.title)\(key)")
            }
        }
    }

    // MARK: - Language self test
    //
    // Eight languages is too many to eyeball, and a missed entry is invisible in a
    // screenshot-free environment (it degrades to the Chinese string). So the
    // check is mechanical, per language:
    //   1. every Chinese menu title must have a table entry for that language
    //   2. the rendered title must differ from the Chinese source
    //   3. the rendered menu must still have exactly as many titles as Chinese
    //   4. the language's own script must actually appear in the output
    // Runs headless:
    //   ./ScheutieOS --self-test-lang

    /// Collects every non-empty title in a menu tree (top-level holder items
    /// carry no title, their submenu does).
    private static func collectTitles(_ menu: NSMenu, into out: inout [String]) {
        if !menu.title.isEmpty { out.append(menu.title) }
        for item in menu.items {
            if !item.title.isEmpty { out.append(item.title) }
            if let sub = item.submenu { collectTitles(sub, into: &out) }
        }
    }

    static func runLanguageSelfTest() -> Bool {
        let probe = AppDelegate()
        var failures: [String] = []

        L.set(.chinese)
        probe.buildMenuBar()
        var zhTitles: [String] = []
        if let m = NSApp.mainMenu { collectTitles(m, into: &zhTitles) }
        Diag.log("selftest-lang zh titles (\(zhTitles.count)): \(zhTitles.joined(separator: " | "))")

        guard !zhTitles.isEmpty else {
            Diag.log("selftest-lang FAIL: collected no menu titles")
            return false
        }

        // A duplicated Chinese key would silently swallow a whole table row.
        if L.keyCount != L.allKeys.count {
            failures.append("duplicate keys: \(L.allKeys.count) rows, \(L.keyCount) distinct")
        }

        // Language names are never translated, so they are exempt everywhere.
        let languageNames = Set(AppLanguage.allCases.map { $0.title })

        // Script that must show up if the column was really translated rather than
        // filled with the English text.
        let expectedScript: [AppLanguage: (String, (String) -> Bool)] = [
            .russian:  ("Cyrillic", L.hasCyrillic),
            .arabic:   ("Arabic",   L.hasArabicScript),
            .japanese: ("kana",     L.hasKana),
            .korean:   ("Hangul",   L.hasHangul),
        ]

        for language in AppLanguage.allCases where language != .chinese {
            L.set(language)
            probe.buildMenuBar()
            var titles: [String] = []
            if let m = NSApp.mainMenu { collectTitles(m, into: &titles) }

            // Product names stay verbatim by design; everything else must be
            // translated in every language.
            let checkable = zhTitles.filter {
                !languageNames.contains($0) && !L.isVerbatim($0)
            }

            // 1) table completeness
            let missing = checkable.filter { !L.hasTranslation($0, in: language) }
            if !missing.isEmpty {
                failures.append("\(language.code) missing \(missing.count): "
                                + missing.prefix(3).joined(separator: " / "))
            }

            // 2) nothing may still render the Chinese source
            let unchanged = checkable.filter { L.t($0) == $0 }
            if !unchanged.isEmpty {
                failures.append("\(language.code) untranslated \(unchanged.count): "
                                + unchanged.prefix(3).joined(separator: " / "))
            }

            // 3) no menu item may be lost in translation
            if titles.count != zhTitles.count {
                failures.append("\(language.code) title count \(titles.count) != zh \(zhTitles.count)")
            }

            // 4) the target script is actually present
            if let (label, matches) = expectedScript[language] {
                let hits = titles.filter(matches).count
                let ratio = Double(hits) / Double(max(titles.count, 1))
                if ratio < 0.25 {
                    failures.append("\(language.code) only \(hits)/\(titles.count) titles contain \(label)")
                }
            }

            Diag.log("selftest-lang \(language.code) (\(titles.count) titles): "
                     + titles.joined(separator: " | "))
        }

        if failures.isEmpty {
            let n = AppLanguage.allCases.count - 1
            Diag.log("selftest-lang PASS: \(n) languages × \(zhTitles.count) titles, none untranslated")
            return true
        }
        Diag.log("selftest-lang FAIL: \(failures.joined(separator: " ;; "))")
        return false
    }

    // MARK: - Menu actions

    @objc private func reloadPage() { webView.reload() }
    @objc private func goHome() { webView.load(URLRequest(url: kHomeURL)) }
    @objc private func goBack() { if webView.canGoBack { webView.goBack() } }
    @objc private func goForward() { if webView.canGoForward { webView.goForward() } }
    @objc private func zoomIn() { setZoom(webView.pageZoom + 0.1) }
    @objc private func zoomOut() { setZoom(webView.pageZoom - 0.1) }
    @objc private func zoomReset() { setZoom(1.0) }

    private func setZoom(_ z: CGFloat) {
        let clamped = min(max(z, 0.4), 3.0)
        webView.pageZoom = clamped
        Prefs.shared.pageZoom = Double(clamped)
    }

    // MARK: - 增强 · 外观

    @objc private func setAppearanceMode(_ sender: NSMenuItem) {
        let mode = AppearanceMode(rawValue: sender.tag) ?? .system
        Prefs.shared.appearanceMode = mode
        // App-wide setting: every open window follows, not just the front one.
        for s in sessions {
            s.webView.appearance = mode.appearance
            // WKWebView needs a nudge for prefers-color-scheme to be re-evaluated.
            s.webView.evaluateJavaScript("void 0;", completionHandler: nil)
        }
        flash(L.appearanceChanged(mode.title))
    }

    // MARK: - 增强 · 语言
    //
    // Switches the app's own *fixed* chrome — the menu bar, dialogs and the About
    // window — into any of the eight languages. Nothing else is affected: the web
    // page, the conversation, the user's input, the model's replies and the
    // exported Markdown are all left exactly as they are. There is no code path
    // from this setting to the page.
    //
    // The translations are baked into L10n.swift rather than produced at runtime.
    // The system Translation framework can't do it here: on macOS 27 every
    // zh→X pair reports `.supported` but not installed, `canRequestDownloads` is
    // false, and `prepareTranslation()` throws `.notInstalled` — both from a CLI
    // and from a real NSApplication. Measured, not assumed.

    @objc private func setLanguage(_ sender: NSMenuItem) {
        let language = AppLanguage(rawValue: sender.tag) ?? .chinese
        guard language != Prefs.shared.language else { return }
        Prefs.shared.language = language
        L.set(language)
        Diag.log("language → \(language.title)")
        // Menu titles are baked in at construction time, so the whole menu has to
        // be rebuilt. Doing that from inside a menu action means mutating the menu
        // that is currently tracking — hand it to the next runloop pass instead.
        DispatchQueue.main.async { [weak self] in
            self?.buildMenuBar()
        }
        flash(L.languageChanged(language))
    }

    // MARK: - 增强 · User-Agent

    @objc private func setUserAgentPreset(_ sender: NSMenuItem) {
        guard sender.tag >= 0 && sender.tag < kUserAgentPresets.count else { return }
        Prefs.shared.uaIndex = sender.tag
        applyUserAgent()
    }

    @objc private func setCustomUserAgent() {
        let current = Prefs.shared.uaIndex < 0 ? Prefs.shared.customUA : Prefs.shared.effectiveUA
        guard let value = Prompts.text(title: L.t("自定义 User-Agent"),
                                       message: L.customUAHint(),
                                       defaultValue: current),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        Prefs.shared.customUA = value.trimmingCharacters(in: .whitespacesAndNewlines)
        Prefs.shared.uaIndex = -1
        applyUserAgent()
    }

    @objc private func resetUserAgent() {
        Prefs.shared.uaIndex = 0
        Prefs.shared.customUA = ""
        applyUserAgent()
    }

    private func applyUserAgent() {
        // App-wide identity: reload every window so each document is fetched with
        // the new User-Agent.
        for s in sessions {
            s.webView.customUserAgent = Prefs.shared.effectiveUA
            s.webView.reload()
        }
    }

    // MARK: - 增强 · 页面样式

    @objc private func toggleHideScrollbar() {
        Prefs.shared.hideScrollbar.toggle()
        applyStyles()
    }

    @objc private func toggleNoAnimation() {
        Prefs.shared.noAnimation.toggle()
        applyStyles()
    }

    @objc private func editCustomCSS() {
        guard let css = Prompts.multiline(
            title: "自定义 CSS",
            message: "直接写下要注入的 CSS 规则，会应用到站点的所有页面。",
            defaultValue: Prefs.shared.customCSS
        ) else { return }
        Prefs.shared.customCSS = css
        applyStyles()
    }

    @objc private func clearCustomCSS() {
        guard !Prefs.shared.customCSS.isEmpty else { return }
        Prefs.shared.customCSS = ""
        applyStyles()
        flash("自定义 CSS 已清除")
    }

    @objc private func reapplyCSS() {
        applyStyles()
        flash("样式已重新应用")
    }

    /// Push the assembled CSS into the page (survives CSP because it uses a
    /// constructed stylesheet first, inline <style> as fallback).
    ///
    /// Enhancement settings are app-wide, so with several windows open the CSS
    /// goes into all of them. Pass `target` to address one page on its own (used
    /// after a navigation finishes).
    func applyStyles(in target: WKWebView? = nil) {
        let css = Prefs.shared.combinedCSS
        let literal = jsString(css)
        let js = """
        (function(){
          if (window.__scheutiePendingCSS !== undefined) { window.__scheutiePendingCSS = \(literal); }
          if (typeof window.__scheutieApplyCSS === 'function') { return window.__scheutieApplyCSS(\(literal)); }
          return 'not-ready';
        })();
        """
        let targets = target.map { [$0] } ?? sessions.map { $0.webView }
        for wv in targets {
            wv.evaluateJavaScript(js) { result, error in
                if let error = error {
                    Diag.log("applyStyles FAILED: \(error.localizedDescription)")
                } else if let r = result as? String {
                    Diag.log("applyStyles -> \(r) (css \(css.utf8.count) bytes)")
                }
            }
        }
    }

    /// Safe JS string literal (handles quotes, newlines, unicode line separators).
    private func jsString(_ s: String) -> String {
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"":        out += "\\\""
            case "\\":        out += "\\\\"
            case "\n":        out += "\\n"
            case "\r":        out += "\\r"
            case "\t":        out += "\\t"
            case "\u{2028}":  out += "\\u2028"
            case "\u{2029}":  out += "\\u2029"
            default:
                if ch.value < 0x20 {
                    out += String(format: "\\u%04x", ch.value)
                } else {
                    out.unicodeScalars.append(ch)
                }
            }
        }
        return out + "\""
    }

    // MARK: - 对话 · 导出
    //
    // These now live under their own top-level 对话 menu: they are the part of
    // this app a plain browser can't replace, so they get to be first-class.

    @objc private func copyConversationMarkdown() {
        runExport(script: "__scheutieExportMarkdown") { [weak self] md in
            guard let self = self else { return }
            self.writeToPasteboard(md, asRichMarkdown: true)
            self.flash(L.copiedMarkdown(md.count))
        }
    }

    /// Markdown for just the current selection — usually one answer rather than
    /// the whole conversation.
    @objc private func copySelectionMarkdown() {
        runExport(script: "__scheutieExportSelection") { [weak self] md in
            guard let self = self else { return }
            let trimmed = md.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                self.alert(L.t("没选中内容"), L.t("请先用鼠标选中想导出的部分，再执行这个命令。"))
                return
            }
            self.writeToPasteboard(trimmed, asRichMarkdown: true)
            self.flash(L.copiedSelection(trimmed.count))
        }
    }

    @objc private func exportConversationMarkdown() {
        runExport(script: "__scheutieExportMarkdown") { [weak self] md in
            guard let self = self else { return }
            self.saveToFile(text: md, ext: "md", panelTitle: L.t("导出对话为 Markdown"))
        }
    }

    @objc private func exportPlainText() {
        webView.evaluateJavaScript(
            "window.__scheutieExportPlainText ? __scheutieExportPlainText() : (document.body ? document.body.innerText : '')"
        ) { [weak self] result, error in
            guard let self = self else { return }
            if let error = error {
                self.alert(L.t("导出失败"), error.localizedDescription)
                return
            }
            guard let text = result as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.alert(L.t("导出失败"), L.t("没能从当前页面提取到内容。\n可能页面还没加载完，或站点结构有变化。"))
                return
            }
            self.saveToFile(text: text, ext: "txt", panelTitle: L.t("导出为纯文本"))
        }
    }

    @objc private func copyPlainText() {
        webView.evaluateJavaScript(
            "window.__scheutieExportPlainText ? __scheutieExportPlainText() : (document.body ? document.body.innerText : '')"
        ) { [weak self] result, _ in
            guard let self = self, let text = result as? String, !text.isEmpty else { return }
            self.writeToPasteboard(text, asRichMarkdown: false)
            self.flash(L.copiedAllText(text.count))
        }
    }

    /// Character / word count of the current conversation, shown as a HUD flash.
    @objc private func showTextStats() {
        webView.evaluateJavaScript("window.__scheutieCountText ? __scheutieCountText() : '{}'") {
            [weak self] result, _ in
            guard let self = self else { return }
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                self.flash(L.t("统计失败"))
                return
            }
            self.flash(L.textStats(chars: obj["chars"] as? Int ?? 0,
                                   cjk: obj["cjk"] as? Int ?? 0,
                                   words: obj["words"] as? Int ?? 0))
        }
    }

    /// Shared save-panel flow for the two "export to file" commands.
    private func saveToFile(text: String, ext: String, panelTitle: String) {
        let panel = NSSavePanel()
        panel.title = panelTitle
        panel.nameFieldStringValue = suggestedFilename(ext: ext)
        panel.canCreateDirectories = true
        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] resp in
            guard let self = self, resp == .OK, let url = panel.url else { return }
            let target = url.pathExtension.lowercased() == ext
                ? url
                : url.appendingPathExtension(ext)
            do {
                try text.write(to: target, atomically: true, encoding: .utf8)
                Prefs.shared.exportCount += 1
                self.flash(L.exportedTo(target.lastPathComponent))
                NSWorkspace.shared.activateFileViewerSelecting([target])
            } catch {
                self.alert(L.t("导出失败"), error.localizedDescription)
            }
        }
        // Sheets need a window; if the last one closed in the meantime, run the
        // panel standalone rather than silently doing nothing.
        if let w = window, w.isVisible {
            panel.beginSheetModal(for: w, completionHandler: handle)
        } else {
            handle(panel.runModal())
        }
    }

    @objc private func printPage() {
        guard let w = window, w.isVisible, let wv = webView else { return }
        let info = NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        let op = wv.printOperation(with: info)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.view?.frame = wv.bounds
        op.runModal(for: w, delegate: nil, didRun: nil, contextInfo: nil)
    }

    private func runExport(script: String, _ done: @escaping (String) -> Void) {
        webView.evaluateJavaScript("window.\(script) ? \(script)() : null") {
            [weak self] result, error in
            guard let self = self else { return }
            if let error = error {
                self.alert(L.t("导出失败"), error.localizedDescription)
                return
            }
            guard let md = result as? String, !md.isEmpty else {
                self.alert(L.t("导出失败"), L.t("没能从当前页面提取到对话内容。\n可能页面还没加载完，或站点结构有变化。"))
                return
            }
            done(md)
        }
    }

    private func suggestedFilename(ext: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        let stripped = (webView.title ?? "").replacingOccurrences(of: "— \(kAppName)", with: "")
        let cleaned = stripped
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = L.t("对话")
        let base = cleaned.isEmpty ? fallback : cleaned
        return "\(base)-\(f.string(from: Date())).\(ext)"
    }

    private func writeToPasteboard(_ s: String, asRichMarkdown: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if asRichMarkdown {
            // Provide both plain text and a Markdown-typed flavor.
            let item = NSPasteboardItem()
            item.setString(s, forType: .string)
            if let mdType = NSPasteboard.PasteboardType(rawValue: "net.daringfireball.markdown") as NSPasteboard.PasteboardType? {
                item.setString(s, forType: mdType)
            }
            pb.writeObjects([item])
        } else {
            pb.setString(s, forType: .string)
        }
    }

    // MARK: - 增强 · 重置

    @objc private func resetAllEnhancements() {
        let p = Prefs.shared
        p.appearanceMode = .system
        p.uaIndex = 0
        p.customUA = ""
        p.hideScrollbar = false
        p.noAnimation = false
        p.customCSS = ""
        for s in sessions {
            s.webView.appearance = nil
            s.webView.customUserAgent = p.effectiveUA
            s.webView.reload()
        }
        flash(L.t("已重置所有增强设置"))
    }

    // MARK: - Feedback helpers

    private func flash(_ message: String) {
        Diag.log(message)
        guard let window = window else { return }
        let label = NSTextField(labelWithString: message)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()
        let pad: CGFloat = 14
        let hud = NSView(frame: NSRect(x: 0, y: 0,
                                       width: label.frame.width + pad * 2,
                                       height: label.frame.height + pad))
        hud.wantsLayer = true
        hud.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        hud.layer?.cornerRadius = 10
        label.frame.origin = NSPoint(x: pad, y: pad / 2)
        hud.addSubview(label)

        let container = window.contentView!
        hud.frame.origin = NSPoint(x: (container.bounds.width - hud.frame.width) / 2,
                                   y: container.bounds.height * 0.12)
        hud.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
        container.addSubview(hud)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                hud.animator().alphaValue = 0
            } completionHandler: {
                hud.removeFromSuperview()
            }
        }
    }

    /// Presents an alert against the frontmost window, falling back to a modal
    /// when there is no window left to hang a sheet on.
    private func presentAlert(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let w = window, w.isVisible {
            alert.beginSheetModal(for: w) { resp in completion(resp) }
        } else {
            completion(alert.runModal())
        }
    }

    private func alert(_ title: String, _ message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: L.t("好"))
        presentAlert(a) { _ in }
    }

    // MARK: - NSMenuItemValidation
    //
    // With ⌘N in play there can be zero windows at any moment. Every command that
    // dereferences `webView` would crash then, so they are disabled instead.

    private static let windowCommands: Set<Selector> = [
        #selector(reloadPage), #selector(goHome), #selector(goBack), #selector(goForward),
        #selector(zoomIn), #selector(zoomOut), #selector(zoomReset), #selector(showFind),
        #selector(exportConversationMarkdown), #selector(copyConversationMarkdown),
        #selector(copySelectionMarkdown), #selector(exportPlainText), #selector(copyPlainText),
        #selector(showTextStats), #selector(printPage),
        #selector(setAppearanceMode(_:)), #selector(setUserAgentPreset(_:)),
        #selector(setCustomUserAgent), #selector(resetUserAgent),
        #selector(toggleHideScrollbar), #selector(toggleNoAnimation),
        #selector(editCustomCSS), #selector(clearCustomCSS), #selector(reapplyCSS),
        #selector(resetAllEnhancements),
    ]

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let action = item.action, AppDelegate.windowCommands.contains(action) else {
            return true
        }
        guard let s = keySession, s.window.isVisible else { return false }
        if action == #selector(goBack)    { return s.webView.canGoBack }
        if action == #selector(goForward) { return s.webView.canGoForward }
        // Validation runs after menuNeedsUpdate and would otherwise re-enable this
        // item, undoing the grey-out. Same condition in both places, so whichever
        // runs last agrees.
        if action == #selector(clearCustomCSS) {
            return !Prefs.shared.customCSS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    // MARK: - NSMenuDelegate (sync checkmarks when a submenu opens)

    func menuNeedsUpdate(_ menu: NSMenu) {
        let p = Prefs.shared
        if menu === appearanceMenu {
            for item in menu.items { item.state = (item.tag == p.appearanceMode.rawValue) ? .on : .off }
        } else if menu === languageMenu {
            for item in menu.items { item.state = (item.tag == p.language.rawValue) ? .on : .off }
        } else if menu === uaMenu {
            let custom = p.uaIndex < 0
            for item in menu.items {
                if item.isSeparatorItem { continue }
                if item.action == #selector(setUserAgentPreset(_:)) {
                    item.state = (item.tag == p.uaIndex) ? .on : .off
                } else if item.action == #selector(setCustomUserAgent) {
                    item.state = custom ? .on : .off
                    item.title = custom ? L.t("自定义…（当前已启用）") : L.t("自定义…")
                }
            }
        } else if menu === styleMenu {
            // Item references, not title lookups: titles are localized.
            styleHideScrollbar.state = p.hideScrollbar ? .on : .off
            styleNoAnimation.state = p.noAnimation ? .on : .off
            let hasCustom = !p.customCSS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            styleClearCustomCSS.isEnabled = hasCustom
            styleCustomCSS.title = hasCustom ? L.t("自定义 CSS…（已设置）") : L.t("自定义 CSS…")
        } else if menu === viewMenu {
            // Second line of defence against macOS's automatic window tabbing.
            // See `stripTabCommands`.
            let removed = stripTabCommands(from: menu)
            if removed > 0 && !tabStripReported {
                tabStripReported = true
                Diag.log("stripped \(removed) AppKit tab command(s) from the 显示 menu")
            }
        }
    }

    // MARK: - Dropping the tab commands macOS injects

    /// AppKit's automatic window tabbing adds a whole family of commands to the
    /// View menu («Show Tab Bar», «Show All Tabs», «Move Tab to New Window», …).
    /// This app is one window = one page by design, so those entries are pure
    /// noise — they advertise a feature that cannot exist here.
    ///
    /// `NSWindow.allowsAutomaticWindowTabbing = false` is the real switch and is
    /// set before any window exists. This is the belt to that pair of braces:
    /// matched by selector *name*, because the items are injected at menu-open
    /// time and would otherwise be invisible to inspection.
    private static let tabCommandNames: Set<String> = [
        "toggleTabBar:", "toggleTabOverview:", "enterTabOverview:", "exitTabOverview:",
        "showAllTabs:", "moveTabToNewWindow:", "mergeAllWindows:",
        "selectNextTab:", "selectPreviousTab:",
        "closeTab:", "closeOtherTabs:", "closeTabsToTheLeft:", "closeTabsToTheRight:",
        "pinTab:", "unpinTab:", "arrangeTabsByTitle:",
    ]

    private var tabStripReported = false

    /// Removes any tab-semantics command from `menu`; returns how many went.
    @discardableResult
    private func stripTabCommands(from menu: NSMenu) -> Int {
        var removed = 0
        for item in menu.items.reversed() {
            guard let action = item.action else { continue }
            if AppDelegate.tabCommandNames.contains(NSStringFromSelector(action)) {
                menu.removeItem(item)
                removed += 1
            }
        }
        // Dropping a group can leave its separator dangling at the end.
        while let last = menu.items.last, last.isSeparatorItem {
            menu.removeItem(last)
        }
        return removed
    }

    // MARK: - Zoom


    @objc private func showFind() {
        // Uses the system find panel against the web view's responder chain.
        let sender = NSMenuItem()
        sender.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        if let wv = webView {
            NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: wv, from: sender)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadCount += 1
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Re-apply injected CSS after every navigation, then self-check that the
        // enhancement runtime actually landed. Addressed at the page that just
        // finished, not at whichever window happens to be frontmost.
        applyStyles(in: webView)
        diagnostics(in: webView)
    }

    /// Verifies the injected runtime is present. Result goes to the unified log:
    ///   log show --predicate 'process == "ScheutieOS"' --last 3m --style compact
    func diagnostics(in target: WKWebView) {
        let js = """
        (function(){
          var cssOk = (typeof window.__scheutieApplyCSS === 'function');
          var mdOk  = (typeof window.__scheutieExportMarkdown === 'function');
          var nodes = document.body ? document.body.querySelectorAll('*').length : 0;
          var text  = document.body ? (document.body.innerText || '').length : 0;
          var sample = mdOk ? window.__scheutieExportMarkdown().length : 0;
          return 'css=' + cssOk + ' md=' + mdOk + ' nodes=' + nodes
               + ' textChars=' + text + ' mdChars=' + sample;
        })();
        """
        target.evaluateJavaScript(js) { result, error in
            if let error = error {
                Diag.log("diagnostics FAILED: \(error.localizedDescription)")
            } else if let r = result as? String {
                Diag.log("diagnostics OK load#\(self.loadCount) \(r)")
            }
        }
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Keep everything inside the app window; external schemes go to the system.
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() {
            let internalSchemes = ["http", "https", "about", "data", "blob", "file"]
            if !internalSchemes.contains(scheme) {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            // External links opened deliberately in a new window -> system browser
            if navigationAction.targetFrame == nil,
               navigationAction.navigationType == .linkActivated,
               let host = url.host,
               !host.hasSuffix("deepseek.com") {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView,
                 navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: - WKDownloadDelegate

    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        var dest = downloads.appendingPathComponent(suggestedFilename)
        var counter = 1
        let base = dest.deletingPathExtension().lastPathComponent
        let ext = dest.pathExtension
        while FileManager.default.fileExists(atPath: dest.path) {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            dest = downloads.appendingPathComponent(name)
            counter += 1
        }
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        NSSound(named: "Glass")?.play()
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil,
           let url = navigationAction.request.url {
            let host = url.host ?? ""
            if host.hasSuffix("deepseek.com") {
                webView.load(navigationAction.request)
            } else {
                NSWorkspace.shared.open(url)
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.begin { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = L.t("提示")
        alert.informativeText = message
        alert.addButton(withTitle: L.t("好"))
        presentAlert(alert) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = L.t("确认")
        alert.informativeText = message
        alert.addButton(withTitle: L.t("确定"))
        alert.addButton(withTitle: L.t("取消"))
        presentAlert(alert) { resp in
            completionHandler(resp == .alertFirstButtonReturn)
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = L.t("输入")
        alert.informativeText = prompt
        alert.addButton(withTitle: L.t("确定"))
        alert.addButton(withTitle: L.t("取消"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        presentAlert(alert) { resp in
            completionHandler(resp == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }
}

// MARK: - Entry point

// Offscreen design check:
//   ./ScheutieOS --render-about /tmp/about.png
if let i = CommandLine.arguments.firstIndex(of: "--render-about"),
   i + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    Diag.log("argv → [\(CommandLine.arguments.dropFirst().joined(separator: " "))]")
    L.set(Prefs.shared.language)
    AboutBuilder.renderPreview(to: CommandLine.arguments[i + 1])
    exit(0)
}

// Menu localization check (no window, no screen recording needed):
//   ./ScheutieOS --self-test-lang
if CommandLine.arguments.contains("--self-test-lang") {
    _ = NSApplication.shared
    Diag.log("argv → [\(CommandLine.arguments.dropFirst().joined(separator: " "))]")
    let ok = AppDelegate.runLanguageSelfTest()
    exit(ok ? 0 : 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
