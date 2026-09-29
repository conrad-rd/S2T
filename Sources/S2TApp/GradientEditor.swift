import AppKit
import S2TCore

@MainActor final class GradientEditor: NSStackView {
    let resetButton = NSButton(title: "Reset", target: nil, action: nil)
    let addButton = NSButton()
    let removeButton = NSButton()
    let evenButton = NSButton(title: "Space evenly", target: nil, action: nil)
    let track = GradientTrack(frame: .zero)
    private(set) var gradient = GlowGradient()
    private(set) var selectedID: UUID?
    private(set) var colorEditingID: UUID?
    var presentsColorPanel = true
    private var colorPanel: NSColorPanel?
    private var mode: GlowAppearance?
    private var clickMonitor: Any?
    var onChange: ((GlowGradient) -> Void)?

    init() {
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("appearance.gradient")
        orientation = .vertical
        alignment = .leading
        spacing = 10
        let title = NSTextField(labelWithString: "Gradient")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        resetButton.target = self
        resetButton.action = #selector(resetGradient)
        resetButton.identifier = NSUserInterfaceItemIdentifier("appearance.gradient.reset")
        resetButton.setAccessibilityLabel("Reset gradient")
        resetButton.toolTip = "Restore the app's default gradient for this appearance"
        append(title)
        track.heightAnchor.constraint(equalToConstant: 84).isActive = true
        append(track)
        track.onSelect = { [weak self] id in self?.selectStop(id) }
        track.onMove = { [weak self] id, position in
            guard let self else { return }
            self.gradient.moveStop(id: id, to: position)
            self.changed()
        }
        track.onEditColor = { [weak self] id in self?.openColorPicker(id) }
        track.onAdd = { [weak self] position in self?.addColor(at: position) }
        track.onRemove = { [weak self] id in self?.removeColor(id) }
        track.onRestore = { [weak self] gradient in self?.gradient = gradient; self?.changed() }
        for (button, label, action) in [
            (removeButton, "Remove point", #selector(removeColorButton)),
            (addButton, "Add point", #selector(addColorButton))
        ] {
            button.title = label
            button.setAccessibilityLabel(label)
            button.target = self
            button.action = action
        }
        removeButton.toolTip = "Remove the selected point"
        addButton.toolTip = "Add a point beside the selected point"
        evenButton.target = self
        evenButton.action = #selector(spaceEvenly)
        for button in [removeButton, addButton, evenButton, resetButton] {
            if #available(macOS 26, *) {
                button.bezelStyle = .glass
                button.borderShape = .capsule
            } else {
                button.bezelStyle = .rounded
            }
            button.isBordered = true
            button.controlSize = .regular
            button.cell?.wraps = false
            button.cell?.isScrollable = false
            button.cell?.lineBreakMode = .byClipping
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        let tools = NSStackView(views: [removeButton, addButton, NSView(), evenButton, resetButton])
        tools.spacing = 4
        tools.alignment = .centerY
        append(tools)
        NotificationCenter.default.addObserver(self, selector: #selector(clearSelection),
            name: NSApplication.didResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(colorPanelWillClose(_:)),
            name: NSWindow.willCloseNotification, object: nil)
        refresh(gradient, mode: .bottom)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let clickMonitor { NSEvent.removeMonitor(clickMonitor) } }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        guard window != nil else { endColorEditing(); return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleMouseDown(event, in: event.window)
            return event
        }
    }

    func handleMouseDown(_ event: NSEvent, in clickedWindow: NSWindow?) {
        guard selectedID != nil else { return }
        if let colorPanel, clickedWindow === colorPanel { return }
        if clickedWindow === window, let content = window?.contentView {
            let point = content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
            if let hit = content.hitTest(point) {
                let selectionControls: [NSView] = track.handles.map { $0 as NSView } + [addButton, removeButton]
                if selectionControls.contains(where: { hit === $0 || hit.isDescendant(of: $0) }) { return }
            }
        }
        endColorEditing()
    }

    @objc private func clearSelection() { endColorEditing() }
    @objc private func colorPanelWillClose(_ notification: Notification) {
        if let panel = notification.object as? NSColorPanel, panel === colorPanel { endColorEditing() }
    }

    private func append(_ view: NSView) {
        addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }

    func refresh(_ value: GlowGradient, mode: GlowAppearance) {
        if self.mode != mode {
            endColorEditing()
            self.mode = mode
        }
        gradient = value
        if let selectedID, value.index(of: selectedID) == nil { endColorEditing() }
        track.refresh(value, selected: selectedID)
        removeButton.isEnabled = selectedID != nil && value.stops.count > 1
        evenButton.isEnabled = value.stops.count > 1
        resetButton.isEnabled = !value.isDefault
        if let id = colorEditingID, let index = value.index(of: id), let panel = colorPanel {
            let rgb = value.stops[index].color
            let color = NSColor(srgbRed: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1)
            if panel.color != color { panel.color = color }
        }
    }

    func selectStop(_ id: UUID) {
        guard gradient.index(of: id) != nil else { return }
        selectedID = id
        if colorEditingID != nil { colorEditingID = id }
        refresh(gradient, mode: mode ?? .bottom)
    }

    private func openColorPicker(_ id: UUID) {
        selectStop(id)
        colorEditingID = id
        guard presentsColorPanel, let index = gradient.index(of: id) else { return }
        let panel = NSColorPanel.shared
        colorPanel = panel
        panel.showsAlpha = false
        panel.isContinuous = true
        let rgb = gradient.stops[index].color
        panel.color = NSColor(srgbRed: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1)
        panel.setTarget(self)
        panel.setAction(#selector(changeColor(_:)))
        panel.orderFront(nil)
    }

    @objc private func changeColor(_ sender: NSColorPanel) { applyColor(sender.color) }
    func applyColor(_ picked: NSColor) {
        guard let id = colorEditingID, let color = picked.usingColorSpace(.sRGB) else { return }
        gradient.setColor(SIMD3(color.redComponent, color.greenComponent, color.blueComponent), id: id)
        changed()
    }

    func endColorEditing() {
        selectedID = nil
        colorEditingID = nil
        if let colorPanel {
            colorPanel.setTarget(nil)
            colorPanel.setAction(nil)
            colorPanel.orderOut(nil)
        }
        colorPanel = nil
        track.cancelDrag()
        track.refresh(gradient, selected: nil)
        removeButton.isEnabled = false
        if let responder = window?.firstResponder as? GradientStopHandle, responder.track === track {
            window?.makeFirstResponder(nil)
        }
    }
    private func changed() {
        refresh(gradient, mode: mode ?? .bottom)
        onChange?(gradient)
    }
    private func addColor(at position: Double? = nil) {
        track.cancelDrag()
        let id = gradient.addStop(at: position)
        selectedID = id
        changed()
        openColorPicker(id)
    }
    private func removeColor(_ id: UUID) {
        guard gradient.stops.count > 1, let index = gradient.index(of: id) else { return }
        endColorEditing()
        gradient.removeStop(id: id)
        selectedID = gradient.stops[min(index, gradient.stops.count - 1)].id
        changed()
        if let handle = track.handles.first(where: { $0.stopID == selectedID }) { window?.makeFirstResponder(handle) }
    }
    @objc private func addColorButton() {
        guard let selectedID, let index = gradient.index(of: selectedID) else { addColor(); return }
        let position = gradient.stops[index].position
        let neighbor: Double
        if position < 1 {
            neighbor = gradient.stops.first(where: { $0.position > position })?.position ?? 1
        } else {
            neighbor = gradient.stops.last(where: { $0.position < position })?.position ?? 0
        }
        addColor(at: (position + neighbor) / 2)
    }
    @objc private func removeColorButton() { if let selectedID { removeColor(selectedID) } }
    @objc private func spaceEvenly() { track.cancelDrag(); gradient.spaceEvenly(); changed() }
    @objc private func resetGradient() {
        endColorEditing()
        gradient = .init()
        changed()
    }
}
