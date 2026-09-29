import AppKit
import SwiftUI

@MainActor final class SettingsEditorWindow: NSWindow {
    var cancelFieldEditing: (() -> Void)?

    // AppKit owns titlebar geometry, focus rings and mouse tracking.
    override func sendEvent(_ event: NSEvent) {
        if handleEditingEvent(event) { return }
        super.sendEvent(event)
    }

    @discardableResult func handleEditingEvent(_ event: NSEvent) -> Bool {
        guard let editor = firstResponder as? NSTextView, editor.isFieldEditor else { return false }
        if event.type == .keyDown, event.keyCode == 53,
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
           !editor.hasMarkedText() {
            cancelFieldEditing?()
            return makeFirstResponder(nil)
        }
        return false
    }
}

@MainActor enum SettingsWindow {
    static func make(state: AppState) -> NSWindow {
        let window = SettingsEditorWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "S2T"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white
        let toolbar = NSToolbar(identifier: "S2TSettingsToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 780, height: 630)
        window.contentView = NSHostingView(rootView: ContentView(state: state))
        return window
    }
}
