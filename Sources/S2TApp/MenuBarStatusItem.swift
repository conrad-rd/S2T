import AppKit

@MainActor enum MenuBarStatusItem {
    static let applicationName = "S2T.MenuBar"
    static let verificationName = "S2T.Verification"

    static func make(length: CGFloat, preview: Bool) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: length)
        // AppKit persists visibility even for unnamed items. Verification must use its own identity.
        item.autosaveName = preview ? verificationName : applicationName
        item.isVisible = true
        return item
    }
}
