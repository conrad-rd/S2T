import AppKit
import ApplicationServices
import S2TCore

@MainActor final class DictionaryLearner {
    private var worker: Task<Void, Never>?
    private var suggestions: DictionarySuggestions?
    private var learning: DictionaryLearningController?
    private var session = UUID()
    private var retryRequested = false
    private let makeReader: (pid_t) -> DictionaryFieldReader
    private let frontmostPID: () -> pid_t?
    private let presentsWindows: Bool

    init(makeReader: @escaping (pid_t) -> DictionaryFieldReader = { DictionaryFieldReader(pid: $0) },
         frontmostPID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
         presentsWindows: Bool = true) {
        self.makeReader = makeReader
        self.frontmostPID = frontmostPID
        self.presentsWindows = presentsWindows
    }

    func stop() {
        session = UUID()
        retryRequested = false
        worker?.cancel()
        worker = nil
        learning?.invalidate()
        learning = nil
        suggestions?.hide()
        suggestions = nil
    }

    func start(output: String, file: DictionaryFile, recipient: pid_t?, expectedField: AXUIElement? = nil,
               insertionSelection: NSRange? = nil, insertionBaseline: String? = nil,
               judge: DictionaryLearningController.Judge? = nil,
               onStatus: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        stop()
        guard let pid = recipient, pid != ProcessInfo.processInfo.processIdentifier,
              NSRunningApplication(processIdentifier: pid)?.bundleIdentifier != "com.raycast.macos" else {
            onStatus("Dictionary learning unavailable: no receiving app was captured.")
            return
        }
        let token = session
        let startedAt = ProcessInfo.processInfo.systemUptime
        let presentation = DictionarySuggestions(file: file, presentsWindows: presentsWindows, onError: onError)
        suggestions = presentation
        learning = DictionaryLearningController(judge: judge, save: { entries in
            presentation.apply(entries, bounds: nil)
        }, status: onStatus)
        onStatus("Waiting for the delivered text in the receiving field…")
        let reader = makeReader(pid)
        let isActive: @MainActor @Sendable () -> Bool = { [frontmostPID] in frontmostPID() == pid }
        worker = Task.detached(priority: .utility) { [weak self] in
            defer { Task { @MainActor [weak self] in self?.finished(session: token) } }
            reader.prepare()
            var field: AXUIElement?
            var observation: DictionaryObservation?
            // Browser accessibility trees and asynchronous paste can become available after delivery.
            while !Task.isCancelled, ProcessInfo.processInfo.systemUptime - startedAt < 60 {
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                guard await isActive() else { continue }
                if let focused = reader.focused() {
                    if let expectedField {
                        guard let expected = reader.editor(near: expectedField), CFEqual(expected, focused) else { continue }
                    }
                    if let field, !CFEqual(field, focused) { continue }
                    field = focused
                    if let baseline = reader.read(focused), let confirmed = reader.focused(), CFEqual(confirmed, focused) {
                        guard await isActive(), !Task.isCancelled else { continue }
                        observation = DictionaryObservation(output: output, baseline: baseline, startedAt: startedAt,
                                                            selection: reader.selection(focused), insertionSelection: insertionSelection,
                                                            insertionBaseline: insertionBaseline)
                        if observation != nil { break }
                    }
                }
            }
            guard let field, var observation else {
                await self?.unavailable(session: token, onStatus: onStatus)
                return
            }
            await self?.watching(session: token, onStatus: onStatus)
            var previous: String?
            while !Task.isCancelled, ProcessInfo.processInfo.systemUptime - startedAt < 60 {
                do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return }
                guard await isActive(), let current = reader.sample(field), await isActive() else {
                    await self?.changed(session: token)
                    observation.retryEvaluation()
                    continue
                }
                guard !Task.isCancelled else { return }
                if await self?.takeRetry(session: token) == true { observation.retryEvaluation() }
                if previous != current {
                    previous = current
                    await self?.changed(session: token)
                }
                switch observation.sample(current, at: ProcessInfo.processInfo.systemUptime) {
                case .waiting: break
                case .stopped: return
                case .suggestions(let entries, let range):
                    let anchor = reader.bounds(field, range: range)
                    guard !Task.isCancelled else { return }
                    await self?.submit(entries, bounds: anchor, session: token, isCurrent: {
                        guard ProcessInfo.processInfo.systemUptime - startedAt < 60,
                              await isActive(), !Task.isCancelled else { return false }
                        let value = await Task.detached(priority: .utility) { reader.sample(field) }.value
                        let active = await isActive()
                        return value == current && !Task.isCancelled && active
                    })
                }
            }
        }
    }

    private func watching(session token: UUID, onStatus: (String) -> Void) {
        guard session == token else { return }
        onStatus("Watching for corrections in the receiving field for one minute.")
    }

    private func changed(session token: UUID) {
        guard session == token else { return }
        learning?.invalidate()
    }

    private func takeRetry(session token: UUID) -> Bool {
        guard session == token, retryRequested else { return false }
        retryRequested = false
        return true
    }

    private func finished(session token: UUID) {
        guard session == token else { return }
        learning?.finishObservation()
    }

    private func unavailable(session token: UUID, onStatus: (String) -> Void) {
        guard session == token else { return }
        learning?.invalidate()
        learning = nil
        onStatus("Dictionary learning unavailable: this app did not expose the delivered text through Accessibility.")
    }

    private func submit(_ entries: [DictionaryCorrection], bounds: CGRect?, session token: UUID,
                        isCurrent: @escaping @Sendable () async -> Bool) {
        guard session == token else { return }
        suggestions?.setAnchor(bounds)
        learning?.submit(entries, isCurrent: isCurrent, onValidationFailure: { [weak self] in
            guard let self, self.session == token else { return }
            self.retryRequested = true
        })
    }

    nonisolated static func readText(attribute: (String) -> CFTypeRef?) -> String? {
        DictionaryFieldReader.readText(attribute: attribute)
    }

    static func popupFrame(above anchor: CGRect, visibleFrame: CGRect, height: CGFloat = 54, width: CGFloat = 320) -> CGRect {
        let width = min(width, visibleFrame.width)
        let height = min(height, visibleFrame.height)
        let x = min(max(anchor.midX - width / 2, visibleFrame.minX), visibleFrame.maxX - width)
        let preferredY = anchor.maxY + 8
        let y = preferredY + height <= visibleFrame.maxY ? preferredY : anchor.minY - height - 8
        return CGRect(x: x, y: min(max(y, visibleFrame.minY), visibleFrame.maxY - height), width: width, height: height)
    }
}
