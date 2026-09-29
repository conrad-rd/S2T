import AppKit
import SwiftUI

/// The page and titlebar share one system background; the inset rail floats above it.
@MainActor final class SettingsWindowSurface: NSViewController {
    let background = NSHostingView(rootView: SettingsPageBackground())
    let separator = NSHostingView(rootView: Divider())

    init(split: NSSplitViewController) {
        super.init(nibName: nil, bundle: nil)
        view = NSView()
        addChild(split)
        background.safeAreaRegions = []
        separator.safeAreaRegions = []
        background.sizingOptions = []
        separator.sizingOptions = [.intrinsicContentSize]
        for child in [background, separator, split.view] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
            NSLayoutConstraint.activate([
                child.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
        }
        for child in [background, split.view] {
            NSLayoutConstraint.activate([
                child.topAnchor.constraint(equalTo: view.topAnchor),
                child.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
    }

    required init?(coder: NSCoder) { nil }

    func alignTitlebar(in window: NSWindow) {
        guard let guide = window.contentLayoutGuide as? NSLayoutGuide else { return }
        separator.bottomAnchor.constraint(equalTo: guide.topAnchor).isActive = true
    }
}
