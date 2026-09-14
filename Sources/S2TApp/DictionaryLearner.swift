import AppKit
import ApplicationServices
import S2TCore

@MainActor final class DictionaryLearner {
    private struct SavedCorrection: Sendable {
        var words: [String] = []
        var bounds: CGRect? = nil
    }
    private var task: Task<Void, Never>?
    private var worker: Task<Result<SavedCorrection, Error>, Never>?
    private var popup: NSPanel?
    private var dismiss: Task<Void, Never>?

    func stop() { task?.cancel(); worker?.cancel(); task = nil; worker = nil }

    func start(output: String, file: DictionaryFile, onError: @escaping (String) -> Void) {
        stop()
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.bundleIdentifier != "com.raycast.macos" else { return }
        let pid = app.processIdentifier
        task = Task {
            guard !Task.isCancelled else { return }
            let operation = Task.detached(priority: .utility) { () -> Result<SavedCorrection, Error> in
                let root = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(root, 0.15)
                func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
                    var value: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
                    return value
                }
                func focused() -> AXUIElement? {
                    guard let value = attribute(root, kAXFocusedUIElementAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
                    return (value as! AXUIElement)
                }
                func read(_ field: AXUIElement) -> String? {
                    guard let role = attribute(field, kAXRoleAttribute) as? String,
                          [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
                          attribute(field, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
                          let count = attribute(field, kAXNumberOfCharactersAttribute) as? Int,
                          count <= 16_384,
                          let value = attribute(field, kAXValueAttribute) as? String,
                          value.utf8.count <= 16_384 else { return nil }
                    return value
                }
                func bounds(_ field: AXUIElement, range: NSRange) -> CGRect? {
                    var axRange = CFRange(location: range.location, length: range.length)
                    if let parameter = AXValueCreate(.cfRange, &axRange) {
                        var result: CFTypeRef?
                        if AXUIElementCopyParameterizedAttributeValue(field, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &result) == .success,
                           let result, CFGetTypeID(result) == AXValueGetTypeID() {
                            var rect = CGRect.zero
                            if AXValueGetValue(result as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 { return rect }
                        }
                    }
                    guard let position = attribute(field, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
                          let size = attribute(field, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
                    var point = CGPoint.zero
                    var dimensions = CGSize.zero
                    guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
                          AXValueGetValue(size as! AXValue, .cgSize, &dimensions), dimensions.width > 0, dimensions.height > 0 else { return nil }
                    return CGRect(origin: point, size: dimensions)
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let field = focused(), let baseline = read(field),
                      let range = baseline.range(of: output),
                      baseline.range(of: output, range: range.upperBound..<baseline.endIndex) == nil else { return .success(SavedCorrection()) }
                let prefix = String(baseline[..<range.lowerBound]), suffix = String(baseline[range.upperBound...])
                var previous: String?
                for _ in 0..<30 {
                    do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return .success(SavedCorrection()) }
                    let active = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
                    guard active, let currentFocus = focused(), CFEqual(currentFocus, field), let current = read(field),
                          let confirmed = focused(), CFEqual(confirmed, field) else { return .success(SavedCorrection()) }
                    guard current.hasPrefix(prefix), current.hasSuffix(suffix), current.count >= prefix.count + suffix.count else { return .success(SavedCorrection()) }
                    let edited = String(current.dropFirst(prefix.count).dropLast(suffix.count))
                    let words = DictionaryCorrections.words(original: output, corrected: edited)
                    if !words.isEmpty, previous == current {
                        do {
                            try Task.checkCancellation()
                            let anchor = bounds(field, range: NSRange(location: prefix.utf16.count, length: edited.utf16.count))
                            guard let confirmed = focused(), CFEqual(confirmed, field) else { return .success(SavedCorrection()) }
                            return .success(SavedCorrection(words: try file.append(words), bounds: anchor))
                        } catch { return .failure(error) }
                    }
                    previous = current
                }
                return .success(SavedCorrection())
            }
            worker = operation
            let result = await operation.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let saved): if !saved.words.isEmpty { show(saved.words, bounds: saved.bounds) }
            case .failure(let error): onError("Could not save dictionary correction. " + error.localizedDescription)
            }
        }
    }

    static func popupFrame(above anchor: CGRect, visibleFrame: CGRect) -> CGRect {
        let width = min(CGFloat(320), visibleFrame.width)
        let x = min(max(anchor.midX - width / 2, visibleFrame.minX), visibleFrame.maxX - width)
        let preferredY = anchor.maxY + 8
        let y = preferredY + 44 <= visibleFrame.maxY ? preferredY : anchor.minY - 52
        return CGRect(x: x, y: min(max(y, visibleFrame.minY), visibleFrame.maxY - 44), width: width, height: 44)
    }

    private func show(_ words: [String], bounds: CGRect?) {
        dismiss?.cancel()
        let panel = popup ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        popup = panel
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 320, height: 44))
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        let label = NSTextField(labelWithString: "Added to dictionary: " + words.joined(separator: ", "))
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 14, y: 14, width: 292, height: 17)
        background.addSubview(label)
        panel.contentView = background
        let anchor = bounds.map { CGRect(x: $0.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - $0.maxY, width: $0.width, height: $0.height) }
            ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.max { left, right in
            let a = left.frame.intersection(anchor), b = right.frame.intersection(anchor)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        }
        let targetScreen = bounds == nil ? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } : screen
        guard let frame = (targetScreen ?? NSScreen.main)?.visibleFrame else { return }
        panel.setFrame(Self.popupFrame(above: anchor, visibleFrame: frame), display: false)
        panel.orderFrontRegardless()
        dismiss = Task {
            do { try await Task.sleep(nanoseconds: 4_000_000_000) } catch { return }
            panel.orderOut(nil)
        }
    }
}
