import AppKit
import SwiftUI
import S2TCore

struct WritingChangesView: View {
    let diff: WritingDiff
    @State private var change = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if diff.changeCount > 0 {
                HStack(spacing: 8) {
                    Text("Change \(change + 1) of \(diff.changeCount)").font(.caption).foregroundStyle(.secondary)
                    Button { change = max(0, change - 1) } label: { Image(systemName: "chevron.up") }
                        .disabled(change == 0).accessibilityLabel("Previous change")
                    Button { change = min(diff.changeCount - 1, change + 1) } label: { Image(systemName: "chevron.down") }
                        .disabled(change >= diff.changeCount - 1).accessibilityLabel("Next change")
                    Spacer()
                }.controlSize(.small)
            } else { Text("No changes to apply").font(.callout).foregroundStyle(.secondary).padding(.top, 10) }
            WritingDiffText(diff: diff, change: change)
        }.onChange(of: diff) { _, _ in change = 0 }
    }
}

struct WritingDiffText: NSViewRepresentable {
    let diff: WritingDiff
    let change: Int
    final class Coordinator {
        var diff: WritingDiff?
        var change = -1
        var ranges: [NSRange] = []
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let text = NSTextView(); text.isEditable = false; text.isSelectable = true; text.drawsBackground = false
        text.isVerticallyResizable = true; text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainerInset = NSSize(width: 0, height: 14)
        text.setAccessibilityLabel("Changes: additions underlined, deletions struck through")
        text.setAccessibilityIdentifier("writing.diff")
        scroll.documentView = text
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        if context.coordinator.diff != diff {
            let result = NSMutableAttributedString(string: "")
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 5
            let base: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
            var inChange = false
            context.coordinator.ranges = []
            for segment in diff.segments {
                var attributes = base
                switch segment.kind {
                case .same: inChange = false
                case .removed:
                    attributes[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.15)
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                case .inserted:
                    attributes[.backgroundColor] = NSColor.systemGreen.withAlphaComponent(0.15)
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                if segment.kind != .same, !inChange {
                    context.coordinator.ranges.append(NSRange(location: result.length, length: (segment.text as NSString).length))
                    inChange = true
                }
                result.append(NSAttributedString(string: segment.text, attributes: attributes))
            }
            text.textStorage?.setAttributedString(result)
            context.coordinator.diff = diff; context.coordinator.change = -1
        }
        if change != context.coordinator.change, context.coordinator.ranges.indices.contains(change) {
            text.scrollRangeToVisible(context.coordinator.ranges[change]); context.coordinator.change = change
        }
    }
}
