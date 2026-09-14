import AppKit
import Combine
import SwiftUI
import S2TCore

enum AppearanceSection: Int, CaseIterable {
    case glow, edge, speech
    var title: String { ["Glow", "Edge", "Speech"][rawValue] }
    var controls: [AppearanceControl] {
        switch self {
        case .glow: return [.intensity, .gradientSpeed, .width, .backgroundBlur, .bodyOpacity, .softness, .falloff]
        case .edge: return [.edgeBlur, .edgeGlow, .edge, .edgeHeight, .edgeOpacity]
        case .speech: return [.minimum, .maximum]
        }
    }
}

enum AppearanceControl: String, CaseIterable {
    case intensity, gradientSpeed, width, backgroundBlur, bodyOpacity, softness, falloff, edge, edgeBlur, edgeGlow, edgeHeight, edgeOpacity, minimum, maximum
    var section: AppearanceSection { AppearanceSection.allCases.first { $0.controls.contains(self) }! }
    var id: String { "glow." + rawValue }
    var title: String {
        switch self {
        case .gradientSpeed: return "Gradient speed"
        case .intensity: return "Intensity"
        case .width: return "Width"
        case .backgroundBlur: return "Background blur"
        case .bodyOpacity: return "Main glow opacity"
        case .softness: return "Glow softness"
        case .falloff: return "Falloff"
        case .edge: return "Edge brightness"
        case .edgeBlur: return "Edge blur"
        case .edgeGlow: return "Edge glow"
        case .edgeHeight: return "Edge height"
        case .edgeOpacity: return "Edge opacity"
        case .minimum: return "Quiet amount"
        case .maximum: return "Loud amount"
        }
    }
    var rowTitle: String {
        switch self {
        case .edge: return "Brightness"
        case .edgeBlur: return "Blur"
        case .edgeGlow: return "Glow"
        case .edgeHeight: return "Height"
        case .edgeOpacity: return "Opacity"
        default: return title
        }
    }
    var symbol: String {
        switch self {
        case .gradientSpeed: return "arrow.triangle.2.circlepath"
        case .intensity: return "sun.max"
        case .width: return "arrow.left.and.right"
        case .backgroundBlur: return "square.3.layers.3d"
        case .bodyOpacity: return "circle.lefthalf.filled"
        case .softness: return "drop.halffull"
        case .falloff: return "circle.dotted"
        case .edge: return "circle.lefthalf.filled"
        case .edgeBlur: return "drop.halffull"
        case .edgeGlow: return "sparkles"
        case .edgeHeight: return "arrow.up.and.down"
        case .edgeOpacity: return "circle.dotted"
        case .minimum: return "speaker.wave.1"
        case .maximum: return "speaker.wave.3"
        }
    }
    var range: ClosedRange<Double> {
        switch self {
        case .gradientSpeed: return 0...1
        case .intensity: return 0.25...1.3
        case .width: return 0.25...1
        case .softness, .edgeBlur: return 0...12
        case .falloff: return 0.5...2
        case .edgeHeight: return 0...1
        case .edgeOpacity, .bodyOpacity: return 0...1
        case .maximum: return 0...5
        default: return 0...2
        }
    }
    var help: String {
        switch self {
        case .gradientSpeed: return "Color cycles per second. Zero stops movement. Applies to all glow modes. Reduce Motion keeps colors still."
        case .backgroundBlur: return "Softens the background through the native progressive blur. Zero keeps it sharp."
        case .bodyOpacity: return "Changes the main glow's transparency without changing the light sweep or background blur."
        case .softness: return "Softens the colored glow while keeping the edge crisp."
        case .falloff: return "Higher values fade the glow faster. Lower values leave a longer tail."
        case .edge: return "Changes the light level of the rim and its halo."
        case .edgeBlur: return "Softens only the bright rim."
        case .edgeGlow: return "Adds a soft colored halo around the rim."
        case .edgeHeight: return "Scales the rim height from zero to its full height. Zero hides the rim and its halo."
        case .edgeOpacity: return "Changes the visibility of the rim and its halo together."
        case .minimum: return "Glow amount while listening quietly."
        case .maximum: return "Glow amount at the loudest speech level."
        default: return title
        }
    }
    func isVisible(for mode: GlowAppearance) -> Bool {
        mode != .bezel && (self != .width || mode == .bottom || mode == .aroundNotch)
    }
    func formatted(_ value: Double) -> String {
        if self == .gradientSpeed { return value == 0 ? "0 · Off" : String(format: "%.2f cycles/s", value) }
        return self == .softness || self == .edgeBlur ? String(format: "%.1f pt", value) : self == .falloff ? String(format: "%.2f×", value) : "\(Int((value * 100).rounded()))%"
    }
    @MainActor func value(in state: AppState) -> Double {
        switch self {
        case .gradientSpeed: return state.glowTuning.gradientSpeed
        case .intensity: return state.glowStrength
        case .width: return state.glowWidth
        case .backgroundBlur: return state.glowTuning.backgroundBlur
        case .bodyOpacity: return state.glowTuning.bodyOpacity
        case .softness: return state.glowTuning.softness
        case .falloff: return state.glowTuning.falloff
        case .edge: return state.glowTuning.edgeBrightness
        case .edgeBlur: return state.glowTuning.edgeBlur
        case .edgeGlow: return state.glowTuning.edgeGlow
        case .edgeHeight: return state.glowTuning.edgeHeight
        case .edgeOpacity: return state.glowTuning.edgeOpacity
        case .minimum: return state.glowMinimum
        case .maximum: return state.glowMaximum
        }
    }
    @MainActor func set(_ raw: Double, in state: AppState) {
        let value = min(range.upperBound, max(range.lowerBound, raw))
        switch self {
        case .gradientSpeed: state.glowTuning.gradientSpeed = value
        case .intensity: state.glowStrength = value
        case .width: state.glowWidth = value
        case .backgroundBlur: state.glowTuning.backgroundBlur = value
        case .bodyOpacity: state.glowTuning.bodyOpacity = value
        case .softness: state.glowTuning.softness = value
        case .falloff: state.glowTuning.falloff = value
        case .edge: state.glowTuning.edgeBrightness = value
        case .edgeBlur: state.glowTuning.edgeBlur = value
        case .edgeGlow: state.glowTuning.edgeGlow = value
        case .edgeHeight: state.glowTuning.edgeHeight = value
        case .edgeOpacity: state.glowTuning.edgeOpacity = value
        case .minimum:
            state.glowMinimum = value
            if value > state.glowMaximum { state.glowMaximum = value }
        case .maximum:
            state.glowMaximum = value
            if value < state.glowMinimum { state.glowMinimum = value }
        }
    }
}

@MainActor final class AppearanceWindowController: NSObject, NSWindowDelegate {
    let state: AppState
    let preview = AppearancePreviewActivity()
    private(set) var window: NSWindow?
    private(set) var sliders: [AppearanceControl: NSSlider] = [:]
    private var values: [AppearanceControl: NSTextField] = [:]
    private var rows: [AppearanceControl: NSView] = [:]
    private(set) var sidebar = AppearanceSidebarController()
    private(set) var splitController = NSSplitViewController()
    private(set) var previewHost: NSView?
    private(set) var sidePicker = BezelPlacementPicker(frame: .zero)
    let phasePicker = AppearancePhasePicker(frame: .zero)
    let sectionBar = AppearanceSectionBar(frame: .zero)
    private(set) var selectedSection = AppearanceSection.glow
    private var speechPreviewPhase = 1
    private var sectionCards: [AppearanceSection: NSView] = [:]
    private(set) var controlsScroll = NSScrollView()
    private(set) var controlsPanel: NSView!
    private var panelHeight: NSLayoutConstraint!
    private var panelWidth: NSLayoutConstraint!
    private var sideGroup = NSView()
    private var inputHelp = NSTextField(wrappingLabelWithString: "")
    private var reset = NSButton()
    private(set) lazy var modelsPane = ModelsPane(state: state)
    private(set) var showingModels = false
    private(set) var showingKeys = false
    private(set) lazy var apiKeysPane = APIKeysPane(state: state)
    private var appearanceDetail: NSView?
    private var subscription: AnyCancellable?
    private let presentsWindows: Bool

    init(state: AppState, presentsWindows: Bool = true) {
        self.state = state
        self.presentsWindows = presentsWindows && !state.isPreview
        super.init()
        subscription = state.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }
    }

    @discardableResult func prepare() -> NSWindow {
        if let window { refresh(); return window }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: true)
        window.title = "S2T Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.identifier = NSUserInterfaceItemIdentifier("s2t.appearance")
        window.isReleasedWhenClosed = false
        window.titlebarSeparatorStyle = .none
        window.delegate = self

        let detail = NSViewController()
        let content = AppearanceDetailView()
        detail.view = content
        appearanceDetail = content
        sidebar.onSelection = { [weak self] mode in
            guard let self else { return }
            self.setModelsVisible(false)
            self.state.glowAppearance = mode
            self.refresh()
            self.scrollControlsToTop()
        }
        sidebar.onAPIKeys = { [weak self] in self?.setSettingsPane("keys") }
        sidebar.onModels = { [weak self] in self?.setModelsVisible(true) }
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 208
        sidebarItem.maximumThickness = 208
        sidebarItem.canCollapse = false
        sidebarItem.allowsFullHeightLayout = true
        splitController.addSplitViewItem(sidebarItem)
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 572
        splitController.addSplitViewItem(detailItem)
        splitController.splitView.dividerStyle = .thin
        window.contentViewController = splitController
        window.setContentSize(NSSize(width: 780, height: 720))

        reset = NSButton(title: "Reset", target: self, action: #selector(resetGlow))
        reset.attributedTitle = NSAttributedString(string: "Reset", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 13, weight: .medium)
        ])
        if #available(macOS 26, *) {
            reset.bezelStyle = .glass
            reset.borderShape = .capsule
            reset.tintProminence = .primary
        } else {
            reset.bezelStyle = .rounded
        }
        reset.identifier = NSUserInterfaceItemIdentifier("appearance.reset")
        reset.bezelColor = .systemBlue
        reset.isBordered = true
        reset.contentTintColor = .white
        reset.toolTip = "Reset glow settings"
        reset.setAccessibilityLabel("Reset glow settings")
        let host = NSHostingView(rootView: AppearancePreview(state: state, activity: preview))
        host.identifier = NSUserInterfaceItemIdentifier("appearance.preview")
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        host.wantsLayer = true
        host.layer?.cornerRadius = 0
        host.layer?.masksToBounds = true
        content.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            host.topAnchor.constraint(equalTo: content.topAnchor),
            host.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        previewHost = host
        phasePicker.onSelection = { [weak self] phase in
            self?.preview.phase = phase
            self?.refresh()
        }
        let panelContent = NSView()
        controlsPanel = SettingsGlassBar.make(content: panelContent, cornerRadius: 36)
        controlsPanel.identifier = NSUserInterfaceItemIdentifier("appearance.controlsPanel")
        controlsPanel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(controlsPanel)
        panelHeight = controlsPanel.heightAnchor.constraint(equalToConstant: 392)
        panelWidth = controlsPanel.widthAnchor.constraint(equalToConstant: 476)
        NSLayoutConstraint.activate([
            controlsPanel.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            controlsPanel.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -24),
            panelWidth,
            panelHeight
        ])
        let previewBar = NSStackView(views: [phasePicker, NSView(), sectionBar])
        previewBar.distribution = .fill
        previewBar.spacing = 8
        previewBar.translatesAutoresizingMaskIntoConstraints = false
        panelContent.addSubview(previewBar)
        NSLayoutConstraint.activate([
            previewBar.leadingAnchor.constraint(equalTo: panelContent.leadingAnchor, constant: 12),
            previewBar.trailingAnchor.constraint(equalTo: panelContent.trailingAnchor, constant: -12),
            previewBar.topAnchor.constraint(equalTo: panelContent.topAnchor, constant: 12),
            previewBar.heightAnchor.constraint(equalToConstant: 48)
        ])
        sectionBar.onSelection = { [weak self] section in self?.selectSection(section) }

        controlsScroll.drawsBackground = false
        controlsScroll.hasVerticalScroller = true
        controlsScroll.autohidesScrollers = true
        controlsScroll.translatesAutoresizingMaskIntoConstraints = false
        panelContent.addSubview(controlsScroll)
        reset.translatesAutoresizingMaskIntoConstraints = false
        reset.controlSize = .regular
        panelContent.addSubview(reset)
        NSLayoutConstraint.activate([
            controlsScroll.leadingAnchor.constraint(equalTo: panelContent.leadingAnchor, constant: 12),
            controlsScroll.trailingAnchor.constraint(equalTo: panelContent.trailingAnchor, constant: -12),
            controlsScroll.topAnchor.constraint(equalTo: previewBar.bottomAnchor, constant: 8),
            controlsScroll.bottomAnchor.constraint(equalTo: reset.topAnchor, constant: -8),
            reset.trailingAnchor.constraint(equalTo: panelContent.trailingAnchor, constant: -20),
            reset.bottomAnchor.constraint(equalTo: panelContent.bottomAnchor, constant: -20),
            reset.widthAnchor.constraint(equalToConstant: 86),
            reset.heightAnchor.constraint(equalToConstant: 32)
        ])
        let document = AppearanceFlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        controlsScroll.documentView = document
        document.widthAnchor.constraint(equalTo: controlsScroll.contentView.widthAnchor).isActive = true
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -4)
        ])
        func append(_ view: NSView) {
            view.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        for control in AppearanceControl.allCases {
            let icon = NSImageView(image: NSImage(systemSymbolName: control.symbol, accessibilityDescription: nil)!)
            icon.symbolConfiguration = .init(pointSize: 12, weight: .regular)
            icon.contentTintColor = .secondaryLabelColor
            icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
            let label = NSTextField(labelWithString: control.rowTitle)
            label.font = .systemFont(ofSize: 13)
            label.widthAnchor.constraint(equalToConstant: 110).isActive = true
            let slider = NSSlider(value: control.value(in: state), minValue: control.range.lowerBound,
                maxValue: control.range.upperBound, target: self, action: #selector(changeSlider(_:)))
            slider.identifier = NSUserInterfaceItemIdentifier(control.id)
            slider.isContinuous = true
            slider.controlSize = .small
            slider.setAccessibilityLabel(control.title)
            slider.toolTip = control.help
            let value = NSTextField(labelWithString: "")
            value.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            value.textColor = .secondaryLabelColor
            value.alignment = .right
            value.widthAnchor.constraint(equalToConstant: control == .gradientSpeed ? 94 : 42).isActive = true
            let row = AppearanceSettingRow(views: [icon, label, slider, value])
            row.alignment = .centerY
            row.spacing = 8
            row.heightAnchor.constraint(equalToConstant: 38).isActive = true
            sliders[control] = slider; values[control] = value; rows[control] = row
        }
        for section in AppearanceSection.allCases {
            let group = card(section.controls.compactMap { rows[$0] })
            group.identifier = NSUserInterfaceItemIdentifier("appearance.section.\(section.title.lowercased())")
            sectionCards[section] = group
            append(group)
        }
        sidePicker.target = self
        sidePicker.action = #selector(changeSide(_:))
        sidePicker.setAccessibilityLabel("Bezel placement")
        let placement = NSStackView(views: [sectionLabel("Placement", symbol: "sidebar.right"), NSView(), sidePicker])
        placement.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let dragHint = NSTextField(labelWithString: "Drag the Bezel to either edge and move it up or down.")
        dragHint.font = .systemFont(ofSize: 11)
        dragHint.textColor = .secondaryLabelColor
        sideGroup = card([placement, dragHint])
        append(sideGroup)
        inputHelp.font = .systemFont(ofSize: 11)
        inputHelp.textColor = .secondaryLabelColor
        inputHelp.maximumNumberOfLines = 2
        append(inputHelp)
        self.window = window
        if presentsWindows {
            if !window.setFrameUsingName("S2TSettingsHierarchyWindow") { window.center() }
            window.setContentSize(NSSize(width: 780, height: 720))
            window.setFrameAutosaveName("S2TSettingsHierarchyWindow")
        }
        refresh()
        return window
    }

    private func sectionLabel(_ title: String, symbol: String) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        icon.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        let row = NSStackView(views: [icon, label])
        row.spacing = 7
        return row
    }

    private func vertical(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }

    private func card(_ rows: [NSView]) -> NSView {
        let card = NSView()
        let stack = vertical(rows)
        stack.spacing = 0
        for row in rows.dropLast() { (row as? AppearanceSettingRow)?.showsSeparator = true }
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -5)
        ])
        return card
    }

    func show() {
        let window = prepare()
        preview.running = !showingModels && !showingKeys
        guard presentsWindows else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func showModels() {
        _ = prepare()
        sidebar.selectModels()
        setModelsVisible(true)
        show()
    }

    func showAPIKeys() {
        _ = prepare()
        sidebar.table.selectRowIndexes(IndexSet(integer: sidebar.keysRow), byExtendingSelection: false)
        setSettingsPane("keys")
        show()
    }

    func setModelsVisible(_ visible: Bool) { setSettingsPane(visible ? "models" : nil) }

    private func setSettingsPane(_ pane: String?) {
        guard let content = appearanceDetail,
              showingModels != (pane == "models") || showingKeys != (pane == "keys") else { return }
        showingModels = pane == "models"
        showingKeys = pane == "keys"
        let selected: NSView?
        if showingModels { selected = modelsPane.view }
        else if showingKeys { selected = apiKeysPane.view }
        else { selected = nil }
        if let selected {
            preview.stop()
            if selected.superview == nil {
                selected.translatesAutoresizingMaskIntoConstraints = false
                content.addSubview(selected)
                NSLayoutConstraint.activate([
                    selected.leadingAnchor.constraint(equalTo: content.leadingAnchor), selected.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                    selected.topAnchor.constraint(equalTo: content.topAnchor), selected.bottomAnchor.constraint(equalTo: content.bottomAnchor)
                ])
            }
            if showingModels { modelsPane.rebuild(); modelsPane.loadCatalog() }
            else { apiKeysPane.refresh() }
        } else { preview.running = window?.isVisible == true }
        for child in content.subviews {
            if let selected { child.isHidden = child !== selected }
            else { child.isHidden = child === modelsPane.view || child === apiKeysPane.view }
        }
    }

    func windowWillClose(_ notification: Notification) { preview.stop() }

    func selectSection(_ section: AppearanceSection) {
        if section != selectedSection {
            if selectedSection == .speech { speechPreviewPhase = preview.phase }
            selectedSection = section
            preview.phase = section == .speech ? speechPreviewPhase : 0
        }
        refresh()
        scrollControlsToTop()
    }

    private func scrollControlsToTop() {
        controlsScroll.contentView.scroll(to: .zero)
        controlsScroll.reflectScrolledClipView(controlsScroll.contentView)
    }

    func reveal(_ control: AppearanceControl) {
        selectSection(control.section)
        guard let row = rows[control] else { return }
        window?.contentView?.layoutSubtreeIfNeeded()
        row.scrollToVisible(row.bounds.insetBy(dx: 0, dy: -8))
    }

    func refresh() {
        guard let window else { return }
        if !showingModels && !showingKeys { sidebar.select(state.glowAppearance) }
        sidePicker.selectedSegment = state.bezelSide == .left ? 0 : 1
        window.appearance = state.menuAppearance == "system" ? nil : NSAppearance(named: state.menuAppearance == "dark" ? .darkAqua : .aqua)
        for control in AppearanceControl.allCases {
            sliders[control]?.doubleValue = control.value(in: state)
            values[control]?.stringValue = control.formatted(control.value(in: state))
            rows[control]?.isHidden = !control.isVisible(for: state.glowAppearance)
        }
        let bezel = state.glowAppearance == .bezel
        controlsPanel.isHidden = bezel || showingModels || showingKeys
        panelHeight.constant = bezel ? 200 : 392
        panelWidth.constant = bezel ? 444 : 476
        sideGroup.isHidden = !bezel
        sectionBar.isHidden = bezel || showingModels || showingKeys
        sectionBar.select(selectedSection)
        for (section, card) in sectionCards { card.isHidden = bezel || section != selectedSection }
        reset.isHidden = bezel
        inputHelp.stringValue = state.inputOutlineNotice ?? "Uses Bottom when a focused input isn't available."
        inputHelp.isHidden = state.glowAppearance != .aroundInput || state.inputOutlineNotice == nil
        phasePicker.select(preview.phase, bezel: bezel)
        window.contentView?.layoutSubtreeIfNeeded()
    }

    @objc private func changeSlider(_ sender: NSSlider) {
        guard let control = AppearanceControl.allCases.first(where: { $0.id == sender.identifier?.rawValue }) else { return }
        control.set(sender.doubleValue, in: state)
        refresh()
    }
    @objc private func changeSide(_ sender: BezelPlacementPicker) {
        state.bezelSide = sender.selectedSegment == 0 ? .left : .right
        refresh()
    }
    @objc private func resetGlow() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Reset glow settings?"
        alert.informativeText = "Restores glow, edge and speech response adjustments for all three glow appearances."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.restoreGlowDefaults()
        }
    }
    private func restoreGlowDefaults() {
        state.glowStrength = 0.8; state.glowWidth = 1
        state.glowMinimum = 0.3; state.glowMaximum = 2
        state.glowTuning = .init()
        refresh()
    }
}

private final class AppearanceDetailView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

private final class AppearanceFlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class AppearanceCardView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        NSColor.labelColor.withAlphaComponent(0.055).setFill()
        path.fill()
    }
}

private final class AppearanceSettingRow: NSStackView {
    var showsSeparator = false
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsSeparator else { return }
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(rect: NSRect(x: 24, y: isFlipped ? bounds.height - 0.5 : 0, width: bounds.width - 24, height: 0.5)).fill()
    }
}
