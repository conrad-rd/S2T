import AppKit

let alias = URL(fileURLWithPath: CommandLine.arguments[1])
let target = URL(fileURLWithPath: "/Applications", isDirectory: true)
if !CommandLine.arguments.contains("--verify") {
    let bookmark = try target.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
    try URL.writeBookmarkData(bookmark, to: alias)
    let folder = NSWorkspace.shared.icon(forFile: target.path)
    let icon = NSImage(size: NSSize(width: 512, height: 512), flipped: false) { _ in
        let side = 400.0 * 76.0 / 72.0
        let inset = (512.0 - side) / 2.0
        folder.draw(in: NSRect(x: inset, y: inset, width: side, height: side))
        return true
    }
    guard NSWorkspace.shared.setIcon(icon, forFile: alias.path, options: []) else {
        fatalError("Could not set the installer Applications icon")
    }
}
let bookmark = try URL.bookmarkData(withContentsOf: alias)
var stale = false
let resolved = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
guard resolved.standardizedFileURL == target.standardizedFileURL,
      try alias.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile == true else {
    fatalError("Applications shortcut must be a Finder alias to /Applications")
}
guard let attributes = try? FileManager.default.attributesOfItem(atPath: alias.path),
      (attributes[.size] as? NSNumber)?.intValue ?? 0 > 0 else {
    fatalError("Applications alias is empty")
}
print("Applications Finder alias resolves to /Applications without UI.")
