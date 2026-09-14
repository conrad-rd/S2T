import AppKit
import CryptoKit
import S2TCore

@MainActor final class ClipboardMonitor {
    static let outputType = NSPasteboard.PasteboardType("com.s2t.dictation.output")
    private let pasteboard: NSPasteboard
    private let persistence: ClipboardHistoryPersistence?
    private var archive = ClipboardArchive()
    private var restored = false
    private var dirty = false
    private var checkInitialClipboard = true
    private var timer: Timer?
    private(set) var isRunning = false
    private(set) var persistenceError: String?
    var itemCount: Int { archive.history.entries.count }
    var entries: [ClipboardHistory.Entry] { archive.history.entries }
    var onChange: (() -> Void)?

    init(pasteboard: NSPasteboard = .general, persistence: ClipboardHistoryPersistence? = nil) {
        self.pasteboard = pasteboard
        self.persistence = persistence
        restore()
        persist()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        checkInitialClipboard = true
        poll()
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        persist()
        onChange?()
    }

    func snapshot() -> ClipboardHistory {
        poll()
        return archive.history
    }

    func clear() {
        archive.history = ClipboardHistory()
        archive.changeCount = pasteboard.changeCount
        archive.fingerprint = fingerprint(currentText())
        restored = true
        dirty = true
        persist()
        onChange?()
    }

    func poll() {
        guard isRunning else { return }
        let previous = entries
        let previousError = persistenceError
        defer {
            persist()
            if entries != previous || persistenceError != previousError { onChange?() }
        }
        if !restored { restore() }
        archive.history.prune()
        if entries != previous { dirty = true }
        let change = pasteboard.changeCount
        guard change != archive.changeCount || checkInitialClipboard else { return }
        checkInitialClipboard = false
        let text = currentText()
        guard pasteboard.changeCount == change else { checkInitialClipboard = true; return }
        let digest = fingerprint(text)
        guard change != archive.changeCount || digest != archive.fingerprint else { return }
        archive.changeCount = change
        archive.fingerprint = digest
        dirty = true
        if let text { archive.history.record(text) }
    }

    private func currentText() -> String? {
        guard pasteboard.availableType(from: [Self.outputType]) == nil else { return nil }
        return pasteboard.string(forType: .string) ?? pasteboard.string(forType: .URL)
    }

    private func fingerprint(_ text: String?) -> String? {
        text.map { Data(SHA256.hash(data: Data($0.utf8))).base64EncodedString() }
    }

    private func restore() {
        guard let persistence else { restored = true; return }
        do {
            var saved = try persistence.load(at: Date())
            if dirty {
                saved.history = ClipboardHistory(restoring: saved.history.entries + entries)
                saved.changeCount = archive.changeCount
                saved.fingerprint = archive.fingerprint
            }
            archive = saved
            restored = true
            dirty = true
            persistenceError = nil
        } catch {
            persistenceError = "Could not load saved clipboard history. The saved file has been left intact. " + error.localizedDescription
        }
    }

    private func persist() {
        guard dirty, restored, let persistence else { return }
        do {
            try persistence.save(archive)
            dirty = false
            persistenceError = nil
        } catch {
            persistenceError = "Clipboard history has unsaved changes. S2T will retry while running. " + error.localizedDescription
        }
    }
}
