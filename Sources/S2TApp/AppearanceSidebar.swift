import AppKit
import S2TCore

@MainActor final class AppearanceSidebarController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    let table = NSTableView()
    let logo = NSImageView()
    var onSelection: ((GlowAppearance) -> Void)?
    var onAPIKeys: (() -> Void)?
    var onModels: (() -> Void)?

    override func loadView() {
        let background = NSVisualEffectView()
        background.material = .sidebar
        background.blendingMode = .behindWindow
        view = background
        logo.image = NSImage(named: "MenuBar")
        logo.contentTintColor = .labelColor
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.imageAlignment = .alignLeft
        logo.identifier = NSUserInterfaceItemIdentifier("settings.logo")
        logo.setAccessibilityLabel("S2T")
        logo.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(logo)
        NSLayoutConstraint.activate([
            logo.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 22),
            logo.topAnchor.constraint(equalTo: background.topAnchor, constant: 62),
            logo.widthAnchor.constraint(equalToConstant: 158),
            logo.heightAnchor.constraint(equalToConstant: 72)
        ])
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 7),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -7),
            scroll.topAnchor.constraint(equalTo: logo.bottomAnchor, constant: 24),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -18)
        ])
        table.identifier = NSUserInterfaceItemIdentifier("appearance.sidebar")
        table.style = .sourceList
        table.backgroundColor = .clear
        table.headerView = nil
        table.rowHeight = 34
        table.intercellSpacing = NSSize(width: 0, height: 3)
        table.allowsEmptySelection = false
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("mode")))
        table.delegate = self
        table.dataSource = self
        table.setAccessibilityLabel("Settings navigation")
        scroll.documentView = table
    }

    var keysRow: Int { modelsRow + 1 }
    let modelsRow = GlowAppearance.allCases.count + 2
    func row(for mode: GlowAppearance) -> Int { GlowAppearance.allCases.firstIndex(of: mode)! + 1 }
    private func isGroup(_ row: Int) -> Bool { row == 0 || row == GlowAppearance.allCases.count + 1 }
    func numberOfRows(in tableView: NSTableView) -> Int { GlowAppearance.allCases.count + 4 }
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { isGroup(row) }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { !isGroup(row) }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 34 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = AppearanceSidebarCell()
        let title: String
        if isGroup(row) { title = row == 0 ? "Appearance" : "Dictation" }
        else if row == modelsRow { title = "Models" }
        else if row == keysRow { title = "API keys" }
        else { title = ["Bottom", "Around Notch", "Around Input", "Bezel"][row - 1] }
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: isGroup(row) ? 11 : 13, weight: isGroup(row) ? .semibold : .regular)
        label.textColor = isGroup(row) ? .secondaryLabelColor : .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        let leading: NSLayoutXAxisAnchor
        if isGroup(row) {
            leading = cell.leadingAnchor
        } else {
            let icon = AppearanceIconView(symbol: row == keysRow ? "key" : "cpu", color: row == keysRow ? .systemOrange : .systemIndigo, size: 24)
            if row != modelsRow && row != keysRow { icon.configure(mode: GlowAppearance.allCases[row - 1]) }
            cell.addSubview(icon)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 5),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            leading = icon.trailingAnchor
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leading, constant: isGroup(row) ? 5 : 8),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        cell.setAccessibilityLabel(title)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if table.selectedRow == keysRow { onAPIKeys?(); return }
        if table.selectedRow == modelsRow { onModels?(); return }
        let index = table.selectedRow - 1
        guard GlowAppearance.allCases.indices.contains(index) else { return }
        onSelection?(GlowAppearance.allCases[index])
    }

    func select(_ mode: GlowAppearance) {
        loadViewIfNeeded()
        let selected = row(for: mode)
        guard table.selectedRow != selected else { return }
        table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
    }

    func selectModels() {
        loadViewIfNeeded()
        table.selectRowIndexes(IndexSet(integer: modelsRow), byExtendingSelection: false)
    }


}

final class AppearanceIconView: NSView {
    private let glyph = NSImageView()
    private var color: NSColor
    override var allowsVibrancy: Bool { false }
    init(symbol: String, color: NSColor, size: CGFloat) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        translatesAutoresizingMaskIntoConstraints = false
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        glyph.symbolConfiguration = .init(pointSize: size * 0.58, weight: .medium)
        glyph.contentTintColor = .white
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size), heightAnchor.constraint(equalToConstant: size),
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor), glyph.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { nil }
    func configure(mode: GlowAppearance) {
        let index = GlowAppearance.allCases.firstIndex(of: mode)!
        let symbol = ["dock.rectangle", "macbook", "rectangle.and.pencil.and.ellipsis", "sidebar.right"][index]
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        color = [.systemPurple, .systemBlue, .systemPink, .systemGray][index]
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.width * 0.23, yRadius: bounds.width * 0.23)
        NSGradient(starting: color.blended(withFraction: 0.12, of: .white)!, ending: color)?.draw(in: path, angle: -90)
        NSColor.white.withAlphaComponent(0.18).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}


private final class AppearanceSidebarCell: NSTableCellView {
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            textField?.textColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .labelColor
        }
    }
}
