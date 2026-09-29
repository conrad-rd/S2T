import AppKit
import ApplicationServices
import S2TCore

@MainActor enum DictionaryProbe {
    static func run() async throws {
        try measureReaderSampling()
        try verifyReader()
        try verifyFocusedDescendant()
        try await verifyObserverRecovery()
        try verifyControls()
        try await verifyLocalLearning()
        try await verifySaveBeforeCategorization()
        try await verifyJevRaceHandling()
        try await verifyContextChangePreservesCorrection()
        try await verifyTimedDismissal()
        print("PASS: dictionary focused-editor fixtures, secure/oversized exclusion, compact automatic confirmations, Remove, four-second expiry, manual-edit preservation and hidden panel layout. No real fields, dictionary, clipboard or screen pixels accessed.")
    }

    private static func verifyObserverRecovery() async throws {
        let pid: pid_t = 730_100
        let root = AXUIElementCreateApplication(pid)
        let field = AXUIElementCreateApplication(pid + 1)
        let editor = NSTextView(frame: .zero)
        editor.string = "Ask conrad today."
        var available = true
        var rejectValidation = false
        var rejectNextValue = false
        var foreground: pid_t? = pid
        var statuses: [String] = []
        let reader = DictionaryFieldReader(pid: pid, attribute: { node, name in
            DispatchQueue.main.sync {
                guard available else { return nil }
                if CFEqual(node, root) { return name == kAXFocusedUIElementAttribute ? field : nil }
                switch name {
                case kAXRoleAttribute: return kAXTextAreaRole as CFString
                case kAXValueAttribute:
                    if rejectNextValue { rejectNextValue = false; return nil }
                    return editor.string as CFString
                case kAXPositionAttribute:
                    if rejectValidation { rejectValidation = false; rejectNextValue = true }
                    return nil
                case kAXNumberOfCharactersAttribute: return NSNumber(value: editor.string.utf16.count)
                default: return nil
                }
            }
        }, fallbackFocus: { nil })
        let file = DictionaryFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("s2t-observer-" + UUID().uuidString).appendingPathComponent("dictionary.md"))
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        let learner = DictionaryLearner(makeReader: { _ in reader }, frontmostPID: { foreground }, presentsWindows: false)
        defer { learner.stop() }
        learner.start(output: editor.string, file: file, recipient: pid, expectedField: field,
            insertionSelection: NSRange(location: 0, length: 0), insertionBaseline: "",
            onStatus: { statuses.append($0) }, onError: { statuses.append($0) })
        for _ in 0..<40 {
            if statuses.contains(where: { $0.hasPrefix("Watching for") }) { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        guard statuses.contains(where: { $0.hasPrefix("Watching for") }) else { throw failure("Production watcher did not attach to the native editor.") }
        available = false
        try await Task.sleep(nanoseconds: 200_000_000)
        available = true
        editor.insertText("Konrad", replacementRange: NSRange(location: 4, length: 6))
        let first = DictionaryCorrection(original: "conrad", replacement: "Konrad", context: "Ask Konrad today.")
        for _ in 0..<40 {
            if try file.contains(first) { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        guard try file.contains(first) else { throw failure("A transient Accessibility failure permanently stopped the production correction watcher.") }
        foreground = nil
        try await Task.sleep(nanoseconds: 200_000_000)
        foreground = pid
        editor.insertText("Conrad", replacementRange: NSRange(location: 4, length: 6))
        let second = DictionaryCorrection(original: "conrad", replacement: "Conrad", context: "Ask Conrad today.")
        for _ in 0..<40 {
            if try file.contains(second) { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        guard try file.contains(second), try !file.contains(first) else { throw failure("Returning to the receiving field did not resume correction learning.") }
        rejectValidation = true
        editor.insertText("Konrad", replacementRange: NSRange(location: 4, length: 6))
        for _ in 0..<60 {
            if try file.contains(first) { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        guard !rejectValidation, try file.contains(first), try !file.contains(second) else {
            throw failure("A failed final validation silently lost a detected correction.")
        }
        learner.stop()
        editor.insertText("Conrad", replacementRange: NSRange(location: 4, length: 6))
        try await Task.sleep(nanoseconds: 350_000_000)
        guard try file.contains(first), try !file.contains(second) else { throw failure("A cancelled watcher saved a later edit.") }
        print("PASS: production watcher → native editor edits → dictionary file, including unavailable Accessibility, focus leave/return, failed final validation, replacement and cancellation. Injected AX transport; no user fields or providers.")
    }

    private static func verifyLocalLearning() async throws {
        let preferences = UserDefaults(suiteName: "com.s2t.preview")!
        let savedPreferences = preferences.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { preferences.setPersistentDomain(savedPreferences, forName: "com.s2t.preview") }
        preferences.setPersistentDomain(["dictionaryLearningRoute": "s2t", "speechUsesCredits": true], forName: "com.s2t.preview")
        let state = AppState(preview: true)
        guard !state.dictionaryCategorizationEnabled else { throw failure("Existing credit settings enabled paid categorization by default.") }
        state.dictionaryLearningRoute = .typeSafe
        state.dictionaryCategorizationEnabled = true
        let restored = AppState(preview: true)
        guard restored.dictionaryCategorizationEnabled, restored.dictionaryLearningRoute == .typeSafe else {
            throw failure("Categorization preferences were not restored independently.")
        }
        let file = DictionaryFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("s2t-dictionary-offline-" + UUID().uuidString).appendingPathComponent("dictionary.md"))
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        let ui = DictionarySuggestions(file: file, presentsWindows: false) { _ in }
        let controller = DictionaryLearningController(save: { ui.apply($0, bounds: nil) }, status: { _ in })
        let editor = NSTextView(frame: .zero)
        editor.string = "Ask conrad today."
        var observation = DictionaryObservation(output: editor.string, baseline: editor.string, startedAt: 0)!
        editor.insertText("Konrad", replacementRange: NSRange(location: 4, length: 6))
        _ = observation.sample(editor.string, at: 1)
        guard case .suggestions(let entries, _) = observation.sample(editor.string, at: 1.21) else {
            throw failure("The edited word was not detected locally.")
        }
        controller.submit(entries, isCurrent: { true })
        try await Task.sleep(nanoseconds: 30_000_000)
        guard let entry = entries.first, try file.contains(entry), entry.replacement == "Konrad", entry.categories.isEmpty else {
            throw failure("Offline word detection did not reach the dictionary file.")
        }
        controller.submit([], isCurrent: { true })
        try await Task.sleep(nanoseconds: 30_000_000)
        guard try !file.contains(entry) else { throw failure("Offline undo retained a correction.") }
        controller.invalidate()
        print("PASS: categorization defaults off for existing credit users, preferences persist, and native word edits save locally without a provider.")
    }

    private static func verifySaveBeforeCategorization() async throws {
        let judge = DictionaryFixtureJudge()
        let file = DictionaryFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("s2t-dictionary-local-" + UUID().uuidString).appendingPathComponent("dictionary.md"))
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        let ui = DictionarySuggestions(file: file, presentsWindows: false) { _ in }
        let controller = DictionaryLearningController(judge: { try await judge.decide($0) }, save: { ui.apply($0, bounds: nil) }, status: { _ in })
        let entry = DictionaryCorrection(original: "cloud flair", replacement: "Cloudflare", context: "Use Cloudflare today.")
        controller.submit([entry], isCurrent: { true })
        try await Task.sleep(nanoseconds: 50_000_000)
        guard try file.contains(entry), ui.visibleItems.count == 1 else {
            throw failure("A detected word correction was not saved before Jev responded.")
        }
        try await judge.waitForRequest()
        await judge.complete(.uncertain)
        try await Task.sleep(nanoseconds: 30_000_000)
        guard try file.contains(entry) else { throw failure("An uncertain category erased a locally saved correction.") }
        let second = DictionaryCorrection(original: "open router", replacement: "OpenRouter", context: "Use OpenRouter today.")
        controller.submit([entry, second], isCurrent: { true })
        try await judge.waitForRequest()
        await judge.fail()
        try await Task.sleep(nanoseconds: 30_000_000)
        guard try file.contains(entry), try file.contains(second) else { throw failure("A provider failure erased a locally saved correction.") }
        controller.invalidate()
        print("PASS: word corrections persist and show confirmation before categorization; uncertain categories and provider failures retain corrections.")
    }

    private static func verifyJevRaceHandling() async throws {
        let judge = DictionaryFixtureJudge()
        var saved: [DictionaryCorrection] = []
        var statuses: [String] = []
        let controller = DictionaryLearningController(judge: { try await judge.decide($0) }, save: { saved = $0; return true }, status: { statuses.append($0) })
        let first = DictionaryCorrection(original: "conrad", replacement: "Konrad", context: "Ask Konrad today.", categories: ["c001"])
        let second = DictionaryCorrection(original: "conrad", replacement: "Conrad", context: "Ask Conrad today.", categories: ["c001"])
        let firstLocal = DictionaryCorrection(original: first.original, replacement: first.replacement, context: first.context)
        let secondLocal = DictionaryCorrection(original: second.original, replacement: second.replacement, context: second.context)
        controller.submit([firstLocal], isCurrent: { true })
        try await judge.waitForRequest()
        controller.invalidate()
        await judge.complete(.accepted(first))
        try await Task.sleep(nanoseconds: 30_000_000)
        guard saved == [firstLocal] else { throw failure("A cancelled Jev response changed the local correction.") }
        controller.submit([secondLocal], isCurrent: { true })
        try await judge.waitForRequest()
        await judge.complete(.accepted(second))
        try await Task.sleep(nanoseconds: 30_000_000)
        guard saved == [second] else { throw failure("A current validated correction was not saved.") }
        controller.submit([], isCurrent: { true })
        try await Task.sleep(nanoseconds: 30_000_000)
        guard saved.isEmpty else { throw failure("Undo retained a learned correction.") }
        controller.submit([firstLocal], isCurrent: { await judge.current })
        try await judge.waitForRequest()
        await judge.loseFocus()
        await judge.complete(.accepted(first))
        try await Task.sleep(nanoseconds: 30_000_000)
        guard saved == [firstLocal] else { throw failure("A category changed after the receiving field lost focus.") }
        controller.invalidate()
        print("PASS: production dictionary controller saves locally, rejects stale categories, removes undo and revalidates focus. Fake Jev only.")
    }

    private static func verifyContextChangePreservesCorrection() async throws {
        let judge = DictionaryFixtureJudge()
        let file = DictionaryFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("s2t-dictionary-context-" + UUID().uuidString).appendingPathComponent("dictionary.md"))
        let first = DictionaryCorrection(original: "cloud flair", replacement: "Cloudflare", context: "Use Cloudflare today.", categories: ["c021"])
        let edited = DictionaryCorrection(original: first.original, replacement: first.replacement, context: "Use Cloudflare tomorrow.")
        let ui = DictionarySuggestions(file: file, presentsWindows: false) { _ in }
        let controller = DictionaryLearningController(judge: { try await judge.decide($0) }, save: { ui.apply($0, bounds: nil) }, status: { _ in })
        controller.submit([first], isCurrent: { true })
        try await judge.waitForRequest()
        await judge.complete(.accepted(first))
        try await Task.sleep(nanoseconds: 30_000_000)
        guard try file.contains(first) else { throw failure("Initial correction was not persisted.") }
        controller.submit([edited], isCurrent: { true })
        try await Task.sleep(nanoseconds: 30_000_000)
        guard try file.contains(first) else { throw failure("Typing near a saved correction removed it before a new decision.") }
        try await judge.waitForRequest()
        await judge.complete(.uncertain)
        try await Task.sleep(nanoseconds: 30_000_000)
        guard try file.contains(first) else { throw failure("Uncertain new context erased an already approved correction.") }
        controller.submit([], isCurrent: { true })
        try await Task.sleep(nanoseconds: 30_000_000)
        guard try !file.contains(first) else { throw failure("Undo did not remove the preserved session correction.") }
        controller.invalidate()
        print("PASS: later context changes retain approved dictionary records, while undo removes them.")
    }

    private static func verifyFocusedDescendant() throws {
        let root = AXUIElementCreateApplication(730001)
        let field = AXUIElementCreateApplication(730002)
        let leaf = AXUIElementCreateApplication(730003)
        var secure = false
        var reads = 0
        let reader = DictionaryFieldReader(pid: 730001, attribute: { node, name in
            if CFEqual(node, root), name == kAXFocusedUIElementAttribute { return leaf }
            if CFEqual(node, leaf) {
                if name == kAXRoleAttribute { return kAXStaticTextRole as CFString }
                if name == kAXParentAttribute { return field }
            }
            if CFEqual(node, field) {
                if name == kAXRoleAttribute { return kAXTextAreaRole as CFString }
                if name == kAXSubroleAttribute, secure { return kAXSecureTextFieldSubrole as CFString }
                if name == kAXValueAttribute { reads += 1; return "Use Cloudflare today." as CFString }
            }
            return nil
        }, children: { _ in [] }, fallbackFocus: { nil })
        guard let focused = reader.focused(), CFEqual(focused, field), reader.sample(field) == "Use Cloudflare today." else {
            throw failure("A focused text descendant prevented dictionary observation.")
        }
        secure = true
        let before = reads
        guard reader.focused() == nil, reader.sample(field) == nil, reads == before else {
            throw failure("A focused descendant allowed secure field contents to be read.")
        }
        print("PASS: focused text descendants resolve only to their nonsecure editor.")
    }

    private static func verifyTimedDismissal() async throws {
        let file = DictionaryFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("s2t-dictionary-timer-" + UUID().uuidString).appendingPathComponent("dictionary.md"))
        let correction = DictionaryCorrection(original: "konrad", replacement: "Konrad")
        var errors: [String] = []
        let ui = DictionarySuggestions(file: file, presentsWindows: false) { errors.append($0) }
        let started = ProcessInfo.processInfo.systemUptime
        ui.apply([correction], bounds: nil)
        let saved = ProcessInfo.processInfo.systemUptime
        guard try file.contains(correction), ui.visibleItems.count == 1 else { throw failure("Automatic save did not precede confirmation.") }
        try await Task.sleep(nanoseconds: 4_200_000_000)
        guard ui.visibleItems.isEmpty, ui.scheduledExpiry == nil, ui.panel?.isVisible == false,
              try file.contains(correction), errors.isEmpty else { throw failure("The real four-second timer did not dismiss the hidden confirmation.") }
        print(String(format: "Dictionary automatic save and hidden toast construction: %.1f ms; real four-second expiry passed.", (saved - started) * 1000))
    }

    private static func measureReaderSampling() throws {
        let root = AXUIElementCreateApplication(720001)
        let field = AXUIElementCreateApplication(720002)
        let ancestors = (0..<8).map { AXUIElementCreateApplication(pid_t(720010 + $0)) }
        var requests = 0
        let reader = DictionaryFieldReader(pid: 720001, attribute: { node, name in
            requests += 1
            if CFEqual(node, root), name == kAXFocusedUIElementAttribute { return field }
            if name == kAXParentAttribute {
                if CFEqual(node, field) { return ancestors[0] }
                if let i = ancestors.firstIndex(where: { CFEqual(node, $0) }), i + 1 < ancestors.count { return ancestors[i + 1] }
            }
            if CFEqual(node, field) {
                if name == kAXRoleAttribute { return kAXTextAreaRole as CFString }
                if name == kAXValueAttribute { return "Ask Konrad today" as CFString }
            }
            return nil
        }, children: { _ in [] }, rangeText: { _, _ in nil }, fallbackFocus: { nil })
        guard reader.sample(field) == "Ask Konrad today" else { throw failure("Sampling fixture failed.") }
        guard requests <= 8 else { throw failure("Steady sampling repeated editor ancestry lookups.") }
        print("Dictionary steady editor sample: \(requests) Accessibility attribute requests")
    }

    private static func verifyReader() throws {
        let root = AXUIElementCreateApplication(710001)
        let wrapper = AXUIElementCreateApplication(710002)
        let field = AXUIElementCreateApplication(710003)
        let second = AXUIElementCreateApplication(710004)
        var focus: AXUIElement? = nil
        var secure = false
        var editable = false
        var ambiguous = false
        var role = kAXTextAreaRole
        var valueReads = 0
        let reader = DictionaryFieldReader(pid: 710001, attribute: { element, name in
            if CFEqual(element, root), name == kAXFocusedUIElementAttribute { return focus }
            if CFEqual(element, wrapper), name == kAXRoleAttribute { return kAXGroupRole as CFString }
            if CFEqual(element, field) || CFEqual(element, second) {
                if name == kAXRoleAttribute { return role as CFString }
                if name == kAXSubroleAttribute, secure { return kAXSecureTextFieldSubrole as CFString }
                if name == "AXEditable" { return editable ? kCFBooleanTrue : kCFBooleanFalse }
                if name == kAXValueAttribute { valueReads += 1; return "Ask conrad today" as CFString }
            }
            return nil
        }, children: { element in
            CFEqual(element, wrapper) ? (ambiguous ? [field, second] : [field]) : []
        }, rangeText: { _, _ in nil }, fallbackFocus: { nil })
        guard reader.focused() == nil else { throw failure("Unavailable focus was accepted.") }
        focus = wrapper
        guard let found = reader.focused(), CFEqual(found, field), reader.read(found) == "Ask conrad today" else {
            throw failure("Delayed wrapped editor was not resolved.")
        }
        ambiguous = true
        guard reader.focused() == nil else { throw failure("Ambiguous editors were accepted.") }
        ambiguous = false
        role = kAXGroupRole; editable = true
        guard let contentEditable = reader.focused(), reader.read(contentEditable) != nil else { throw failure("Explicitly editable content was ignored.") }
        role = kAXComboBoxRole; editable = false
        guard reader.focused() == nil else { throw failure("A noneditable combo box was accepted.") }
        role = kAXTextAreaRole; secure = true
        let before = valueReads
        guard reader.focused() == nil, reader.read(field) == nil, valueReads == before else { throw failure("Secure contents were read.") }
        var attributes: [String: CFTypeRef] = [kAXRoleAttribute: kAXTextAreaRole as CFString, kAXNumberOfCharactersAttribute: 6 as CFNumber]
        guard DictionaryFieldReader.readText(attribute: { attributes[$0] }, rangeText: { _ in "Konrad" }) == "Konrad" else { throw failure("Bounded range text fallback failed.") }
        attributes[kAXValueAttribute] = "" as CFString
        guard DictionaryFieldReader.readText(attribute: { attributes[$0] }, rangeText: { _ in "Konrad" }) == "Konrad" else {
            throw failure("An empty Accessibility value hid the editor's nonempty range text.")
        }
        attributes[kAXNumberOfCharactersAttribute] = 20_000 as CFNumber
        var rangeRead = false
        guard DictionaryFieldReader.readText(attribute: { attributes[$0] }, rangeText: { _ in rangeRead = true; return "Konrad" }) == nil, !rangeRead else {
            throw failure("Oversized text reached range read.")
        }
    }

    private static func verifyControls() throws {
        let file = DictionaryFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("s2t-dictionary-ui-" + UUID().uuidString).appendingPathComponent("dictionary.md"))
        _ = try file.read()
        let manual = "# Personal dictionary\n\n- My manual name\n"
        try manual.write(to: file.url, atomically: true, encoding: .utf8)
        var errors: [String] = []
        var time: TimeInterval = 100
        let ui = DictionarySuggestions(file: file, presentsWindows: false, now: { time }) { errors.append($0) }
        let first = DictionaryCorrection(original: "yew", replacement: "you")
        let phrase = DictionaryCorrection(original: "old account", replacement: "our new company account")
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        ui.apply([first], bounds: CGRect(x: 200, y: 300, width: 200, height: 60))
        guard ui.items.count == 1, ui.deleteButtons.count == 1,
              let panel = ui.panel, !panel.isVisible, !panel.canBecomeKey, !panel.canBecomeMain, !panel.ignoresMouseEvents,
              panel.styleMask.contains(.nonactivatingPanel), try file.contains(first),
              panel.frame.height == 36, panel.frame.width <= 160, ui.scheduledExpiry == 104 else {
            throw failure("Corrections must save automatically in a compact four-second confirmation.")
        }
        let id = ui.items[0].id
        guard let remove = ui.deleteButtons[id], remove.title.isEmpty, remove.frame.size == CGSize(width: 24, height: 24),
              remove.accessibilityLabel() == "Remove \"you\" from dictionary", remove.acceptsFirstMouse(for: nil) else {
            throw failure("Missing compact accessible Remove control or first-click support.")
        }
        try verifyMountedContent(panel: panel, word: first.replacement, button: remove)
        time = 101
        ui.apply([first, phrase], bounds: nil)
        guard ui.items.count == 2, ui.rowFrames.count == 2, ui.rowFrames[0].maxY <= ui.rowFrames[1].minY,
              try file.contains(phrase), ui.scheduledExpiry == 104 else { throw failure("Independent corrections failed to stack or reset an older expiry.") }
        try verifyMountedContent(panel: panel, word: phrase.replacement, button: ui.deleteButtons[ui.items[1].id]!)
        var content = try file.read()
        content += "\nNew manual note.\n"
        try content.write(to: file.url, atomically: true, encoding: .utf8)
        remove.performClick(nil)
        guard !ui.items[0].saved, try !file.contains(first), ui.deleteButtons[id] == nil,
              try file.read().hasPrefix(manual), try file.read().hasSuffix("New manual note.\n") else { throw failure("Remove damaged manual edits or failed to remove the saved record.") }
        try verifyMountedContent(panel: panel, word: phrase.replacement, button: ui.deleteButtons[ui.items[1].id]!)
        ui.apply([first, phrase], bounds: nil)
        guard !ui.items[0].saved, try !file.contains(first), ui.visibleItems.count == 1 else { throw failure("A removed entry was automatically re-added.") }
        var revised = DictionaryCorrection(original: phrase.original, replacement: "the new company account")
        time = 102
        ui.apply([first, revised], bounds: nil)
        guard ui.items.count == 2, ui.items[1].correction == revised, try file.contains(revised), try !file.contains(phrase) else {
            throw failure("Continued typing left a provisional dictionary entry behind.")
        }
        time = 105.999
        ui.expireDue()
        guard ui.visibleItems.count == 1 else { throw failure("Confirmation expired before four seconds.") }
        time = 106
        ui.expireDue()
        guard ui.visibleItems.isEmpty, ui.scheduledExpiry == nil, !panel.isVisible, try file.contains(revised) else {
            throw failure("Expiry did not hide the confirmation or removed a saved correction.")
        }
        time = 107
        ui.apply([first, revised], bounds: nil)
        guard ui.visibleItems.isEmpty else { throw failure("Unchanged corrections reappeared after expiry.") }
        let categorized = DictionaryCorrection(original: revised.original, replacement: revised.replacement, categories: ["c047"])
        ui.apply([first, categorized], bounds: nil)
        guard ui.visibleItems.isEmpty, try file.contains(categorized), try !file.contains(revised) else {
            throw failure("Background categorization duplicated the word or displayed an expired confirmation again.")
        }
        revised = categorized
        let extra = (0..<10).map { DictionaryCorrection(original: "old \($0)", replacement: "a longer preferred phrase \($0)") }
        ui.apply([first, revised] + extra, bounds: nil)
        guard ui.visibleItems.count == 10, let contentView = ui.panel?.contentView, contentView.frame.height <= 320,
              descendants(contentView).compactMap({ $0 as? NSScrollView }).first?.hasVerticalScroller == true,
              errors.isEmpty, NSWorkspace.shared.frontmostApplication?.processIdentifier == front else { throw failure("Long stacks must scroll without taking focus.") }
        let firstVisible = ui.visibleItems[0]
        try verifyMountedContent(panel: panel, word: firstVisible.correction.replacement, button: ui.deleteButtons[firstVisible.id]!)
        ui.apply([], bounds: nil)
        guard ui.visibleItems.isEmpty, try !file.contains(revised) else { throw failure("Reverting a correction retained its provisional record.") }
        let long = DictionaryCorrection(original: "previous name", replacement: "International Association for Research into Language and Communication")
        ui.apply([long], bounds: nil)
        guard let longItem = ui.visibleItems.first, panel.frame.height > 36, panel.frame.width <= 340 else {
            throw failure("Long phrases must wrap within the compact confirmation.")
        }
        try verifyMountedContent(panel: panel, word: long.replacement, button: ui.deleteButtons[longItem.id]!)
        for display in [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: 900, width: 1920, height: 1080)] {
            let frame = DictionaryLearner.popupFrame(above: CGRect(x: display.minX, y: display.maxY - 24, width: 80, height: 24), visibleFrame: display, height: 320)
            guard display.contains(frame) else { throw failure("Confirmation left the display.") }
        }
        ui.hide()
    }

    private static func verifyMountedContent(panel: NSPanel, word: String, button: NSButton) throws {
        guard let root = panel.contentView else { throw failure("Missing confirmation content.") }
        let views = descendants(root)
        guard let scroll = views.compactMap({ $0 as? NSScrollView }).first,
              scroll.contentView.bounds.width > 0, scroll.contentView.bounds.height >= 36 else {
            throw failure("The confirmation viewport is empty: \(views.compactMap { $0 as? NSScrollView }.first?.frame ?? .zero).")
        }
        guard let quote = views.compactMap({ $0 as? NSTextField }).first(where: { $0.stringValue == "\"\(word)\"" }),
              quote.window === panel, quote.visibleRect.contains(quote.bounds),
              button.visibleRect.contains(button.bounds) else {
            throw failure("The quoted correction or Remove control is clipped out of the mounted view.")
        }
        let textSize = quote.cell?.cellSize(forBounds: CGRect(x: 0, y: 0, width: quote.bounds.width, height: .greatestFiniteMagnitude)) ?? .zero
        guard textSize.height <= quote.bounds.height, button.image != nil else {
            throw failure("The complete phrase or Remove icon does not fit its control.")
        }
        guard quote.textColor == NSColor.white,
              panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
              !views.compactMap({ $0 as? NSTextField }).contains(where: { $0.stringValue == "Added to dictionary" }),
              !button.isBordered, button.frame.width == 24 else {
            throw failure("Dictionary confirmation must use compact white-on-dark recording styling without a subtitle or large button.")
        }
        if #available(macOS 26, *), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            guard let glass = views.compactMap({ $0 as? NSGlassEffectView }).first(where: { effect in
                effect.contentView.map { descendants($0).contains(where: { $0 === quote }) } ?? false
            }), glass.style == .clear,
                  glass.contentView.map({ descendants($0).contains(where: { $0 === button }) }) == true else {
                throw failure("Each confirmation must own its text and remove action inside native clear glass.")
            }
        }
        let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: root.superview)
        guard root.hitTest(point) === button else { throw failure("Remove cannot be reached through the actual view hierarchy.") }
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "DictionaryProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private actor DictionaryFixtureJudge {
    private var pending: CheckedContinuation<DictionaryLearningDecision, Error>?
    private(set) var current = true
    func decide(_ plan: DictionaryLearningPlan) async throws -> DictionaryLearningDecision {
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func complete(_ decision: DictionaryLearningDecision) { pending?.resume(returning: decision); pending = nil }
    func fail() { pending?.resume(throwing: URLError(.notConnectedToInternet)); pending = nil }
    func loseFocus() { current = false }
    func waitForRequest() async throws {
        for _ in 0..<150 {
            if pending != nil { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw ServiceError.message("The dictionary fixture did not request a decision.")
    }
}
