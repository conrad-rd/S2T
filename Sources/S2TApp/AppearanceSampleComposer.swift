import AppKit
import SwiftUI
import S2TCore

struct AppearanceSampleComposer: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "plus").font(.system(size: 23, weight: .light)).accessibilityHidden(true)
            AppearanceSampleField(text: $text)
                .frame(minWidth: 150)
            HStack(spacing: 5) {
                Text("6")
                Text("Pro").foregroundStyle(.secondary)
                Image(systemName: "chevron.down").font(.system(size: 10))
            }
            .font(.system(size: 15))
            .accessibilityHidden(true)
            Image(systemName: "mic").font(.system(size: 18)).accessibilityHidden(true)
            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(nsColor: .textBackgroundColor))
                .frame(width: 32, height: 32)
                .background(Color.primary, in: Circle())
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 17)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor), in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1.4)
                .allowsHitTesting(false)
        }
    }
}

struct AppearanceSampleField: NSViewRepresentable {
    @Binding var text: String
    var processing: InputProcessingBackdrop? = nil
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeNSView(context: Context) -> AppearanceSampleTextField {
        let field = AppearanceSampleTextField()
        field.identifier = NSUserInterfaceItemIdentifier("appearance.sample.input")
        field.placeholderString = "Ask ChatGPT"
        field.font = .systemFont(ofSize: 18)
        field.isBordered = false
        field.drawsBackground = false
        field.appearance = NSAppearance(named: .darkAqua)
        field.textColor = NSColor(white: 0.93, alpha: 1)
        field.focusRingType = .none
        field.lineBreakMode = .byClipping
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Sample message")
        field.setAccessibilityHelp("Type here to try the input glow. This text stays in the preview.")
        return field
    }
    func updateNSView(_ field: AppearanceSampleTextField, context: Context) {
        context.coordinator.text = $text
        field.processing = processing
        if field.stringValue != text { field.stringValue = text }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}


final class AppearanceSampleTextField: NSTextField {
    var processing: InputProcessingBackdrop? { didSet { updateProcessing() } }
    private let blurSource = ProgressiveBackdropView()

    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        updateProcessing()
    }

    private func updateProcessing() {
        guard let processing, bounds.width > 0, bounds.height > 0 else {
            layer?.filters = nil
            return
        }
        wantsLayer = true
        layerUsesCoreImageFilters = false
        blurSource.setFrameSize(bounds.size)
        var profile = GlowProfile(energy: 1, heights: [])
        profile.processingInput = processing
        blurSource.profile = profile
        layer?.filters = blurSource.layer?.sublayers?.first?.filters
    }
}
