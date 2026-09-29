import AppKit

final class ReadOnlyAccessibilityEditor: NSTextView {
    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        if ["setAccessibilityValue:", "setAccessibilitySelectedText:"].contains(NSStringFromSelector(selector)) { return false }
        return super.isAccessibilitySelectorAllowed(selector)
    }
}

final class SelectionlessEditor: NSTextView {
    override func accessibilitySelectedTextRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }
}

final class DeferredSelectionSearchField: NSSearchField {
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.currentEditor()?.selectAll(nil)
            }
        }
        return result
    }
}

final class FixturePaste: NSObject {
    @objc func paste(_ sender: Any?) {
        guard let name = ProcessInfo.processInfo.environment["S2T_TEST_PASTEBOARD"],
              let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        print("fixture paste responder=\(editor.accessibilityIdentifier()) selection=\(editor.selectedRange())")
        fflush(stdout)
        _ = editor.readSelection(from: NSPasteboard(name: .init(name)))
    }
}
let fixturePaste = FixturePaste()
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let menu = NSMenu()
let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
let editMenu = NSMenu(title: "Edit")
let pasteItem = editMenu.addItem(withTitle: "Paste", action: #selector(FixturePaste.paste(_:)), keyEquivalent: "v")
pasteItem.target = fixturePaste
editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
editItem.submenu = editMenu
menu.addItem(editItem)
app.mainMenu = menu
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 340), styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.title = "S2T paste verification"
let content = NSView(frame: window.contentLayoutRect)
let field = DeferredSelectionSearchField(frame: NSRect(x: 20, y: 285, width: 430, height: 28))
field.stringValue = "before selected after"
field.setAccessibilityIdentifier("probe.search")
let editor = NSTextView(frame: NSRect(x: 20, y: 150, width: 430, height: 120))
editor.string = "before selected after"
editor.isRichText = false
editor.allowsUndo = true
editor.setAccessibilityIdentifier("probe.editor")
let readOnlyEditor = ReadOnlyAccessibilityEditor(frame: NSRect(x: 20, y: 80, width: 430, height: 55))
readOnlyEditor.string = "before selected after"
readOnlyEditor.isRichText = false
readOnlyEditor.allowsUndo = true
readOnlyEditor.setAccessibilityIdentifier("probe.readOnlyEditor")
let selectionless = SelectionlessEditor(frame: NSRect(x: 20, y: 15, width: 430, height: 55))
selectionless.string = "existing text"
selectionless.isRichText = false
selectionless.setAccessibilityIdentifier("probe.selectionless")
content.addSubview(selectionless)
content.addSubview(readOnlyEditor)
content.addSubview(field)
content.addSubview(editor)
window.contentView = content
window.center()
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
window.makeFirstResponder(editor)
editor.setSelectedRange(NSRange(location: 7, length: 8))
Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { _ in app.terminate(nil) }
app.run()
