import AppKit
import AVFoundation
import SwiftUI
import S2TCore

enum WritingPromptDictationPhase: Equatable {
    case idle
    case preparing
    case recording
    case transcribing

    var active: Bool { self != .idle }
    var label: String {
        switch self {
        case .idle: return "Dictate request"
        case .preparing: return "Starting microphone"
        case .recording: return "Stop and transcribe"
        case .transcribing: return "Transcribing request"
        }
    }
}

@MainActor protocol WritingPromptCapturing: AnyObject {
    func start(deviceUID: String) async throws
    func finish() async -> Data
    func cancel()
}

@MainActor final class LiveWritingPromptCapture: WritingPromptCapturing {
    private let microphone: Microphone
    private let requestAccess: () async -> Bool
    private var generation = UUID()

    init(microphone: Microphone = Microphone(), requestAccess: @escaping () async -> Bool = { await AVCaptureDevice.requestAccess(for: .audio) }) {
        self.microphone = microphone
        self.requestAccess = requestAccess
    }

    func start(deviceUID: String) async throws {
        let attempt = UUID()
        generation = attempt
        let allowed = await requestAccess()
        try Task.checkCancellation()
        guard generation == attempt else { throw CancellationError() }
        guard allowed else {
            throw ServiceError.message("Microphone access is off. Allow S2T in System Settings → Privacy & Security → Microphone.")
        }
        try await microphone.start(deviceUID: deviceUID)
        if Task.isCancelled || generation != attempt {
            if generation == attempt { microphone.cancel() }
            throw CancellationError()
        }
    }

    func finish() async -> Data { await microphone.finish() }
    func cancel() { generation = UUID(); microphone.cancel() }
}

final class WritingPromptTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var placeholder = "Describe the change…" { didSet { needsDisplay = true } }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        guard isReturn, !hasMarkedText() else { super.keyDown(with: event); return }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift) {
            insertNewline(nil)
        } else {
            onSubmit?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, window?.firstResponder !== self else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.placeholderTextColor
        ]
        placeholder.draw(at: NSPoint(x: textContainerInset.width + 1, y: textContainerInset.height), withAttributes: attributes)
    }

    @discardableResult
    func handleReturnForVerification(shift: Bool) -> Bool {
        if shift { insertNewline(nil); return false }
        onSubmit?(); return true
    }
}

struct WritingPromptTextEditor: NSViewRepresentable {
    @Binding var text: String
    let enabled: Bool
    let submit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let editor = WritingPromptTextView()
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 13)
        editor.textColor = .labelColor
        editor.insertionPointColor = .controlAccentColor
        editor.textContainerInset = NSSize(width: 2, height: 4)
        editor.textContainer?.lineFragmentPadding = 0
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.setAccessibilityLabel("AI editing request")
        editor.setAccessibilityIdentifier("writing.request")
        editor.onSubmit = submit
        scroll.documentView = editor
        context.coordinator.editor = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? WritingPromptTextView else { return }
        editor.isEditable = enabled
        editor.isSelectable = enabled
        editor.onSubmit = submit
        if editor.string != text {
            let selection = editor.selectedRange()
            editor.string = text
            editor.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        }
        editor.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var editor: WritingPromptTextView?
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let editor else { return }
            text.wrappedValue = editor.string
            editor.needsDisplay = true
        }
    }
}

struct WritingPromptComposer<ModelControls: View>: View {
    @Binding var text: String
    let enabled: Bool
    let busy: Bool
    let startedAt: Date?
    let modelTitle: String
    let dictationPhase: WritingPromptDictationPhase
    let submit: () -> Void
    let cancel: () -> Void
    let toggleDictation: () -> Void
    @ViewBuilder let modelControls: () -> ModelControls
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var canSubmit: Bool {
        enabled && !busy && !dictationPhase.active && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if busy {
                HStack(spacing: 8) {
                    if reduceMotion { Image(systemName: "hourglass") }
                    else { WritingActivityIndicator().frame(width: 14, height: 14) }
                    Text("Rewriting with \(modelTitle)…").lineLimit(1)
                    Spacer()
                    if let startedAt {
                        TimelineView(.periodic(from: startedAt, by: 1)) { context in
                            Text("\(max(0, Int(context.date.timeIntervalSince(startedAt))))s").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }.font(.callout).accessibilityIdentifier("writing.activity")
            }
            GroupBox {
                WritingPromptTextEditor(text: $text, enabled: enabled && !busy && !dictationPhase.active, submit: submit)
                    .frame(height: 52).padding(4)
            }
            HStack(spacing: 8) {
                modelControls()
                Spacer(minLength: 0)
                Button(action: toggleDictation) {
                    Image(systemName: dictationPhase == .recording ? "stop.fill" : "mic")
                }.disabled(!enabled || busy)
                    .help(dictationPhase.label).accessibilityLabel(dictationPhase.label)
                    .accessibilityIdentifier("writing.dictate")
                if dictationPhase == .preparing || dictationPhase == .transcribing {
                    ProgressView().controlSize(.small)
                }
                Button(action: busy ? cancel : submit) {
                    Label(busy ? "Stop" : "Suggest", systemImage: busy ? "stop.fill" : "arrow.up")
                }.disabled(!busy && !canSubmit).buttonStyle(.borderedProminent)
                    .help("Return sends; Shift-Return adds a line")
                    .accessibilityIdentifier("writing.improve")
            }
        }
    }
}

struct WritingActivityIndicator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSProgressIndicator {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isIndeterminate = true
        spinner.setAccessibilityLabel("Writing model is working")
        spinner.setAccessibilityIdentifier("writing.activity.spinner")
        spinner.startAnimation(nil)
        return spinner
    }
    func updateNSView(_ spinner: NSProgressIndicator, context: Context) { spinner.startAnimation(nil) }
    static func dismantleNSView(_ spinner: NSProgressIndicator, coordinator: ()) { spinner.stopAnimation(nil) }
}
