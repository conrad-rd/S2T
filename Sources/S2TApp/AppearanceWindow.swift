import AppKit
import Combine
import SwiftUI
import S2TCore

enum AppearanceSection: Int, CaseIterable {
    case glow, edge, speech, gradient
    var title: String { ["Glow", "Edge", "Speech", "Gradient"][rawValue] }
    var controls: [AppearanceControl] {
        switch self {
        case .glow: return [.intensity, .width, .backgroundBlur, .bodyOpacity, .softness, .falloff, .inputMinimumSize, .inputMaximumSize]
        case .edge: return [.edgeBlur, .edgeGlow, .edge, .edgeHeight, .edgeOpacity]
        case .speech: return [.minimum, .maximum]
        case .gradient: return [.gradientSpeed]
        }
    }
}

enum AppearanceControl: String, CaseIterable {
    case inputMinimumSize, inputMaximumSize, intensity, gradientSpeed, width, backgroundBlur, bodyOpacity, softness, falloff, edge, edgeBlur, edgeGlow, edgeHeight, edgeOpacity, minimum, maximum
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
        case .inputMinimumSize: return "Minimum size"
        case .inputMaximumSize: return "Maximum size"
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
        case .inputMinimumSize, .inputMaximumSize: return "arrow.up.and.down"
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
        case .inputMinimumSize, .inputMaximumSize: return 0.5...2
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
        case .inputMinimumSize: return "Glow size for small text boxes. Keeps a visible tail. Preview shows the maximum."
        case .inputMaximumSize: return "Glow size for large text boxes. Preview always shows this size."
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
        if self == .inputMinimumSize || self == .inputMaximumSize { return mode == .withinInput }
        return mode != .bezel && mode != .liquidGlass && (self != .width || mode == .bottom || mode == .aroundNotch)
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
        case .inputMinimumSize: return state.glowTuning.inputMinimumSize
        case .inputMaximumSize: return state.glowTuning.inputMaximumSize
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
        case .inputMinimumSize:
            state.glowTuning.inputMinimumSize = value
            state.glowTuning.inputMaximumSize = max(value, state.glowTuning.inputMaximumSize)
        case .inputMaximumSize:
            state.glowTuning.inputMaximumSize = value
            state.glowTuning.inputMinimumSize = min(value, state.glowTuning.inputMinimumSize)
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

/// A single selection drives navigation; pages keep their editors alive while hidden.
private enum SettingsDestination: String {
    case appearance, dashboard, dictation, models, keys, writing, meetings, recent
}

@MainActor final class AppearanceWindowController: NSObject, NSWindowDelegate {
    static let contentSize = NSSize(width: 780, height: 720)
    let state: AppState
    let preview: AppearancePreviewActivity
    let modeBar = AppearanceModeBar()
    let pageToolbar = SettingsPageToolbar()
    private(set) var window: NSWindow?
    private(set) var sliders: [AppearanceControl: NSSlider] = [:]
    private var values: [AppearanceControl: NSTextField] = [:]
    private var rows: [AppearanceControl: NSView] = [:]
    private(set) var sidebar = AppearanceSidebarController()
    private(set) var splitController = NSSplitViewController()
    private(set) var windowSurface: SettingsWindowSurface!
    private(set) var previewHost: NSView?
    private(set) var sidePicker = BezelPlacementPicker(frame: .zero)
    let sectionBar = AppearanceSectionBar(frame: .zero)
    private let fixedPreviewHint = NSTextField(labelWithString: "Drag the indicator to an edge")
    private(set) var selectedSection = AppearanceSection.glow
    private var sectionCards: [AppearanceSection: NSView] = [:]
    private(set) var controlsScroll = NSScrollView()
    private(set) var controlsPanel: NSView!
    private(set) var adjustments = NSView()
    private var panelHeight: NSLayoutConstraint!
    private(set) var classicBarAvoidance: ClassicBarAvoidance?
    private var sideGroup = NSView()
    let gradientEditor = GradientEditor()
    private var gradientCard = NSView()
    private var inputHelp = NSTextField(wrappingLabelWithString: "")
    private(set) var inputSizeToggle = NSSwitch()
    private(set) var inputSizeRow: NSStackView = AppearanceSettingRow()
    private var reset = NSButton()
    private(set) lazy var modelsPane: ModelsPane = {
        let pane = ModelsPane(state: state)
        pane.openAPIKeys = { [weak self] account in
            self?.showAPIKeys()
            self?.apiKeysPane.editing.beginEditing(account)
        }
        return pane
    }()
    var showingRecentRecordings: Bool { destination == .recent }
    let recentFilter = RecentRecordingsFilter()
    private(set) lazy var recentRecordingsPane: NSHostingView<RecentRecordingsView> = {
        let host = NSHostingView(rootView: RecentRecordingsView(history: state.recentRecordings,
            filter: recentFilter, copy: { [weak state] text in state?.copyText(text) }))
        host.sizingOptions = []
        return host
    }()
    var showingDashboard: Bool { destination == .dashboard }
    private(set) lazy var dashboardPane = DashboardPane(ledger: state.localUsage, state: state)
    var showingModels: Bool { destination == .models }
    var showingKeys: Bool { destination == .keys }
    var showingMeetings: Bool { destination == .meetings }
    private(set) lazy var meetingsPane = MeetingsPane(state: state)
    var showingWriting: Bool { destination == .writing }
    private(set) lazy var writingPane = WritingPane(state: state)
    private(set) lazy var apiKeysPane = APIKeysPane(state: state)
    var showingDictation: Bool { destination == .dictation }
    private(set) lazy var dictationPane: NSHostingView<DictationSettingsPane> = {
        let host = NSHostingView(rootView: DictationSettingsPane(
            state: state, inputs: state.inputs, navigation: dictationNavigation,
            openAPIKeys: { [weak self] in self?.showAPIKeys() },
            openRecent: { [weak self] in self?.showRecentRecordings() }))
        host.sizingOptions = []
        return host
    }()
    let dictationNavigation = DictationNavigation()
    private var destination = SettingsDestination.appearance
    private var appearanceDetail: NSView?
    private var subscription: AnyCancellable?
    private var modelsSubscription: AnyCancellable?
    private var meetingsSubscription: AnyCancellable?
    private var recentSubscription: AnyCancellable?
    private var dictationSubscription: AnyCancellable?
    private let presentsWindows: Bool
    private var refreshScheduled = false
    private var refreshing = false
    private var refreshedGradient: GlowGradient?
    private var refreshedGradientMode: GlowAppearance?
    private struct LayoutState: Equatable {
        let mode: GlowAppearance
        let section: AppearanceSection
        let destination: SettingsDestination
        let theme: String
        let side: BezelSide
        let inputSize: Bool
        let notice: String?
    }
    private var refreshedLayout: LayoutState?

    init(state: AppState, presentsWindows: Bool = true) {
        self.state = state
        self.preview = AppearancePreviewActivity(mode: state.glowAppearance)
        self.presentsWindows = presentsWindows && !state.isPreview
        super.init()
        subscription = state.objectWillChange.sink { [weak self] in
            guard let self, !self.refreshScheduled, self.window != nil,
                  !self.presentsWindows || self.window?.isVisible == true else { return }
            self.refreshScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.refreshScheduled = false
                self.refresh()
            }
        }
    }

    @discardableResult func prepare() -> NSWindow {
        if let window { refresh(); return window }
        let window = SettingsEditorWindow(contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: true)
        window.title = "Appearance"
        window.acceptsMouseMovedEvents = true
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.identifier = NSUserInterfaceItemIdentifier("s2t.appearance")
        window.isReleasedWhenClosed = false
        window.titlebarSeparatorStyle = .none
        window.delegate = self
        window.cancelFieldEditing = { [weak self] in
            guard let self, self.showingKeys else { return }
            self.apiKeysPane.editing.endEditing(commit: false)
        }
        window.contentMinSize = Self.contentSize
        window.collectionBehavior.insert(.fullScreenNone)

        let detail = NSViewController()
        let content = NSView()
        detail.view = content
        appearanceDetail = content
        sidebar.onAppearance = { [weak self] in
            guard let self else { return }
            self.setModelsVisible(false)
            self.refresh()
            self.scrollControlsToTop()
        }
        sidebar.onRecentRecordings = { [weak self] in self?.setSettingsPane(.recent) }
        sidebar.onDashboard = { [weak self] in self?.setSettingsPane(.dashboard) }
        sidebar.onAPIKeys = { [weak self] in self?.setSettingsPane(.keys) }
        sidebar.onModels = { [weak self] in self?.setModelsVisible(true) }
        sidebar.onWriting = { [weak self] in self?.setSettingsPane(.writing) }
        sidebar.onMeetings = { [weak self] in self?.setSettingsPane(.meetings) }
        sidebar.onDictation = { [weak self] in
            self?.dictationNavigation.page = nil
            self?.setSettingsPane(.dictation)
        }
        splitController.splitView = SettingsSplitView()
        splitController.splitView.isVertical = true
        // The inset rail supplies its own glass. Native sidebar behavior adds a
        // second full-height material and splits the window's titlebar background
        // at this boundary. A regular item keeps one continuous native titlebar.
        let sidebarItem = NSSplitViewItem(viewController: sidebar)
        sidebarItem.minimumThickness = AppearanceSidebarController.containerWidth
        sidebarItem.maximumThickness = AppearanceSidebarController.containerWidth
        sidebarItem.canCollapse = false
        sidebarItem.allowsFullHeightLayout = true
        splitController.addSplitViewItem(sidebarItem)
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 572
        detailItem.allowsFullHeightLayout = true
        splitController.addSplitViewItem(detailItem)
        splitController.splitView.dividerStyle = .thin
        windowSurface = SettingsWindowSurface(split: splitController)
        window.contentViewController = windowSurface
        pageToolbar.owner = self
        window.toolbar = pageToolbar.toolbar
        window.toolbarStyle = .unified
        windowSurface.alignTitlebar(in: window)
        modelsSubscription = modelsPane.navigation.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { [weak self] in self?.pageToolbar.refresh() }
        }
        meetingsSubscription = state.meetings.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { [weak self] in self?.pageToolbar.refresh() }
        }
        dictationSubscription = dictationNavigation.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { [weak self] in self?.pageToolbar.refresh() }
        }
        recentSubscription = state.recentRecordings.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { [weak self] in self?.pageToolbar.refresh() }
        }
        window.setContentSize(Self.contentSize)
        window.contentView?.layoutSubtreeIfNeeded()

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
        sidebar.backdrop.previewViewport = host
        let panelContent = NSView()
        controlsPanel = SettingsGlassBar.make(content: panelContent, cornerRadius: 30)
        controlsPanel.identifier = NSUserInterfaceItemIdentifier("appearance.controlsPanel")
        controlsPanel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(controlsPanel)
        panelHeight = controlsPanel.heightAnchor.constraint(equalToConstant: 340)
        let horizontal = controlsPanel.centerXAnchor.constraint(equalTo: host.centerXAnchor)
        let vertical = controlsPanel.topAnchor.constraint(equalTo: content.bottomAnchor, constant: -AppearancePreviewScene.controlsReserve)
        classicBarAvoidance = ClassicBarAvoidance(panel: controlsPanel, horizontal: horizontal, vertical: vertical, height: panelHeight)
        preview.onClassicPlacement = { [weak self] source, rect, side in
            guard let self, self.preview.mode.isClassic else { return }
            self.classicBarAvoidance?.update(obstacle: rect, in: source, side: side)
        }
        NSLayoutConstraint.activate([
            horizontal,
            vertical,
            controlsPanel.widthAnchor.constraint(equalToConstant: 500),
            panelHeight
        ])
        modeBar.onSelection = { [weak self] mode in self?.selectPreview(mode) }
        fixedPreviewHint.font = .systemFont(ofSize: 12)
        fixedPreviewHint.textColor = .secondaryLabelColor
        fixedPreviewHint.alignment = .right
        fixedPreviewHint.isHidden = true
        let previewBar = NSStackView(views: [modeBar, sectionBar, fixedPreviewHint])
        previewBar.orientation = .horizontal
        previewBar.alignment = .centerY
        previewBar.spacing = 59
        previewBar.translatesAutoresizingMaskIntoConstraints = false
        panelContent.addSubview(previewBar)
        adjustments.translatesAutoresizingMaskIntoConstraints = false
        panelContent.addSubview(adjustments)
        NSLayoutConstraint.activate([
            previewBar.leadingAnchor.constraint(equalTo: panelContent.leadingAnchor, constant: 9),
            previewBar.trailingAnchor.constraint(equalTo: panelContent.trailingAnchor, constant: -9),
            previewBar.topAnchor.constraint(equalTo: panelContent.topAnchor, constant: 9),
            previewBar.heightAnchor.constraint(equalToConstant: 42),
            modeBar.widthAnchor.constraint(equalToConstant: 228),
            modeBar.heightAnchor.constraint(equalToConstant: 42),
            modeBar.heightAnchor.constraint(equalToConstant: 42),
            fixedPreviewHint.widthAnchor.constraint(equalToConstant: 195),
            adjustments.leadingAnchor.constraint(equalTo: panelContent.leadingAnchor),
            adjustments.trailingAnchor.constraint(equalTo: panelContent.trailingAnchor),
            adjustments.topAnchor.constraint(equalTo: previewBar.bottomAnchor, constant: 8),
            adjustments.heightAnchor.constraint(equalToConstant: 281)
        ])
        sectionBar.onSelection = { [weak self] section in self?.selectSection(section) }

        controlsScroll.drawsBackground = false
        controlsScroll.hasVerticalScroller = true
        controlsScroll.autohidesScrollers = true
        controlsScroll.translatesAutoresizingMaskIntoConstraints = false
        adjustments.addSubview(controlsScroll)
        reset.translatesAutoresizingMaskIntoConstraints = false
        reset.controlSize = .regular
        adjustments.addSubview(reset)
        NSLayoutConstraint.activate([
            controlsScroll.leadingAnchor.constraint(equalTo: adjustments.leadingAnchor, constant: 12),
            controlsScroll.trailingAnchor.constraint(equalTo: adjustments.trailingAnchor, constant: -12),
            controlsScroll.topAnchor.constraint(equalTo: adjustments.topAnchor),
            controlsScroll.bottomAnchor.constraint(equalTo: reset.topAnchor, constant: -8),
            reset.trailingAnchor.constraint(equalTo: adjustments.trailingAnchor, constant: -20),
            reset.bottomAnchor.constraint(equalTo: adjustments.bottomAnchor, constant: -20),
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
        let sizeIcon = NSImageView(image: NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil)!)
        sizeIcon.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        sizeIcon.contentTintColor = .secondaryLabelColor
        sizeIcon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        let sizeLabel = NSTextField(labelWithString: "Fit glow to text box")
        sizeLabel.font = .systemFont(ofSize: 13)
        inputSizeToggle.controlSize = .regular
        inputSizeToggle.setAccessibilityLabel("Fit glow to text box")
        for view in [sizeIcon, sizeLabel, NSView(), inputSizeToggle] { inputSizeRow.addArrangedSubview(view) }
        inputSizeRow.alignment = .centerY
        inputSizeRow.spacing = 8
        inputSizeRow.heightAnchor.constraint(equalToConstant: 38).isActive = true
        for section in AppearanceSection.allCases {
            let group = card((section == .glow ? [inputSizeRow] : []) + section.controls.compactMap { rows[$0] })
            group.identifier = NSUserInterfaceItemIdentifier("appearance.section.\(section.title.lowercased())")
            sectionCards[section] = group
            append(group)
        }
        inputSizeToggle.target = self
        inputSizeToggle.action = #selector(changeInputSize)
        inputSizeToggle.toolTip = "Adjust glow falloff to the text box size. Preview shows the maximum."
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
        gradientEditor.presentsColorPanel = presentsWindows
        gradientCard = card([gradientEditor])
        append(gradientCard)
        gradientEditor.onChange = { [weak self] gradient in
            guard let self, self.preview.mode != .bezel && self.preview.mode != .liquidGlass else { return }
            self.state.glowTuning.gradients[self.preview.mode.rawValue] = gradient
        }
        self.window = window
        if presentsWindows {
            if !window.setFrameUsingName("S2TSettingsHierarchyWindow") { window.center() }
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
        let firstPresentation = window == nil
        let window = prepare()
        if firstPresentation {
            sidebar.table.selectRowIndexes(IndexSet(integer: sidebar.dictationRow), byExtendingSelection: false)
            setSettingsPane(.dictation)
        }
        preview.running = !showingOtherPane
        guard presentsWindows else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func showRecentRecordings() {
        _ = prepare()
        sidebar.table.selectRowIndexes(IndexSet(integer: sidebar.recentRecordingsRow), byExtendingSelection: false)
        setSettingsPane(.recent)
        show()
    }

    func showDashboard() {
        _ = prepare()
        sidebar.selectDashboard()
        setSettingsPane(.dashboard)
        show()
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
        setSettingsPane(.keys)
        show()
    }

    func showMeetings() {
        _ = prepare()
        sidebar.table.selectRowIndexes(IndexSet(integer: sidebar.meetingsRow), byExtendingSelection: false)
        setSettingsPane(.meetings)
        show()
    }

    func showWriting() {
        _ = prepare()
        sidebar.table.selectRowIndexes(IndexSet(integer: sidebar.writingRow), byExtendingSelection: false)
        setSettingsPane(.writing)
        show()
    }

    func showDictation() {
        _ = prepare()
        sidebar.table.selectRowIndexes(IndexSet(integer: sidebar.dictationRow), byExtendingSelection: false)
        setSettingsPane(.dictation)
        show()
    }

    /// Opens Dictation → Prompt mode, where the reason Prompt mode could not start is shown.
    func showPromptMode() {
        showDictation()
        dictationNavigation.page = .prompt
    }

    func setModelsVisible(_ visible: Bool) {
        if visible {
            _ = modelsPane.view
            modelsPane.navigation.showOverview()
        }
        setSettingsPane(visible ? .models : .appearance)
    }

    private func setSettingsPane(_ next: SettingsDestination) {
        guard let content = appearanceDetail, destination != next else { return }
        if showingKeys { apiKeysPane.editing.endEditing() }
        if showingWriting { writingPane.editing.cancel() }
        window?.makeFirstResponder(nil)
        destination = next
        sidebar.logo.isDashboardSelected = showingDashboard
        sidebar.pageBackgroundColor = showingDashboard ? DashboardPane.backgroundColor : nil
        window?.backgroundColor = sidebar.pageBackgroundColor ?? .windowBackgroundColor
        content.needsDisplay = true
        sidebar.updateBackground(next == .appearance ? preview.mode : nil)
        let toolbarPage: SettingsPageToolbar.Page = next == .dashboard ? .dashboard : next == .recent ? .recent : next == .keys ? .keys :
            next == .models ? .models : next == .meetings ? .meetings : next == .dictation ? .dictation : .appearance
        window?.title = next == .writing ? "Writing" : next == .dashboard ? "S2T" : toolbarPage.title
        pageToolbar.select(toolbarPage)
        // Home keeps an empty native toolbar so AppKit uses the same traffic-light
        // geometry as every settings page, while its background stays transparent.
        window?.toolbar = showingWriting ? writingPane.nativeToolbar.toolbar : pageToolbar.toolbar
        window?.titleVisibility = showingDashboard ? .hidden : .visible
        window?.titlebarSeparatorStyle = .none
        updateTitlebar()
        window?.toolbarStyle = .unified
        if showingWriting { writingPane.nativeToolbar.refresh() }
        let selected: NSView?
        if showingRecentRecordings { selected = recentRecordingsPane }
        else if showingDashboard { selected = dashboardPane.view }
        else if showingModels { selected = modelsPane.view }
        else if showingKeys { selected = apiKeysPane.view }
        else if showingWriting { selected = writingPane.view }
        else if showingMeetings { selected = meetingsPane.view }
        else if showingDictation { selected = dictationPane }
        else { selected = nil }
        if let selected {
            gradientEditor.endColorEditing()
            preview.stop()
            if selected.superview == nil {
                selected.translatesAutoresizingMaskIntoConstraints = false
                content.addSubview(selected)
                let pageTop = showingDashboard ? content.topAnchor
                    : (window?.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? content.safeAreaLayoutGuide.topAnchor
                NSLayoutConstraint.activate([
                    selected.leadingAnchor.constraint(equalTo: content.leadingAnchor), selected.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                    selected.topAnchor.constraint(equalTo: pageTop),
                    selected.bottomAnchor.constraint(equalTo: content.bottomAnchor)
                ])
            }
            if showingDashboard { Task { await dashboardPane.refresh() } }
            else if showingModels { modelsPane.refreshForPresentation() }
            else if showingKeys { apiKeysPane.refresh() }
            else if showingWriting { writingPane.editing.refresh() }
        } else { preview.running = window?.isVisible == true }
        for child in content.subviews {
            if let selected { child.isHidden = child !== selected }
            else { child.isHidden = child !== previewHost && child !== controlsPanel }
        }
    }

    /// Dashboard and Appearance run their page under a clear titlebar. On Appearance the
    /// title and toolbar buttons follow the preview's own backdrop so they float over it.
    private func updateTitlebar() {
        guard let window else { return }
        let appearancePage = !showingOtherPane
        let clear = showingDashboard || appearancePage
        windowSurface.separator.isHidden = clear
        let titlebar = window.standardWindowButton(.closeButton)?.superview?.superview
        let name: NSAppearance.Name? = appearancePage ? (AppearancePreviewScene.hasLightTop(preview.mode) ? .aqua : .darkAqua) : nil
        if titlebar?.appearance?.name != name { titlebar?.appearance = name.flatMap(NSAppearance.init(named:)) }
    }

    private var showingOtherPane: Bool {
        showingRecentRecordings || showingDashboard || showingModels || showingKeys || showingWriting || showingMeetings || showingDictation
    }

    func windowWillClose(_ notification: Notification) { classicBarAvoidance?.reset(); if showingWriting { writingPane.editing.cancel() }; preview.stop(); gradientEditor.endColorEditing() }

    func selectPreview(_ mode: GlowAppearance) {
        if preview.mode != mode { gradientEditor.endColorEditing() }
        preview.mode = mode
        modeBar.select(mode)
        refresh()
        scrollControlsToTop()
    }

    func selectSection(_ section: AppearanceSection) {
        selectedSection = section
        preview.phase = section == .speech ? 1 : 0
        if section != .gradient { gradientEditor.endColorEditing() }
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
        guard let window, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        pageToolbar.refresh()
        if let previewHost {
            let inset = AppearancePreviewScene.topInset(of: previewHost)
            if preview.topInset != inset { preview.topInset = inset }
        }
        sidebar.updateCredits(state.creditBalance, hidden: !state.isProviderVisible("s2t"))
        for control in AppearanceControl.allCases {
            let value = control.value(in: state), label = control.formatted(control.value(in: state))
            if sliders[control]?.doubleValue != value { sliders[control]?.doubleValue = value }
            if values[control]?.stringValue != label { values[control]?.stringValue = label }
        }
        let gradient = state.glowTuning.gradients[preview.mode.rawValue] ?? .init()
        if refreshedGradient != gradient || refreshedGradientMode != preview.mode {
            refreshedGradient = gradient; refreshedGradientMode = preview.mode
            gradientEditor.refresh(gradient, mode: preview.mode)
        }
        let layout = LayoutState(mode: preview.mode, section: selectedSection, destination: destination,
            theme: state.menuAppearance, side: state.bezelSide,
            inputSize: state.glowTuning.inputSizeEnabled, notice: state.inputOutlineNotice)
        // Meter, phase and slider values do not rebuild the settings hierarchy.
        guard layout != refreshedLayout else { return }
        refreshedLayout = layout
        let windowBackground = sidebar.pageBackgroundColor ?? .windowBackgroundColor
        if window.backgroundColor != windowBackground { window.backgroundColor = windowBackground }
        updateTitlebar()
        if showingOtherPane { classicBarAvoidance?.reset() }
        sidebar.updateBackground(showingOtherPane ? nil : preview.mode)
        if !showingOtherPane { sidebar.selectAppearance() }
        modeBar.select(preview.mode)
        modeBar.isHidden = showingOtherPane
        sidePicker.selectedSegment = state.bezelSide == .left ? 0 : 1
        let appearanceName: NSAppearance.Name? = state.menuAppearance == "system" ? nil : state.menuAppearance == "dark" ? .darkAqua : .aqua
        if window.appearance?.name != appearanceName { window.appearance = appearanceName.flatMap(NSAppearance.init(named:)) }
        for control in AppearanceControl.allCases {
            rows[control]?.isHidden = !control.isVisible(for: preview.mode)
        }
        inputSizeRow.isHidden = preview.mode != .withinInput
        inputSizeToggle.state = state.glowTuning.inputSizeEnabled ? .on : .off
        for control in [AppearanceControl.inputMinimumSize, .inputMaximumSize] { sliders[control]?.isEnabled = state.glowTuning.inputSizeEnabled }
        let bezel = preview.mode == .bezel
        let fixed = bezel || preview.mode == .liquidGlass
        gradientEditor.isHidden = fixed || selectedSection != .gradient
        gradientCard.isHidden = gradientEditor.isHidden
        controlsPanel.isHidden = showingOtherPane
        adjustments.isHidden = fixed
        classicBarAvoidance?.setPresentation(classic: fixed)
        sideGroup.isHidden = true
        sectionBar.isHidden = showingOtherPane || fixed
        fixedPreviewHint.isHidden = showingOtherPane || !fixed
        sectionBar.select(selectedSection)
        for (section, card) in sectionCards { card.isHidden = fixed || section != selectedSection }
        reset.isHidden = fixed
        inputHelp.stringValue = state.inputOutlineNotice ?? "Outlines the focused window when an input box cannot be detected."
        inputHelp.isHidden = !preview.mode.followsInput || state.inputOutlineNotice == nil
        window.contentView?.layoutSubtreeIfNeeded()
        sidebar.backdrop.refreshGeometry()
    }

    @objc private func changeInputSize() {
        state.glowTuning.inputSizeEnabled = inputSizeToggle.state == .on
        refresh()
    }

    @objc private func changeSlider(_ sender: NSSlider) {
        guard let control = AppearanceControl.allCases.first(where: { $0.id == sender.identifier?.rawValue }) else { return }
        control.set(sender.doubleValue, in: state)
        if preview.running, preview.mode != .bezel && preview.mode != .liquidGlass {
            preview.renderer.submit(AppearancePreviewScene.request(state: state, mode: preview.mode, phase: preview.phase,
                time: Date.timeIntervalSinceReferenceDate,
                reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                backdrop: !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency))
        }
        for control in AppearanceControl.allCases {
            let value = control.value(in: state), label = control.formatted(control.value(in: state))
            if sliders[control]?.doubleValue != value { sliders[control]?.doubleValue = value }
            if values[control]?.stringValue != label { values[control]?.stringValue = label }
        }
    }
    @objc private func changeSide(_ sender: BezelPlacementPicker) {
        state.bezelSide = sender.selectedSegment == 0 ? .left : .right
        refresh()
    }
    @objc private func resetGlow() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Reset glow settings?"
        alert.informativeText = "Restores glow, edge, speech response and custom gradients for all three glow appearances."
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

/// The floating rail already has its own edge; leave no split divider beside it.
private final class SettingsSplitView: NSSplitView {
    override var dividerThickness: CGFloat { 0 }
    override var dividerColor: NSColor { .clear }
    override func drawDivider(in rect: NSRect) {}
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
