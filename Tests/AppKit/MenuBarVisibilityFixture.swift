import AppKit

@main struct VisibilityFixture {
    @MainActor static func main() {
        do { try run() } catch { fputs("\(error)\n", stderr); exit(1) }
    }
    @MainActor static func run() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let phase = CommandLine.arguments[1]
        switch phase {
        case "seed-old-hidden-state":
            let item = NSStatusBar.system.statusItem(withLength: 24)
            item.isVisible = false
            UserDefaults.standard.synchronize()
            print("Saved hidden state for unnamed Item-0")
        case "launch":
            let item = MenuBarStatusItem.make(length: 24, preview: false)
            guard item.isVisible else { throw Failure(message: "Real app inherited the verification item's hidden state") }
            guard item.autosaveName == MenuBarStatusItem.applicationName else { throw Failure(message: "Real item lacks a stable identity") }
            UserDefaults.standard.synchronize()
            print("Real item is visible after launch")
        case "hide-preview":
            let item = MenuBarStatusItem.make(length: 24, preview: true)
            guard item.autosaveName != MenuBarStatusItem.applicationName else { throw Failure(message: "Preview shares production identity") }
            item.isVisible = false
            UserDefaults.standard.synchronize()
            print("Preview is hidden under a separate identity")
        case "cleanup":
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
            UserDefaults.standard.synchronize()
        default: throw Failure(message: "Unknown fixture phase")
        }
    }
    struct Failure: Error { let message: String }
}
