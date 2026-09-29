import AppKit
import CoreText
import S2TCore

@MainActor final class AppearanceSidebarController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    static let width: CGFloat = 88
    static let inset: CGFloat = 8
    static let containerWidth = width + 2 * inset
    static let cornerRadius: CGFloat = 12
    let background = SettingsSidebarBackground()
    let backdrop = SettingsSidebarBackdrop(frame: .zero)
    var pageBackgroundColor: NSColor? {
        didSet { if isViewLoaded { updateAccessibility() } }
    }
    let table = NSTableView()
    let logo = SettingsDashboardButton(frame: .zero)
    let navigationContent = NSView()
    private(set) lazy var material = SettingsGlassBar.make(content: navigationContent, cornerRadius: Self.cornerRadius)
    private let shade = NSView()
    let creditNumber = NSButton(title: "--", target: nil, action: nil)
    private var renderedCreditNumber: String?
    let creditCaption = NSTextField(labelWithString: "credits")
    private static let creditFontName: String = {
        if let url = Bundle.main.url(forResource: "BitcountPropSingle-Regular", withExtension: "ttf", subdirectory: "Typography/BitcountPropSingle") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return "BitcountPropSingle-Regular"
    }()
    let policiesLink = NSButton(title: "Policies", target: nil, action: nil)
    var policiesURL: URL? { Bundle.main.url(forResource: "privacy", withExtension: "html", subdirectory: "policies") }
    var openPolicy: (URL) -> Void = { NSWorkspace.shared.open($0) }
    private(set) var backgroundMode: GlowAppearance?
    private var wallpaperImages: [GlowAppearance: CGImage] = [:]
    private var accessibilityObserver: NSObjectProtocol?
    private(set) var backgroundRenderCount = 0
    var maximumBackgroundDimension: Int { wallpaperImages.values.map { max($0.width, $0.height) }.max() ?? 0 }
    var onDashboard: (() -> Void)?
    var onAppearance: (() -> Void)?
    var onAPIKeys: (() -> Void)?
    var onModels: (() -> Void)?
    var onWriting: (() -> Void)?
    var onRecentRecordings: (() -> Void)?
    var onMeetings: (() -> Void)?
    var onDictation: (() -> Void)?

    override func loadView() {
        view = backdrop
        backdrop.addSubview(background)
        background.translatesAutoresizingMaskIntoConstraints = false
        background.wantsLayer = true
        background.layer?.masksToBounds = true
        background.layer?.cornerRadius = Self.cornerRadius
        background.layer?.cornerCurve = .continuous
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: Self.inset),
            background.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor, constant: -Self.inset),
            background.topAnchor.constraint(equalTo: backdrop.topAnchor, constant: Self.inset),
            background.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor, constant: -Self.inset)
        ])
        shade.wantsLayer = true
        for child in [shade, material] {
            child.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(child)
            NSLayoutConstraint.activate([
                child.leadingAnchor.constraint(equalTo: background.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: background.trailingAnchor),
                child.topAnchor.constraint(equalTo: background.topAnchor),
                child.bottomAnchor.constraint(equalTo: background.bottomAnchor)
            ])
        }
        background.onAppearanceChange = { [weak self] in self?.updateAccessibility() }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateAccessibility() }
            }
        logo.image = NSImage(named: "MenuBar")
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.imagePosition = .imageOnly
        logo.contentTintColor = .labelColor
        logo.isBordered = false
        logo.target = self
        logo.action = #selector(showDashboard)
        logo.toolTip = "Dashboard"
        logo.identifier = .init("settings.logo")
        logo.setAccessibilityLabel("S2T Dashboard")

        policiesLink.isBordered = false
        policiesLink.font = .systemFont(ofSize: 11)
        policiesLink.attributedTitle = NSAttributedString(string: "Policies", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ])
        policiesLink.identifier = .init("settings.policies")
        policiesLink.setAccessibilityLabel("Privacy and policies")
        policiesLink.target = self
        policiesLink.action = #selector(showPolicies)
        policiesLink.isEnabled = policiesURL != nil
        creditNumber.isBordered = false
        creditNumber.identifier = .init("settings.credits")
        creditNumber.target = self
        creditNumber.action = #selector(showCreditKey)
        creditCaption.font = .systemFont(ofSize: 10)
        creditCaption.textColor = .secondaryLabelColor
        creditCaption.alignment = .center
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.hasVerticalScroller = false
        for child in [logo, scroll, creditNumber, creditCaption, policiesLink] {
            child.translatesAutoresizingMaskIntoConstraints = false
            navigationContent.addSubview(child)
        }
        NSLayoutConstraint.activate([
            logo.centerXAnchor.constraint(equalTo: navigationContent.centerXAnchor),
            logo.topAnchor.constraint(equalTo: navigationContent.topAnchor, constant: 53),
            logo.widthAnchor.constraint(equalToConstant: 52), logo.heightAnchor.constraint(equalToConstant: 44),
            scroll.leadingAnchor.constraint(equalTo: navigationContent.leadingAnchor, constant: 18),
            scroll.trailingAnchor.constraint(equalTo: navigationContent.trailingAnchor, constant: -18),
            scroll.topAnchor.constraint(equalTo: logo.bottomAnchor, constant: 23),
            scroll.bottomAnchor.constraint(equalTo: creditNumber.topAnchor, constant: -16),
            creditNumber.leadingAnchor.constraint(equalTo: navigationContent.leadingAnchor, constant: 6),
            creditNumber.trailingAnchor.constraint(equalTo: navigationContent.trailingAnchor, constant: -6),
            creditNumber.heightAnchor.constraint(equalToConstant: 34),
            creditNumber.bottomAnchor.constraint(equalTo: creditCaption.topAnchor, constant: -1),
            creditCaption.centerXAnchor.constraint(equalTo: navigationContent.centerXAnchor),
            creditCaption.bottomAnchor.constraint(equalTo: policiesLink.topAnchor, constant: -14),
            policiesLink.centerXAnchor.constraint(equalTo: navigationContent.centerXAnchor),
            policiesLink.bottomAnchor.constraint(equalTo: navigationContent.bottomAnchor, constant: -14),
            policiesLink.heightAnchor.constraint(equalToConstant: 24)
        ])
        table.identifier = .init("appearance.sidebar")
        table.style = .plain
        table.selectionHighlightStyle = .none
        table.focusRingType = .none
        table.backgroundColor = .clear
        table.headerView = nil
        table.rowHeight = 48
        table.intercellSpacing = NSSize(width: 0, height: 10)
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let column = NSTableColumn(identifier: .init("destination"))
        column.minWidth = 0
        column.width = Self.width - 36
        table.addTableColumn(column)
        table.frame.size.width = column.width
        table.autoresizingMask = .width
        table.delegate = self
        table.dataSource = self
        table.setAccessibilityLabel("Settings navigation")
        scroll.documentView = table
        updateCredits(nil)
        updateAccessibility()
    }

    deinit {
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
    }

    func selectDashboard() {
        loadViewIfNeeded()
        table.deselectAll(nil)
        logo.isDashboardSelected = true
    }

    @objc private func showDashboard() {
        selectDashboard()
        onDashboard?()
    }

    @objc private func showCreditKey() { onAPIKeys?() }

    func updateCredits(_ balance: CreditBalance?, hidden: Bool = false) {
        guard isViewLoaded else { return }
        creditNumber.isHidden = hidden
        creditCaption.isHidden = hidden
        guard !hidden else { return }
        let number: String
        if let value = balance?.available {
            number = value.formatted(.number.grouping(.never).precision(.fractionLength(0)))
        } else { number = "--" }
        if renderedCreditNumber != number {
            var size: CGFloat = 26
            var font = NSFont(name: Self.creditFontName, size: size) ?? .monospacedDigitSystemFont(ofSize: size, weight: .regular)
            while (number as NSString).size(withAttributes: [.font: font]).width > Self.width - 16 && size > 10 {
                size -= 1
                font = NSFont(name: Self.creditFontName, size: size) ?? .monospacedDigitSystemFont(ofSize: size, weight: .regular)
            }
            creditNumber.font = font
            creditNumber.attributedTitle = NSAttributedString(string: number, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
            renderedCreditNumber = number
        }
        var help = "Add your S2T key in API keys to see available credits."
        if let balance {
            help = "Available: \(balance.available.formatted()) credits. Pending: \(balance.reserved.formatted()) credits."
            if let limit = balance.keyLimit, let remaining = limit.remainingCredits {
                help += " This key can use \(remaining.formatted()) more credits."
            }
        }
        creditNumber.toolTip = help
        creditNumber.setAccessibilityLabel("S2T credits")
        creditNumber.setAccessibilityValue(balance.map { "\($0.available.formatted()) available credits" } ?? "Balance unavailable")
        creditNumber.setAccessibilityHelp(help)
    }

    @objc private func showPolicies() {
        if let url = policiesURL { openPolicy(url) }
    }

    private func updateAccessibility() {
        let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        backdrop.pageBackgroundColor = pageBackgroundColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            shade.layer?.backgroundColor = opaque ? (pageBackgroundColor ?? .windowBackgroundColor).cgColor : nil
        }
        table.enumerateAvailableRowViews { row, _ in
            (row as? SettingsSidebarRow)?.setHover(false)
            row.needsDisplay = true
        }
    }

    func updateBackground(_ mode: GlowAppearance?) {
        loadViewIfNeeded()
        guard backgroundMode != mode else { return }
        backgroundMode = mode
        guard let mode else {
            backdrop.setWallpaper(nil, mode: nil)
            updateAccessibility()
            return
        }
        let cacheMode: GlowAppearance = mode.isClassic ? .bezel : mode == .withinInput ? .aroundInput : mode
        if wallpaperImages[cacheMode] == nil {
            if let image = AppearancePreviewScene.sidebarWallpaper(for: mode),
               let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
               let bitmap = CGContext(data: nil, width: Int(ceil(image.size.width)), height: Int(ceil(image.size.height)),
                   bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                bitmap.interpolationQuality = .high
                bitmap.draw(source, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
                wallpaperImages[cacheMode] = bitmap.makeImage()
            }
            backgroundRenderCount += 1
        }
        backdrop.setWallpaper(wallpaperImages[cacheMode], mode: mode)
        updateAccessibility()
    }

    var keysRow: Int { modelsRow + 1 }
    var writingRow: Int { keysRow + 1 }
    var meetingsRow: Int { writingRow + 1 }
    var recentRecordingsRow: Int { meetingsRow + 1 }
    var dictationRow: Int { recentRecordingsRow + 1 }
    let appearanceRow = 0
    let modelsRow = 1
    private func isGroup(_ row: Int) -> Bool { false }
    func numberOfRows(in tableView: NSTableView) -> Int { 7 }
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { isGroup(row) }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { !isGroup(row) }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { isGroup(row) ? 24 : 48 }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = SettingsSidebarRow()
        view.isHeading = isGroup(row)
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier(isGroup(row) ? "sidebar.heading" : "sidebar.destination")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? AppearanceSidebarCell ?? AppearanceSidebarCell(group: isGroup(row))
        cell.identifier = identifier
        let title: String
        if isGroup(row) { title = "Dictation" }
        else if row == modelsRow { title = "Models" }
        else if row == keysRow { title = "API keys" }
        else if row == writingRow { title = "Writing" }
        else if row == meetingsRow { title = "Meetings" }
        else if row == recentRecordingsRow { title = "Recent recordings" }
        else if row == dictationRow { title = "Dictation" }
        else { title = "Appearance" }
        let icon: SidebarGlyph? = isGroup(row) ? nil : row == modelsRow ? .models : row == keysRow ? .keys : row == writingRow ? .writing : row == meetingsRow ? .meetings : row == recentRecordingsRow ? .recordings : row == dictationRow ? .dictation : .appearance
        cell.configure(title: title, icon: icon, selected: tableView.selectedRow == row)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if table.selectedRow >= 0 { logo.isDashboardSelected = false }
        if table.selectedRow == keysRow { onAPIKeys?(); return }
        if table.selectedRow == modelsRow { onModels?(); return }
        if table.selectedRow == writingRow { onWriting?(); return }
        if table.selectedRow == recentRecordingsRow { onRecentRecordings?(); return }
        if table.selectedRow == meetingsRow { onMeetings?(); return }
        if table.selectedRow == dictationRow { onDictation?(); return }
        if table.selectedRow == appearanceRow { onAppearance?() }
    }

    func selectAppearance() {
        loadViewIfNeeded()
        guard table.selectedRow != appearanceRow else { return }
        table.selectRowIndexes(IndexSet(integer: appearanceRow), byExtendingSelection: false)
    }

    func selectModels() {
        loadViewIfNeeded()
        table.selectRowIndexes(IndexSet(integer: modelsRow), byExtendingSelection: false)
    }


}

final class AppearanceIconView: NSView {
    private let glyph = NSImageView()
    private var color: NSColor
    override var allowsVibrancy: Bool { false }
    init(symbol: String, color: NSColor, size: CGFloat) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        translatesAutoresizingMaskIntoConstraints = false
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        glyph.symbolConfiguration = .init(pointSize: size * 0.58, weight: .medium)
        glyph.contentTintColor = .white
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size), heightAnchor.constraint(equalToConstant: size),
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor), glyph.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { nil }
    func configure(mode: GlowAppearance) {
        let symbol: String
        switch mode {
        case .bottom: symbol = "dock.rectangle"; color = .systemPurple
        case .aroundNotch: symbol = "macbook"; color = .systemBlue
        case .aroundInput: symbol = "rectangle.and.pencil.and.ellipsis"; color = .systemPink
        case .bezel: symbol = "sidebar.right"; color = .systemGray
        case .liquidGlass: symbol = "waveform"; color = .systemCyan
        case .withinInput: symbol = "rectangle.inset.filled"; color = .systemPink
        }
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.width * 0.23, yRadius: bounds.width * 0.23)
        NSGradient(starting: color.blended(withFraction: 0.12, of: .white)!, ending: color)?.draw(in: path, angle: -90)
        NSColor.white.withAlphaComponent(0.18).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}


private final class AppearanceSidebarCell: NSTableCellView {
    private let glyph = NSImageView()
    let selectionPlate = SettingsSidebarSelectionPlate()
    private var selected = false
    private var hovered = false
    override var allowsVibrancy: Bool { false }
    override var backgroundStyle: NSView.BackgroundStyle { didSet { updateColors() } }

    init(group: Bool) {
        super.init(frame: .zero)
        selectionPlate.translatesAutoresizingMaskIntoConstraints = false
        selectionPlate.setAccessibilityElement(false)
        addSubview(selectionPlate)
        glyph.translatesAutoresizingMaskIntoConstraints = false
        glyph.imageScaling = .scaleProportionallyUpOrDown
        glyph.setAccessibilityElement(false)
        addSubview(glyph)
        NSLayoutConstraint.activate([
            selectionPlate.centerXAnchor.constraint(equalTo: centerXAnchor),
            selectionPlate.centerYAnchor.constraint(equalTo: centerYAnchor),
            selectionPlate.widthAnchor.constraint(equalToConstant: 44),
            selectionPlate.heightAnchor.constraint(equalToConstant: 44),
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 24), glyph.heightAnchor.constraint(equalToConstant: 24)
        ])
        updateColors()
    }
    required init?(coder: NSCoder) { nil }
    func configure(title: String, icon: SidebarGlyph?, selected: Bool) {
        glyph.image = icon?.image
        toolTip = title
        setAccessibilityLabel(title)
        hovered = false
        setSelected(selected)
    }
    func setSelected(_ value: Bool) { selected = value; updateColors() }
    func setHovered(_ value: Bool) { hovered = value; updateColors() }
    private func updateColors() {
        glyph.contentTintColor = selected ? .black : .labelColor
        selectionPlate.alphaValue = selected ? 1 : 0.10
        selectionPlate.isHidden = !selected && !hovered
    }
}

final class SettingsSidebarRow: NSTableRowView {
    var isHeading = false
    private(set) var isHovered = false
    var tileBounds: NSRect {
        let side = max(0, min(bounds.width - 6, bounds.height - 4))
        return NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
    }
    private var hoverArea: NSTrackingArea?
    override var allowsVibrancy: Bool { false }
    override var isSelected: Bool {
        didSet {
            subviews.compactMap { $0 as? AppearanceSidebarCell }.forEach { $0.setSelected(isSelected) }
            setHover(false)
        }
    }
    func setHover(_ active: Bool) {
        let next = active && !isSelected && !isHeading
        guard next != isHovered else { return }
        isHovered = next
        subviews.compactMap { $0 as? AppearanceSidebarCell }.forEach { $0.setHovered(next) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { setHover(true) }
    override func mouseExited(with event: NSEvent) { setHover(false) }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); setHover(false) }
    override func drawSelection(in dirtyRect: NSRect) {}
}

final class SettingsSidebarSelectionPlate: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 10
    }
    required init?(coder: NSCoder) { nil }
    override var allowsVibrancy: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class SettingsSidebarBackground: NSView {
    var onAppearanceChange: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

@MainActor final class SettingsSidebarBackdrop: NSView {
    let wallpaperLayer = CALayer()
    var pageBackgroundColor: NSColor? {
        didSet { needsDisplay = true }
    }
    weak var previewViewport: NSView? {
        didSet {
            guard previewViewport !== oldValue else { return }
            let center = NotificationCenter.default
            for name in [NSView.frameDidChangeNotification, NSView.boundsDidChangeNotification] {
                center.removeObserver(self, name: name, object: oldValue)
            }
            if let previewViewport {
                // The rail has a fixed width, so its own layout does not reliably
                // run after the adjacent preview changes size during live resize.
                previewViewport.postsFrameChangedNotifications = true
                previewViewport.postsBoundsChangedNotifications = true
                for name in [NSView.frameDidChangeNotification, NSView.boundsDidChangeNotification] {
                    center.addObserver(self, selector: #selector(previewGeometryChanged(_:)),
                                       name: name, object: previewViewport)
                }
            }
            refreshGeometry()
        }
    }
    private(set) var mode: GlowAppearance?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        wallpaperLayer.isHidden = true
        wallpaperLayer.contentsGravity = .resize
        layer?.addSublayer(wallpaperLayer)
    }
    required init?(coder: NSCoder) { nil }
    deinit { NotificationCenter.default.removeObserver(self) }

    override func draw(_ dirtyRect: NSRect) {
        guard mode == nil, let pageBackgroundColor else { return }
        pageBackgroundColor.setFill()
        dirtyRect.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    @objc private func previewGeometryChanged(_ notification: Notification) {
        refreshGeometry()
    }

    func setWallpaper(_ image: CGImage?, mode: GlowAppearance?) {
        self.mode = mode
        needsDisplay = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wallpaperLayer.contents = image
        wallpaperLayer.isHidden = image == nil
        if mode == nil { layer?.backgroundColor = nil }
        layoutWallpaper()
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        refreshGeometry()
    }

    func refreshGeometry() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutWallpaper()
        CATransaction.commit()
    }

    private func layoutWallpaper() {
        guard let mode else { return }
        let viewport = previewViewport.map { convert($0.bounds, from: $0) }
            ?? NSRect(x: bounds.maxX, y: 0, width: 676, height: bounds.height)
        guard viewport.width > 0, viewport.height > 0 else { return }
        let scene = AppearancePreviewScene.size(for: mode)
        let placement = AppearancePreviewScene.placement(for: mode, viewport: viewport.size,
            topInset: previewViewport.map(AppearancePreviewScene.topInset(of:)) ?? 0)
        let scale = placement.scale
        let size = NSSize(width: scene.width * scale, height: scene.height * scale)
        let leading = AppearancePreviewScene.sidebarLeadingWidth * scale
        wallpaperLayer.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let background = mode.followsInput ? AppearancePreviewScene.inputBackgroundColor.cgColor : nil
        if layer?.backgroundColor != background { layer?.backgroundColor = background }
        let frame = NSRect(x: viewport.minX + placement.origin.x - leading,
                           y: viewport.maxY - placement.origin.y - size.height,
                           width: size.width + leading, height: size.height)
        if wallpaperLayer.frame != frame { wallpaperLayer.frame = frame }
    }
}

final class SettingsDashboardButton: NSButton {
    var isDashboardSelected = false {
        didSet { isHovered = false; state = isDashboardSelected ? .on : .off; updateColors() }
    }
    private(set) var isHovered = false
    private var hoverArea: NSTrackingArea?
    override init(frame: NSRect) {
        super.init(frame: frame)
        cell = SettingsDashboardButtonCell(textCell: "")
        (cell as? NSButtonCell)?.highlightsBy = []
        (cell as? NSButtonCell)?.showsStateBy = []
        wantsLayer = true
        layer?.cornerRadius = 10
        updateColors()
    }
    required init?(coder: NSCoder) { nil }
    func setHover(_ active: Bool) { isHovered = active && !isDashboardSelected; updateColors() }
    private func updateColors() {
        contentTintColor = isDashboardSelected ? .black : .labelColor
        layer?.backgroundColor = NSColor.white.withAlphaComponent(isDashboardSelected ? 1 : isHovered ? 0.10 : 0).cgColor
        needsDisplay = true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { setHover(true) }
    override func mouseExited(with event: NSEvent) { setHover(false) }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); setHover(false) }
}

private final class SettingsDashboardButtonCell: NSButtonCell {
    override func imageRect(forBounds rect: NSRect) -> NSRect {
        NSRect(x: rect.midX - 19, y: rect.midY - 13, width: 38, height: 26)
    }
}
