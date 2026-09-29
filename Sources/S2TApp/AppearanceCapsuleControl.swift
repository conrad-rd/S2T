import AppKit

@MainActor final class AppearanceIconGroup: SettingsChoiceControl {
    init(items: [(title: String, symbol: String)]) {
        super.init(items: items.map {
            SettingsChoiceItem(title: $0.title, image: NSImage(systemSymbolName: $0.symbol, accessibilityDescription: $0.title)?
                .withSymbolConfiguration(.init(pointSize: 16, weight: .medium)))
        }, label: "Appearance options")
    }
    required init?(coder: NSCoder) { nil }
}
