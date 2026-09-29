import AppKit
import S2TCore

@MainActor enum SettingsSidebarProbe {
    static func run() throws {
        try verifyWallpaperArtwork()
        try verifyWallpaperResizing()
        let sidebar = AppearanceSidebarController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: AppearanceSidebarController.containerWidth, height: 720),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentViewController = sidebar
        window.setContentSize(NSSize(width: AppearanceSidebarController.containerWidth, height: 720))
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        defer { window.contentViewController = nil }
        sidebar.view.layoutSubtreeIfNeeded()
        guard sidebar.background.frame == sidebar.view.bounds.insetBy(dx: 8, dy: 8),
              sidebar.background.bounds.width == 88, sidebar.background.layer?.cornerRadius == 12,
              sidebar.background.layer?.masksToBounds == true,
              sidebar.table.style == .plain, sidebar.table.selectionHighlightStyle == .none,
              sidebar.table.focusRingType == .none, sidebar.table.numberOfRows == 7 else {
            throw failure("Sidebar must retain its eight-point inset, 88-point rail and custom selection: root=\(sidebar.view.bounds), background=\(sidebar.background.frame), radius=\(sidebar.background.layer?.cornerRadius ?? -1), clipping=\(sidebar.background.layer?.masksToBounds ?? false), rows=\(sidebar.table.numberOfRows), style=\(sidebar.table.style.rawValue), selection=\(sidebar.table.selectionHighlightStyle.rawValue), focus=\(sidebar.table.focusRingType.rawValue)")
        }
        if #available(macOS 26, *) {
            guard let glass = sidebar.material as? NSGlassEffectView,
                  glass.cornerRadius == 12, glass.contentView === sidebar.navigationContent else {
                throw failure("Sidebar navigation must sit inside one rounded Liquid Glass surface")
            }
        }
        var visited = Set<String>()
        sidebar.onAppearance = { visited.insert("Appearance") }
        sidebar.onModels = { visited.insert("Models") }
        sidebar.onAPIKeys = { visited.insert("API keys") }
        sidebar.onWriting = { visited.insert("Writing") }
        sidebar.onMeetings = { visited.insert("Meetings") }
        sidebar.onRecentRecordings = { visited.insert("Recent recordings") }
        sidebar.onDictation = { visited.insert("Dictation") }
        let names = ["Appearance", "Models", "API keys", "Writing", "Meetings", "Recent recordings", "Dictation"]
        for row in names.indices {
            sidebar.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            guard let cell = sidebar.table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView,
                  cell.accessibilityLabel() == names[row], cell.toolTip == names[row], cell.textField == nil,
                  cell.subviews.compactMap({ $0 as? NSImageView }).first?.image?.isTemplate == true else {
                throw failure("Missing icon, tooltip or accessibility name at row \(row)")
            }
        }
        guard visited == Set(names) else { throw failure("A destination lost its action") }
        func plate(_ row: Int) throws -> SettingsSidebarSelectionPlate {
            guard let cell = sidebar.table.view(atColumn: 0, row: row, makeIfNecessary: true),
                  let plate = cell.subviews.compactMap({ $0 as? SettingsSidebarSelectionPlate }).first else {
                throw failure("Missing custom sidebar tile")
            }
            cell.layoutSubtreeIfNeeded()
            return plate
        }
        let selected = try plate(sidebar.dictationRow)
        guard !selected.isHidden, selected.alphaValue == 1,
              selected.bounds.size == NSSize(width: 44, height: 44), selected.layer?.cornerRadius == 10,
              selected.layer?.backgroundColor == NSColor.white.cgColor else {
            throw failure("Selected destination must use the original square white tile")
        }
        let idle = try plate(sidebar.modelsRow)
        guard idle.isHidden,
              let row = sidebar.table.rowView(atRow: sidebar.modelsRow, makeIfNecessary: true) as? SettingsSidebarRow else {
            throw failure("Idle navigation must not display a selected tile")
        }
        row.setHover(true)
        guard row.isHovered, !idle.isHidden, abs(idle.alphaValue - 0.10) < 0.001 else {
            throw failure("Original subtle hover fill is missing")
        }
        row.setHover(false)
        guard idle.isHidden else { throw failure("Hover did not clear") }
        sidebar.logo.setHover(true)
        guard sidebar.logo.isHovered, abs((sidebar.logo.layer?.backgroundColor?.alpha ?? 0) - 0.10) < 0.001 else {
            throw failure("Logo hover fill is missing")
        }
        sidebar.logo.setHover(false)
        guard sidebar.logo.cell?.imageRect(forBounds: sidebar.logo.bounds).size == NSSize(width: 38, height: 26) else {
            throw failure("Original logo proportions changed")
        }

        window.makeFirstResponder(sidebar.table)
        let up = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{F700}", charactersIgnoringModifiers: "\u{F700}", isARepeat: false, keyCode: 126)!
        sidebar.table.keyDown(with: up)
        guard sidebar.table.selectedRow == sidebar.recentRecordingsRow else { throw failure("Native keyboard navigation failed") }
        var dashboard = false
        sidebar.onDashboard = { dashboard = true }
        sidebar.logo.performClick(nil)
        guard dashboard, sidebar.table.selectedRow == -1, sidebar.logo.state == .on else { throw failure("Home navigation failed") }
        sidebar.selectAppearance()
        guard sidebar.logo.state == .off else { throw failure("Home selection did not clear") }
        var policy: URL?
        sidebar.openPolicy = { policy = $0 }
        sidebar.policiesLink.performClick(nil)
        guard policy == sidebar.policiesURL, policy != nil else { throw failure("Bundled policies are unavailable") }
        for mode in GlowAppearance.allCases { sidebar.updateBackground(mode) }
        let count = sidebar.backgroundRenderCount
        let start = CACurrentMediaTime()
        for _ in 0..<20 { for mode in GlowAppearance.allCases { sidebar.updateBackground(mode) } }
        guard sidebar.backgroundRenderCount == count, sidebar.maximumBackgroundDimension <= 1440 else {
            throw failure("Appearance sidebar cache grew during repeated navigation")
        }
        sidebar.updateBackground(nil)
        guard sidebar.backdrop.wallpaperLayer.contents == nil else { throw failure("Ordinary settings retained preview artwork") }
        for theme in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: theme)
            sidebar.view.layoutSubtreeIfNeeded()
            guard sidebar.navigationContent.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == theme else {
                throw failure("Sidebar does not inherit the system appearance")
            }
        }
        guard !window.isVisible else { throw failure("Verification exposed its window") }
        print(String(format: "PASS: inset Liquid Glass sidebar, original tiles and hover, keyboard, all destinations, Home, policies, themes and bounded artwork cache; 120 cached switches %.2f ms. No screen capture.", (CACurrentMediaTime() - start) * 1000))
    }
    private static func verifyWallpaperResizing() throws {
        // Reproduce a width-only change without giving the fixed rail a layout
        // pass. The preview notification must update its background immediately.
        let fixture = NSView(frame: NSRect(x: 0, y: 0, width: 1040, height: 720))
        let fixedRail = SettingsSidebarBackdrop(frame: NSRect(x: 0, y: 0, width: 104, height: 720))
        let resizingPreview = NSView(frame: NSRect(x: 104, y: 0, width: 676, height: 720))
        fixture.addSubview(fixedRail)
        fixture.addSubview(resizingPreview)
        fixedRail.previewViewport = resizingPreview
        fixedRail.setWallpaper(nil, mode: .aroundNotch)
        let before = fixedRail.wallpaperLayer.frame
        resizingPreview.setFrameSize(NSSize(width: 936, height: 720))
        guard fixedRail.wallpaperLayer.frame != before,
              abs(fixedRail.wallpaperLayer.frame.maxX - resizingPreview.frame.maxX) < 0.01,
              fixedRail.bounds.size == NSSize(width: 104, height: 720) else {
            throw failure("A preview-only resize left the fixed sidebar's background at the previous size")
        }
        let controller = AppearanceWindowController(state: AppState(preview: true), presentsWindows: false)
        let window = controller.prepare()
        defer { window.close() }
        guard let host = controller.previewHost else { throw failure("Missing Appearance viewport") }
        let backdrop = controller.sidebar.backdrop
        let sizes = [NSSize(width: 780, height: 720), NSSize(width: 1040, height: 720),
                     NSSize(width: 820, height: 720), NSSize(width: 1040, height: 860),
                     NSSize(width: 780, height: 1000), NSSize(width: 920, height: 760),
                     NSSize(width: 780, height: 720)]
        for mode in GlowAppearance.allCases {
            controller.selectPreview(mode)
            let renderCount = controller.sidebar.backgroundRenderCount
            for size in sizes {
                window.setContentSize(size)
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                window.contentView?.superview?.layoutSubtreeIfNeeded()
                window.contentView?.layoutSubtreeIfNeeded()
                // Do not refresh the controller or backdrop here: resize must
                // update the continuation through the production geometry path.
                let viewport = host.convert(host.bounds, to: nil)
                let image = backdrop.convert(backdrop.wallpaperLayer.frame, to: nil)
                let scene = AppearancePreviewScene.size(for: mode)
                let placement = AppearancePreviewScene.placement(for: mode, viewport: viewport.size,
                    topInset: AppearancePreviewScene.topInset(of: host))
                let scale = placement.scale
                let mainWidth = image.width * scene.width / (scene.width + AppearancePreviewScene.sidebarLeadingWidth)
                let mainCenter = image.maxX - mainWidth / 2
                // The preview subject stays in the free band between the toolbar and the real panel.
                let panel = controller.controlsPanel.convert(controller.controlsPanel.bounds, to: nil)
                let panelTop = viewport.maxY - panel.maxY
                let topInset = AppearancePreviewScene.topInset(of: host)
                guard abs(panel.maxY - viewport.minY - AppearancePreviewScene.controlsReserve) < 0.5 else {
                    throw failure("Settings panel moved away from its reserved preview band: \(panel)")
                }
                if let subject = AppearancePreviewScene.subject(for: mode) {
                    let top = placement.origin.y + subject.lowerBound * scale
                    let bottom = placement.origin.y + subject.upperBound * scale
                    guard top >= topInset + 1, bottom <= panelTop - 1,
                          abs((top - topInset) - (panelTop - bottom)) < 0.5 else {
                        throw failure("\(mode) preview is not centered between the toolbar and settings: \(top)...\(bottom), band \(topInset)...\(panelTop)")
                    }
                } else if mode == .bottom, placement.origin.y + AppearancePreviewScene.bottomDisplayHeight * scale > panelTop {
                    throw failure("Bottom glow is hidden behind the settings panel at \(size)")
                }
                // Input previews may shrink onto their uniform background color.
                let covered = backdrop.wallpaperLayer.frame.insetBy(dx: -0.01, dy: -0.01).contains(backdrop.bounds)
                    || mode.followsInput && backdrop.layer?.backgroundColor == AppearancePreviewScene.inputBackgroundColor.cgColor
                guard abs(image.maxY - (viewport.maxY - placement.origin.y)) < 0.01,
                      abs(image.height - scene.height * scale) < 0.01,
                      abs(mainWidth - scene.width * scale) < 0.01,
                      abs(mainCenter - (viewport.minX + placement.origin.x + scene.width * scale / 2)) < 0.01,
                      covered,
                      backdrop.wallpaperLayer.animationKeys()?.isEmpty != false,
                      controller.sidebar.backgroundRenderCount == renderCount,
                      !window.isVisible else {
                    throw failure("Sidebar wallpaper fell out of alignment during resize: \(mode), size=\(size), image=\(image), viewport=\(viewport)")
                }
            }
        }
        controller.showDashboard()
        window.setContentSize(NSSize(width: 1040, height: 860))
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        guard backdrop.wallpaperLayer.isHidden, backdrop.wallpaperLayer.contents == nil else {
            throw failure("Resizing Home restored stale Appearance artwork")
        }
        print("PASS: all Appearance backgrounds stay aligned through repeated width/height resizing without image regeneration or layer animations. Hidden geometry only.")
    }

    private static func verifyWallpaperArtwork() throws {
        func bytes(_ image: CGImage) -> [UInt8] {
            var output = [UInt8](repeating: 0, count: image.width * image.height * 4)
            output.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            return output
        }
        for mode in [GlowAppearance.bottom, .aroundNotch] {
            let original = mode == .bottom ? AppearancePreviewScene.bottomWallpaper : AppearancePreviewScene.notchWallpaper
            guard let original = original?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let extended = AppearancePreviewScene.sidebarWallpaper(for: mode)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  extended.height == original.height, extended.width > original.width,
                  let main = extended.cropping(to: CGRect(x: extended.width - original.width, y: 0,
                      width: original.width, height: original.height)) else {
                throw failure("Missing original Figma artwork or uncropped sidebar continuation")
            }
            let oldBytes = bytes(original), mainBytes = bytes(main)
            let differences = zip(oldBytes, mainBytes).map { abs(Int($0) - Int($1)) }
            guard differences.max() ?? 0 <= 1 else {
                throw failure("Extending the wallpaper changed the main preview artwork for \(mode)")
            }
            let allBytes = bytes(extended)
            let prefixWidth = extended.width - original.width
            var maximumDistinct = 0
            for y in stride(from: 0, to: extended.height, by: 16) {
                var colors = Set<UInt32>()
                for x in stride(from: 0, to: prefixWidth, by: 4) {
                    let offset = (y * extended.width + x) * 4
                    colors.insert(UInt32(allBytes[offset]) << 16 | UInt32(allBytes[offset + 1]) << 8 | UInt32(allBytes[offset + 2]))
                }
                maximumDistinct = max(maximumDistinct, colors.count)
            }
            guard maximumDistinct > 8 else { throw failure("Sidebar artwork repeats a source column instead of continuing the image") }
        }
        print("PASS: original Figma artwork continues under the sidebar with distinct source columns and unchanged main-preview pixels. Asset bitmaps only, no screen capture.")
    }

    private static func failure(_ text: String) -> NSError { NSError(domain: "SettingsSidebar", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
