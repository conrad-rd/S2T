import AppKit
import SwiftUI
import S2TCore

@MainActor enum BrighterEdgeProbe {
    static func run() throws {
        let referenceRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("studies/appearance-reference/rendered")
        let display = GlowDisplay(frame: CGRect(x: 0, y: 0, width: 1080, height: 1080), safeTop: 106.44,
            topLeft: CGRect(x: 0, y: 973.56, width: 334.375, height: 106.44),
            topRight: CGRect(x: 745.625, y: 973.56, width: 334.375, height: 106.44))
        let notch = TopGlowLayout(display: display)
        let fixtures: [(String, ChromaAppearance.Geometry, CGSize, [(Int, Int)])] = [
            ("bottom", .bottom, CGSize(width: 1080, height: 1080), [(540, 1079), (540, 1074), (540, 1060), (540, 1030), (540, 950), (100, 1074)]),
            ("input", .input(CGRect(x: 70, y: 390, width: 940, height: 300), 115), CGSize(width: 1080, height: 1080), [(540, 386), (540, 380), (540, 370), (540, 350)]),
            ("notch", .notch(notch), notch.frame.size, [(540, 475), (540, 485), (540, 515), (540, 565)])
        ]
        for (name, geometry, size, points) in fixtures {
            try autoreleasepool {
                var profile = GlowProfile(energy: 0.5, heights: [3], sweepStrength: 1.3, reducedMotion: true,
                    response: .init(minimum: 1, maximum: 1))
                switch geometry {
                case .bottom: break
        case let .windowBottom(layout): profile.windowBottom = layout
                case let .withinInput(contour): profile.inputOutline = InputOutlineBackdrop(contour: contour, strength: 1.3, withinInput: true)
                case let .input(contour): profile.inputOutline = InputOutlineBackdrop(contour: contour, strength: 1.3)
                case let .notch(layout): profile.topLayout = layout
                }
                let request = ChromaFrameRequest(geometry: geometry, size: size, profile: profile, brightness: 1, backdrop: true)
                let expectedData = try Data(contentsOf: referenceRoot.appendingPathComponent("bottom-e-glow.png"))
                let expectedMapData = try Data(contentsOf: referenceRoot.appendingPathComponent("bottom-e-map.png"))
                guard let frame = ChromaFrame.render(request), let map = frame.radiusMap,
                      let mapBitmap = map.representations.first as? NSBitmapImageRep,
                      let expected = NSBitmapImageRep(data: expectedData),
                      let expectedMap = NSBitmapImageRep(data: expectedMapData) else {
                    throw failure("Missing native fields or approved E fixtures for \(name)")
                }
                let view = ChromaFrameCanvas(frame: frame).frame(width: size.width, height: size.height)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1
                guard let image = renderer.cgImage else { throw failure("Native Canvas did not render \(name)") }
                let actual = NSBitmapImageRep(cgImage: image)
                var maximumColorError = 0.0, maximumMapError = 0.0
                for (x, y) in points {
                    let point = name == "notch"
                        ? CGPoint(x: Double(x) + 0.5 - 540 + size.width / 2, y: Double(y) + 0.5 - 360)
                        : CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
                    let actualX = min(actual.pixelsWide - 1, Int(point.x / size.width * Double(actual.pixelsWide)))
                    let actualY = min(actual.pixelsHigh - 1, Int(point.y / size.height * Double(actual.pixelsHigh)))
                    let sampled = CGPoint(x: (Double(actualX) + 0.5) / Double(actual.pixelsWide) * size.width,
                                          y: (Double(actualY) + 0.5) / Double(actual.pixelsHigh) * size.height)
                    let depth = geometry.distance(sampled, size: size) / geometry.referenceScale * geometry.mode.fieldScale
                    let referenceX = name == "bottom" ? x : 540
                    let referenceY = name == "bottom" ? y : min(1079, max(0, Int(1080 - depth)))
                    guard let a = actual.colorAt(x: actualX, y: actualY)?.usingColorSpace(.sRGB),
                          let e = expected.colorAt(x: referenceX, y: referenceY)?.usingColorSpace(.sRGB) else { throw failure("Invalid color sample") }
                    // Compare premultiplied output, so transparent RGB noise cannot hide a visible difference.
                    let aa = a.alphaComponent, ea = e.alphaComponent
                    let values = [abs(aa - ea), abs(a.redComponent * aa - e.redComponent * ea),
                                  abs(a.greenComponent * aa - e.greenComponent * ea), abs(a.blueComponent * aa - e.blueComponent * ea)]
                    maximumColorError = max(maximumColorError, (values.max() ?? 0) * 255)
                    let mx = min(mapBitmap.pixelsWide - 1, Int(point.x / size.width * Double(mapBitmap.pixelsWide)))
                    let my = min(mapBitmap.pixelsHigh - 1, Int(point.y / size.height * Double(mapBitmap.pixelsHigh)))
                    let ma = mapBitmap.colorAt(x: mx, y: my)?.alphaComponent ?? -1
                    let me = expectedMap.colorAt(x: referenceX, y: referenceY)?.alphaComponent ?? -1
                    maximumMapError = max(maximumMapError, abs(ma - 0.6 * sqrt(max(0, me))) * 255)
                }
                guard maximumColorError <= (name == "bottom" ? 4 : 8), maximumMapError <= (name == "bottom" ? 2 : 3) else {
                    throw failure("\(name) differs from approved E colors or softened reference blur: color \(maximumColorError), map \(maximumMapError) out of 255")
                }
                if name != "bottom" {
                    let point = name == "input" ? CGPoint(x: 540, y: 540) : CGPoint(x: size.width / 2, y: 30)
                    guard (actual.colorAt(x: Int(point.x), y: Int(point.y))?.alphaComponent ?? -1) == 0,
                          (mapBitmap.colorAt(x: Int(point.x), y: Int(point.y))?.alphaComponent ?? -1) == 0 else {
                        throw failure("\(name) interior contains color or blur")
                    }
                }
                let root = ProgressiveBackdropView(frame: CGRect(origin: .zero, size: size))
                root.profile = profile
                let filter = root.layer?.sublayers?.first?.filters?.first as? NSObject
                let actualRadius = filter?.value(forKey: "inputRadius") as? Double ?? -1
                let expectedRadius = name == "input" ? 27.0 : 18.0
                guard abs(actualRadius - expectedRadius) < 0.000001 else { throw failure("\(name) blur radius differs from the strengthened nominal response") }
                try GlowFixture.write(view, size: size, name: "brighter-edge-\(name)")
                print("PASS: \(name) actual Canvas vs frozen Bottom PNG at matched fade depth, max color error \(String(format: "%.2f", maximumColorError))/255, map \(String(format: "%.2f", maximumMapError))/255, \(actualRadius)-point native blur.")
            }
        }
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "BrighterEdgeProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
