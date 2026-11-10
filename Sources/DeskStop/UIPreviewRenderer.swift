#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only: `DeskStop --render-ui <dir>` draws the menu bar panel
/// and every Settings page from fixture data into PNGs, in light and dark,
/// then exits.
///
/// `main.swift` calls this before `AppDelegate` exists, so no store, hotkey,
/// display monitor, scheduler or onboarding ever runs: it cannot touch the
/// real desktop or the saved configurations. `@AppStorage` is pointed at a
/// throwaway suite for the same reason.
enum UIPreviewRenderer {
    static func run(outputDirectory: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let storage = UserDefaults(suiteName: "com.laithshareiyat.deskstop.render-ui")!

        for (appearanceName, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for (fixtureName, snapshot) in [("full", fullFixture), ("empty", emptyFixture)] {
                let model = AppModel(source: { snapshot })
                // The empty fixture also shows the missing-Finder-access card.
                PermissionCenter.shared.setForPreview(
                    finder: fixtureName == "empty" ? .denied : .granted, notifications: .granted)
                if fixtureName == "full" {
                    // Other setups open: the panel grows to fit them, rather
                    // than scrolling at its folded height.
                    storage.set(PanelTab.configurations.rawValue, forKey: "panelSelectedTab")
                    let view = MenuPanelView(model: model,
                                             expandedSetups: Set(snapshot.otherGroups.map(\.id)))
                        .defaultAppStorage(storage)
                        .background(PopoverBackdrop())
                    render(view, appearance: appearance, size: nil,
                           to: output.appendingPathComponent("panel-full-configurations-expanded-\(appearanceName).png"))
                }
                for tab in PanelTab.allCases where fixtureName == "full" || tab == .configurations {
                    storage.set(tab.rawValue, forKey: "panelSelectedTab")
                    let view = MenuPanelView(model: model)
                        .defaultAppStorage(storage)
                        .background(PopoverBackdrop())
                    render(view, appearance: appearance, size: nil,
                           to: output.appendingPathComponent("panel-\(fixtureName)-\(tab.rawValue)-\(appearanceName).png"))
                }
            }
            // Settings shows the not-granted controls: Turn On, and its
            // Start Over menu where the permission has one.
            PermissionCenter.shared.setForPreview(finder: .denied, notifications: .notDetermined)
            let model = AppModel(source: { fullFixture })
            model.notificationWarning = "macOS is set to show no banners for DeskStop, so notifications are delivered to Notification Centre without appearing on screen. Set its alert style to Banners or Alerts."
            for page in SettingsPage.allCases {
                let router = SettingsRouter()
                router.page = page
                let view = SettingsView(model: model, router: router)
                    .background(Color(nsColor: .windowBackgroundColor))
                render(view, appearance: appearance, size: SettingsWindow.defaultContentSize,
                       to: output.appendingPathComponent("settings-\(page.rawValue)-\(appearanceName).png"))
            }
        }
        // The hidden-icons picture gallery, from this Mac's own wallpapers.
        for (appearanceName, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let gallery = PictureGallery(selected: fullFixture.hiddenIconsPicture,
                                         choose: { _ in }, chooseFile: {}, cancel: {})
                .background(Color(nsColor: .windowBackgroundColor))
            render(gallery, appearance: appearance, size: NSSize(width: 620, height: 540),
                   to: output.appendingPathComponent("picture-gallery-\(appearanceName).png"))
        }
        renderStatusIcons(to: output.appendingPathComponent("status-icons.png"))
        renderPanelTour(storage: storage, to: output)
        // The links Settings → Feedback opens, to check what they carry.
        let links = [Feedback.bugReportURL, Feedback.featureRequestURL].compactMap { $0?.absoluteString }
        try? links.joined(separator: "\n\n").write(to: output.appendingPathComponent("feedback-links.txt"),
                                                    atomically: true, encoding: .utf8)
        // The welcome tour on its "save a layout" step: Finder access on,
        // nothing saved yet.
        PermissionCenter.shared.setForPreview(finder: .granted, notifications: .notDetermined)
        for (appearanceName, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let tour = WelcomeTourView(model: AppModel(source: { emptyFixture }), state: WelcomeTourState(),
                                       finish: {}, showMeAround: {})
                .background(Color(nsColor: .windowBackgroundColor))
            render(tour, appearance: appearance, size: nil,
                   to: output.appendingPathComponent("welcome-save-step-\(appearanceName).png"))
        }
        print("Rendered UI previews to \(output.path)")
    }

    /// The walk-through at every stop, on the tab it switches to, plus its
    /// New Layout stop with nothing saved (the empty state's button).
    private static func renderPanelTour(storage: UserDefaults, to output: URL) {
        PermissionCenter.shared.setForPreview(finder: .granted, notifications: .granted)
        let cases: [(String, PanelSnapshot, [PanelTourStop])] = [
            ("full", fullFixture, PanelTourStop.stops(hasLayouts: true)),
            ("empty", emptyFixture, [.newLayout]),
        ]
        for (fixtureName, snapshot, stops) in cases {
            for (number, stop) in stops.enumerated() {
                let model = AppModel(source: { snapshot })
                model.panelTour = stop
                storage.set(stop.tab.rawValue, forKey: "panelSelectedTab")
                let view = MenuPanelView(model: model)
                    .defaultAppStorage(storage)
                    .background(PopoverBackdrop())
                render(view, appearance: .aqua, size: nil,
                       to: output.appendingPathComponent(
                        String(format: "tour-%@-%02d-%@.png", fixtureName, number + 1, "\(stop)")))
            }
        }
    }

    /// The popover's own background is not part of the hosted view, so the
    /// preview draws the solid one the panel has before Liquid Glass.
    private struct PopoverBackdrop: View {
        var body: some View {
            Color(nsColor: .windowBackgroundColor)
        }
    }

    /// Both menu bar glyphs at menu bar size, on a light and a dark strip,
    /// with a hairline around the canvas so clipping or off-centre drawing
    /// shows. They must come out the same size.
    private static func renderStatusIcons(to url: URL) {
        let glyphs = [AppDelegate.statusBarIcon(hidden: false), AppDelegate.statusBarIcon(hidden: true)]
        let scale: CGFloat = 4
        let cell = NSSize(width: 40, height: 24)
        let size = NSSize(width: cell.width * 2 * scale, height: cell.height * 2 * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width),
                                         pixelsHigh: Int(size.height), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
        for (row, (background, ink)) in [(NSColor(white: 0.93, alpha: 1), NSColor.black),
                                         (NSColor(white: 0.15, alpha: 1), NSColor.white)].enumerated() {
            background.setFill()
            NSRect(x: 0, y: CGFloat(row) * cell.height, width: cell.width * 2, height: cell.height).fill()
            for (column, glyph) in glyphs.enumerated() {
                guard let glyph else { continue }
                let origin = NSPoint(x: CGFloat(column) * cell.width + (cell.width - glyph.size.width) / 2,
                                     y: CGFloat(row) * cell.height + (cell.height - glyph.size.height) / 2)
                let box = NSRect(origin: origin, size: glyph.size)
                // A template image draws black; tint it like the menu bar does.
                let tinted = NSImage(size: glyph.size, flipped: false) { rect in
                    glyph.draw(in: rect)
                    ink.set()
                    rect.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: box)
                NSColor.systemRed.withAlphaComponent(0.6).setStroke()
                NSBezierPath(rect: box.insetBy(dx: 0.25, dy: 0.25)).stroke()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func render<V: View>(_ view: V, appearance: NSAppearance.Name,
                                        size: NSSize?, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: appearance)
        let initial = size ?? NSSize(width: PanelStyle.panelWidth, height: 600)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: initial),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = host.appearance
        window.contentView = host
        // Two passes: the panel measures its page, then sizes to it.
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            if size == nil { window.setContentSize(host.fittingSize) }
            RunLoop.current.run(until: Date().addingTimeInterval(size == nil ? 0.15 : 0.6))
        }
        let bounds = host.bounds
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        host.cacheDisplay(in: bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        window.close()
    }

    // MARK: - Fixtures

    private static func configuration(_ name: String, isDefault: Bool = false, shortcut: String? = nil,
                                      icons: Int, displays: Int = 0, apps: [String] = [],
                                      restoresIcons: Bool = true, restoresDisplays: Bool = false,
                                      restoresModes: Bool = false,
                                      launchesApps: Bool = false) -> ConfigurationSummary {
        let modes = ["LG HDR 4K at 2560 × 1440, 60 Hz", "Built-in Retina Display at 1512 × 982, 120 Hz"]
        return ConfigurationSummary(id: UUID(), name: name, isDefault: isDefault, shortcut: shortcut,
                             iconCount: icons, displayCount: displays,
                             mainDisplayName: displays > 0 ? "LG HDR 4K" : nil, appNames: apps,
                             displayModes: Array(modes.prefix(displays)),
                             restoresIcons: restoresIcons && icons > 0,
                             restoresDisplays: restoresDisplays && displays > 0,
                             restoresDisplayModes: restoresModes && displays > 0,
                             launchesApps: launchesApps && !apps.isEmpty)
    }

    private static let fullFixture: PanelSnapshot = {
        var s = PanelSnapshot()
        s.currentDisplayLabel = "Built-in Retina Display + LG HDR 4K"
        s.isDocked = true
        s.currentGroup = DisplayGroup(id: "a|b", label: s.currentDisplayLabel, configurations: [
            configuration("Office", isDefault: true, shortcut: "⌃⌥1", icons: 42, displays: 2,
                          apps: ["Slack", "Mail", "Safari"], restoresDisplays: true, restoresModes: true,
                          launchesApps: true),
            configuration("Clean Desk", shortcut: "⌃⌥2", icons: 12),
            configuration("Presenting", icons: 30, displays: 2, restoresIcons: false, restoresDisplays: true),
        ])
        s.otherGroups = [
            DisplayGroup(id: "a", label: "Built-in Retina Display", configurations: [
                configuration("Travel", isDefault: true, icons: 18),
                configuration("Couch", icons: 9),
            ]),
            DisplayGroup(id: "a|c", label: "Built-in Retina Display + DELL U2719D", configurations: [
                configuration("Home Office", icons: 40, displays: 2, restoresDisplays: true),
            ]),
        ]
        s.undoTitle = "Undo Last Restore"
        s.nextSchedule = "Next: Morning at Mon 9:00 AM"
        s.scheduleCount = 2
        s.hideOnScreenShare = false
        // The busier of the two states: a picture shows its name and Choose.
        s.hiddenIconsPicture = URL(fileURLWithPath: "/System/Library/Desktop Pictures/Sonoma.heic")
        s.showNotifications = true
        s.startAtLogin = true
        s.desktopHidden = false
        s.hideShortcut = "⌃⌥H"
        s.cycleShortcut = nil
        return s
    }()

    private static let emptyFixture: PanelSnapshot = {
        var s = PanelSnapshot()
        s.currentDisplayLabel = "Built-in Retina Display"
        s.currentGroup = DisplayGroup(id: "a", label: s.currentDisplayLabel, configurations: [])
        return s
    }()
}
#endif
