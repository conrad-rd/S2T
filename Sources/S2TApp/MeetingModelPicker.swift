import AppKit
import SwiftUI

struct MeetingModelPicker: NSViewRepresentable {
    let label: String
    let identifier: String
    let choices: [(id: String, title: String)]
    @Binding var selection: String
    var includeUnlistedSelection = true
    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let popup = NSPopUpButton()
        SettingsFormStyle.popup(popup)
        popup.menu?.autoenablesItems = false
        popup.setAccessibilityLabel(label)
        popup.setAccessibilityIdentifier(identifier)
        popup.identifier = .init(identifier)
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.select(_:))
        popup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return popup
    }
    func updateNSView(_ popup: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        let missingSelection = !choices.contains(where: { $0.id == selection })
        let values = missingSelection ? [(selection, includeUnlistedSelection ? selection : "Current provider hidden")] + choices : choices
        if popup.itemArray.compactMap({ $0.representedObject as? String }) != values.map(\.id) || popup.itemTitles != values.map(\.title) {
            popup.removeAllItems()
            for value in values {
                let item = NSMenuItem(title: value.title, action: nil, keyEquivalent: "")
                item.representedObject = value.id
                popup.menu?.addItem(item)
            }
        }
        if missingSelection { popup.item(at: 0)?.isEnabled = includeUnlistedSelection }
        popup.selectItem(at: values.firstIndex { $0.id == selection } ?? 0)
        popup.isEnabled = context.environment.isEnabled
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 280, height: 32)
    }
    final class Coordinator: NSObject {
        var selection: Binding<String>
        init(selection: Binding<String>) { self.selection = selection }
        @objc func select(_ sender: NSPopUpButton) {
            if let value = sender.selectedItem?.representedObject as? String { selection.wrappedValue = value }
        }
    }
}
