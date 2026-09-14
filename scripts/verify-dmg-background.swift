import AppKit

let data = Data(base64Encoded: CommandLine.arguments[1])!
guard let bookmark = CFURLCreateBookmarkDataFromAliasRecord(nil, data as CFData)?.takeRetainedValue() else {
    fatalError("Finder background alias is invalid")
}
var stale = false
let resolved = try URL(resolvingBookmarkData: bookmark as Data, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale)
let expected = URL(fileURLWithPath: CommandLine.arguments[2])
let actualID = try resolved.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject
let expectedID = try expected.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject
guard actualID != nil, actualID == expectedID,
      let image = NSImage(contentsOf: resolved), image.size == NSSize(width: 660, height: 750),
      image.representations.contains(where: { $0.pixelsWide == 660 && $0.pixelsHigh == 750 }),
      image.representations.contains(where: { $0.pixelsWide == 1320 && $0.pixelsHigh == 1500 }) else {
    fatalError("Finder background must resolve to this mounted image and decode at 660 × 750 points")
}
print("Native background resolution and Retina image decoding passed at the current mount.")
