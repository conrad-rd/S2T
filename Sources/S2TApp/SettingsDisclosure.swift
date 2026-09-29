import AppKit
import SwiftUI

@MainActor final class SettingsDisclosure: NSStackView {
    let content = SettingsDocumentStack()
    private let selection: DisclosureSelection
    var expanded: Bool { selection.expanded }

    init(_ title: String, expanded: Bool = false, onChange: @escaping (Bool) -> Void = { _ in }) {
        selection = DisclosureSelection(expanded: expanded)
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 10
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.isHidden = !expanded
        let header = NSHostingView(rootView: SettingsDisclosureLabel(title: title, selection: selection))
        addArrangedSubview(header)
        addArrangedSubview(content)
        for child in [header, content] {
            child.translatesAutoresizingMaskIntoConstraints = false
            child.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        header.heightAnchor.constraint(equalToConstant: 32).isActive = true
        selection.onChange = { [weak self] expanded in
            self?.content.isHidden = !expanded
            onChange(expanded)
        }
    }
    required init?(coder: NSCoder) { nil }
    func setExpanded(_ expanded: Bool) { selection.setExpanded(expanded) }
    func add(_ view: NSView) {
        content.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    }
}

@MainActor private final class DisclosureSelection: ObservableObject {
    @Published var expanded: Bool
    var onChange: ((Bool) -> Void)?
    init(expanded: Bool) { self.expanded = expanded }
    func setExpanded(_ value: Bool) {
        expanded = value
        onChange?(value)
    }
}

private struct SettingsDisclosureLabel: View {
    let title: String
    @ObservedObject var selection: DisclosureSelection
    var body: some View {
        Toggle(title, isOn: Binding(get: { selection.expanded }, set: selection.setExpanded))
        .toggleStyle(.switch)
        .controlSize(.regular)
        .tint(.blue)
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor final class LocalTaskSelection: ObservableObject {
    static let titles = ["Speech to text", "Text cleanup"]
    @Published private(set) var index: Int
    var onChange: ((Int) -> Void)?
    init(index: Int) { self.index = index }
    func select(_ index: Int) {
        guard Self.titles.indices.contains(index) else { return }
        self.index = index
        onChange?(index)
    }
}

struct LocalTaskPicker: View {
    @ObservedObject var selection: LocalTaskSelection
    var body: some View {
        SettingsChoiceBar(titles: LocalTaskSelection.titles, selected: selection.index,
                          label: "Task", select: selection.select)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("models.local.task")
    }
}

enum ModelsSection: Int, CaseIterable {
    case speech, cleanup, local
    var title: String {
        switch self {
        case .speech: "Speech to text"
        case .cleanup: "Text cleanup"
        case .local: "Local models"
        }
    }
}

/// Model settings with sub-pages for provider visibility, local models and comparisons.
@MainActor final class ModelsNavigation: ObservableObject {
    enum Page { case settings, local, compare, providers }
    @Published private(set) var page = Page.settings
    /// The most recently requested task. On the settings page it is the section to reveal.
    @Published private(set) var section = ModelsSection.cleanup
    private(set) var scrollTarget: ModelsSection?
    var comparing: Bool { page == .compare }
    var onSubpage: Bool { page != .settings }
    var pageTitle: String {
        switch page {
        case .settings: "Models"
        case .local: "Local models"
        case .compare: "Compare models"
        case .providers: "Providers"
        }
    }
    var onChange: ((ModelsSection) -> Void)?

    func showOverview() {
        page = .settings
        scrollTarget = nil
        if section == .local { section = .cleanup }
        onChange?(section)
    }
    func showComparison() {
        page = .compare
        onChange?(section)
    }
    func showProviders() {
        page = .providers
        onChange?(section)
    }
    func back() { showOverview() }
    /// Shows a task's section on the settings page, or the local model library for `.local`.
    func select(_ section: ModelsSection) {
        self.section = section
        if section == .local { page = .local; scrollTarget = nil }
        else { page = .settings; scrollTarget = section }
        onChange?(section)
    }
    func takeScrollTarget() -> ModelsSection? {
        defer { scrollTarget = nil }
        return scrollTarget
    }
}
