// About.swift — a hand-built About panel for ScheutieOS.
//
// The stock NSApplication About panel is a single tiny window with one line of
// fine print, which looks cheap for a hand-made app. This draws a proper one:
// large icon, name, version pill, description, developer credit, footer.
//
// `renderPreview(to:)` renders the very same view offscreen to a PNG, so the
// layout can be checked without a screen-recording permission:
//   ./ScheutieOS --render-about /tmp/about.png

import Cocoa

private let kVersion   = "8.4.1"
private let kBuild     = "841"
private let kDeveloper = "Lynne Scheutie & Wanchen Qian"
private let kTagline   = "A quick launcher for DeepSeek"
private let kSite      = "chat.deepseek.com"

// MARK: - Small capsule label used for the version badge

final class PillLabel: NSView {
    private let label: NSTextField
    private let hPad: CGFloat = 11
    private let vPad: CGFloat = 4

    init(text: String, color: NSColor) {
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = color
        wantsLayer = true
        layer?.cornerRadius = 999
        layer?.backgroundColor = color.withAlphaComponent(0.15).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = color.withAlphaComponent(0.22).cgColor
        addSubview(label)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override var intrinsicContentSize: NSSize {
        let s = label.intrinsicContentSize
        return NSSize(width: ceil(s.width) + hPad * 2, height: ceil(s.height) + vPad * 2)
    }

    override func layout() {
        super.layout()
        let s = label.intrinsicContentSize
        label.frame = NSRect(x: hPad,
                             y: (bounds.height - s.height) / 2,
                             width: ceil(s.width),
                             height: ceil(s.height))
    }
}

// MARK: - Background
//
// A hand-drawn gradient instead of NSVisualEffectView: vibrancy cannot be
// reproduced offscreen, so it cannot be verified without screen-recording
// permission. A gradient renders identically in the window and in the
// offscreen design check, and still follows light/dark appearance.

final class AboutBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let top = dark ? NSColor(calibratedWhite: 0.205, alpha: 1)
                       : NSColor(calibratedWhite: 0.995, alpha: 1)
        let bottom = dark ? NSColor(calibratedWhite: 0.145, alpha: 1)
                          : NSColor(calibratedWhite: 0.945, alpha: 1)
        NSGradient(starting: top, ending: bottom)?
            .draw(in: bounds, angle: -90)
    }
}

// MARK: - About content

enum AboutBuilder {

    static let contentSize = NSSize(width: 420, height: 392)

    /// Resolve the icon the same way the system does, with fallbacks for the
    /// offscreen render path where NSApp may not be fully up yet.
    static var appIcon: NSImage {
        if let img = NSApp?.applicationIconImage, img.isValid, img.size.width > 0 {
            return img
        }
        if let name = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String {
            let base = name.hasSuffix(".icns") ? String(name.dropLast(5)) : name
            if let p = Bundle.main.path(forResource: base, ofType: "icns"),
               let img = NSImage(contentsOfFile: p) {
                return img
            }
            if let img = NSImage(named: base) { return img }
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }

    static func makeContentView() -> NSView {
        let bg = AboutBackgroundView(frame: NSRect(origin: .zero, size: contentSize))
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 14
        bg.layer?.masksToBounds = true

        let icon = NSImageView()
        icon.image = appIcon
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.wantsLayer = true
        icon.layer?.shadowColor = NSColor.black.cgColor
        icon.layer?.shadowOpacity = 0.28
        icon.layer?.shadowRadius = 10
        icon.layer?.shadowOffset = NSSize(width: 0, height: -3)

        let name = makeLabel("ScheutieOS", size: 25, weight: .semibold, color: .labelColor)
        name.attributedStringValue = NSAttributedString(
            string: "ScheutieOS",
            attributes: [
                .font: NSFont.systemFont(ofSize: 25, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .kern: -0.4
            ]
        )

        let pill = PillLabel(text: L.aboutPill(version: kVersion, build: kBuild), color: .controlAccentColor)

        let tagline = makeLabel(kTagline, size: 12.5, weight: .regular, color: .secondaryLabelColor)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        let devCaption = makeLabel(L.t("开 发 者"), size: 10, weight: .medium, color: .tertiaryLabelColor)
        devCaption.attributedStringValue = NSAttributedString(
            string: L.t("开 发 者"),
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .kern: 2.0
            ]
        )
        let devName = makeLabel(kDeveloper, size: 13, weight: .medium, color: .labelColor)

        let footer = makeLabel(L.aboutFooter(site: kSite), size: 10.5, weight: .regular,
                               color: .tertiaryLabelColor)
        let copyright = makeLabel("© 2026 \(kDeveloper)", size: 10.5, weight: .regular,
                                  color: .tertiaryLabelColor)

        let stack = NSStackView(views: [icon, name, pill, tagline, divider,
                                        devCaption, devName, footer, copyright])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(16, after: icon)
        stack.setCustomSpacing(9, after: name)
        stack.setCustomSpacing(14, after: pill)
        stack.setCustomSpacing(18, after: tagline)
        stack.setCustomSpacing(14, after: divider)
        stack.setCustomSpacing(3, after: devCaption)
        stack.setCustomSpacing(16, after: devName)
        stack.setCustomSpacing(2, after: footer)

        bg.addSubview(stack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 128),
            icon.heightAnchor.constraint(equalToConstant: 128),
            divider.widthAnchor.constraint(equalToConstant: 250),
            stack.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: bg.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: bg.trailingAnchor, constant: -24)
        ])

        return bg
    }

    private static func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight,
                                 color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.alignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        l.lineBreakMode = .byTruncatingTail
        return l
    }

    // MARK: Offscreen render (for verifying the design without screen capture)

    static func renderPreview(to path: String) {
        let size = contentSize
        let view = makeContentView()
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()

        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            FileHandle.standardError.write("render-about: no bitmap rep\n".data(using: .utf8)!)
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write("render-about: failed to encode PNG\n".data(using: .utf8)!)
            return
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("render-about: wrote \(path) (\(Int(size.width))x\(Int(size.height)))")
        } catch {
            FileHandle.standardError.write("render-about: \(error)\n".data(using: .utf8)!)
        }
    }
}

// MARK: - Window controller

final class AboutWindowController: NSWindowController {

    static let shared = AboutWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: AboutBuilder.contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L.t("关于 ScheutieOS")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        super.init(window: window)

        installContent()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    /// Built fresh on every presentation so a language switch is picked up
    /// without having to recreate the controller.
    private func installContent() {
        guard let window = window else { return }
        let content = AboutBuilder.makeContentView()
        content.frame = NSRect(origin: .zero, size: AboutBuilder.contentSize)
        content.autoresizingMask = [.width, .height]
        window.contentView = content
        window.setContentSize(AboutBuilder.contentSize)
    }

    func present() {
        guard let window = window else { return }
        window.title = L.t("关于 ScheutieOS")
        installContent()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
