import AppKit
import S2TCore

@MainActor final class DictionarySuggestions {
    struct Item {
        let id: UUID
        var correction: DictionaryCorrection
        var saved: Bool
        var expiresAt: TimeInterval
    }

    static let displayDuration: TimeInterval = 4
    private(set) var items: [Item] = []
    private(set) var panel: NSPanel?
    private(set) var deleteButtons: [UUID: NSButton] = [:]
    private(set) var rowFrames: [CGRect] = []
    private(set) var scheduledExpiry: TimeInterval?
    var visibleItems: [Item] { Array(items.filter { $0.saved && $0.expiresAt > now() }.prefix(50)) }
    private let file: DictionaryFile
    private let onError: (String) -> Void
    private let presentsWindows: Bool
    private let now: () -> TimeInterval
    private var anchor: CGRect?
    private var removedOriginals = Set<String>()
    private var expiration: Task<Void, Never>?

    init(file: DictionaryFile, presentsWindows: Bool = true,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         onError: @escaping (String) -> Void) {
        self.file = file
        self.presentsWindows = presentsWindows
        self.now = now
        self.onError = onError
    }

    func hide() {
        expiration?.cancel()
        expiration = nil
        scheduledExpiry = nil
        panel?.orderOut(nil)
    }

    func setAnchor(_ bounds: CGRect?) { anchor = bounds ?? anchor }

    @discardableResult func apply(_ corrections: [DictionaryCorrection], bounds: CGRect?) -> Bool {
        anchor = bounds ?? anchor
        let snapshot = corrections
        func matches(_ a: DictionaryCorrection, _ b: DictionaryCorrection) -> Bool {
            a == b
        }
        let obsolete = items.filter { item in item.saved && !snapshot.contains { matches($0, item.correction) } }
        let additions = snapshot.filter { correction in
            !removedOriginals.contains(correction.original) && !items.contains { $0.saved && matches($0.correction, correction) }
        }
        do {
            let added = try file.update(adding: additions, removing: obsolete.map(\.correction))
            for item in obsolete {
                if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].saved = false }
            }
            for entry in added {
                if let index = items.firstIndex(where: { !$0.saved && $0.correction.original == entry.original }) {
                    let isSameWord = obsolete.contains { $0.id == items[index].id }
                        && items[index].correction.replacement == entry.replacement
                    items[index].correction = entry
                    items[index].saved = true
                    if !isSameWord { items[index].expiresAt = now() + Self.displayDuration }
                } else {
                    items.append(Item(id: UUID(), correction: entry, saved: true, expiresAt: now() + Self.displayDuration))
                }
            }
            rebuild()
            return true
        } catch {
            onError("Could not save dictionary correction. " + error.localizedDescription)
            return false
        }
    }

    func remove(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].saved else { return }
        do {
            _ = try file.remove(items[index].correction)
            removedOriginals.insert(items[index].correction.original)
            items[index].saved = false
            rebuild()
        } catch { onError("Could not remove dictionary correction. " + error.localizedDescription) }
    }

    func expireDue() { rebuild() }

    private func rebuild() {
        expiration?.cancel()
        let visible = visibleItems
        guard !visible.isEmpty else { hide(); return }
        let panel = panel ?? DictionarySuggestionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.panel = panel
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.setAccessibilityLabel("Added to dictionary")

        let cocoaAnchor = anchor.map { CGRect(x: $0.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - $0.maxY, width: $0.width, height: $0.height) }
            ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: cocoaAnchor.midX, y: cocoaAnchor.midY)) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let longest = visible.map { ("\"\($0.correction.replacement)\"" as NSString).size(withAttributes: [.font: font]).width }.max() ?? 80
        let width = min(visibleFrame.width, 340, max(140, ceil(longest) + 74))
        func textHeights(rowWidth: CGFloat) -> [CGFloat] {
            visible.map { item in
                let size = ("\"\(item.correction.replacement)\"" as NSString).boundingRect(with: CGSize(width: rowWidth - 74, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).size
                return ceil(size.height) + 2
            }
        }
        let gap: CGFloat = 6
        let maxHeight = min(visibleFrame.height, 320)
        let needsScroll = textHeights(rowWidth: width).map { max(36, $0 + 16) }.reduce(0, +) + gap * CGFloat(visible.count - 1) > maxHeight
        let rowWidth = width - (needsScroll ? 14 : 0)
        let textWidth = rowWidth - 70
        let labelHeights = textHeights(rowWidth: rowWidth)
        let heights = labelHeights.map { max(36, $0 + 16) }
        let totalRows = heights.reduce(0, +) + gap * CGFloat(visible.count - 1)
        let height = min(maxHeight, totalRows)
        let frame = DictionaryLearner.popupFrame(above: cocoaAnchor, visibleFrame: visibleFrame, height: height, width: width)
        panel.setFrame(frame, display: false)
        let scroll = NSScrollView(frame: CGRect(origin: .zero, size: frame.size))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = totalRows > height
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        let rows = DictionaryFlippedView(frame: CGRect(x: 0, y: 0, width: width, height: totalRows))
        scroll.documentView = rows
        deleteButtons = [:]; rowFrames = []
        var y: CGFloat = 0
        for (index, item) in visible.enumerated() {
            let row = DictionaryToastRow(frame: CGRect(x: 0, y: y, width: rowWidth, height: heights[index]))
            rowFrames.append(row.frame)
            let icon = NSImageView(frame: CGRect(x: 12, y: (row.bounds.height - 12) / 2, width: 12, height: 12))
            icon.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Added to dictionary")?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
            icon.contentTintColor = .white.withAlphaComponent(0.8)
            row.ink.addSubview(icon)
            let quote = NSTextField(wrappingLabelWithString: "\"\(item.correction.replacement)\"")
            quote.font = font
            quote.textColor = .white
            quote.frame = CGRect(x: 32, y: (row.bounds.height - labelHeights[index]) / 2, width: textWidth, height: labelHeights[index])
            quote.toolTip = "Added to dictionary. Replaces \"\(item.correction.original)\"."
            quote.setAccessibilityLabel("\"\(item.correction.replacement)\" added to dictionary")
            row.ink.addSubview(quote)
            let remove = DictionaryRemoveButton { [weak self] in self?.remove(item.id) }
            remove.frame = CGRect(x: rowWidth - 30, y: (row.bounds.height - 24) / 2, width: 24, height: 24)
            remove.setAccessibilityLabel("Remove \"\(item.correction.replacement)\" from dictionary")
            row.ink.addSubview(remove)
            deleteButtons[item.id] = remove
            rows.addSubview(row)
            y += heights[index] + gap
        }
        panel.contentView = DictionaryToastBackground(frame: CGRect(origin: .zero, size: frame.size), scroll: scroll)
        panel.contentView?.layoutSubtreeIfNeeded()
        if presentsWindows { panel.orderFrontRegardless() }
        if let next = visible.map(\.expiresAt).min() {
            scheduledExpiry = next
            let remaining = max(0, next - now())
            expiration = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) } catch { return }
                guard !Task.isCancelled else { return }
                self?.expireDue()
            }
        }
    }
}

private final class DictionarySuggestionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor private final class DictionaryToastBackground: NSView {
    private let scroll: NSScrollView

    init(frame: CGRect, scroll: NSScrollView) {
        self.scroll = scroll
        super.init(frame: frame)
        scroll.autoresizingMask = [.width, .height]
        addSubview(scroll)
        needsLayout = true
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        scroll.tile()
    }
}

@MainActor private final class DictionaryToastRow: NSView {
    let ink: NSView
    private let material: NSView

    override init(frame: NSRect) {
        ink = DictionaryToastInk(frame: CGRect(origin: .zero, size: frame.size))
        if #available(macOS 26, *), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let glass = NSGlassEffectView(frame: ink.frame)
            glass.style = .clear
            glass.cornerRadius = frame.height / 2
            glass.appearance = NSAppearance(named: .darkAqua)
            glass.contentView = ink
            material = glass
        } else {
            material = NSView(frame: ink.frame)
            material.wantsLayer = true
            material.layer?.backgroundColor = NSColor(srgbRed: 0.045, green: 0.065, blue: 0.09, alpha: 1).cgColor
            material.addSubview(ink)
        }
        super.init(frame: frame)
        wantsLayer = true
        let mask = CAShapeLayer()
        mask.path = GlassCapsuleArtwork.path(in: bounds)
        layer?.mask = mask
        material.autoresizingMask = [.width, .height]
        ink.autoresizingMask = [.width, .height]
        addSubview(material)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        material.frame = bounds
        ink.frame = material.bounds
    }
}

@MainActor private final class DictionaryToastInk: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        GlassCapsuleArtwork.drawOverlay(in: bounds, context: context)
    }
}

private final class DictionaryFlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class DictionaryRemoveButton: NSButton {
    private let invoke: () -> Void
    init(action: @escaping () -> Void) {
        invoke = action
        super.init(frame: .zero)
        title = ""
        isBordered = false
        image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        contentTintColor = .white.withAlphaComponent(0.7)
        toolTip = "Remove from dictionary"
        target = self
        self.action = #selector(pressed)
        setButtonType(.momentaryPushIn)
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        (NSColor.white.withAlphaComponent(isHighlighted ? 0.16 : 0.045)).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
        super.draw(dirtyRect)
    }
    @objc private func pressed() { invoke() }
}
