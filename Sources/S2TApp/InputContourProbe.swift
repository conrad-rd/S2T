import AppKit
import ApplicationServices
import SwiftUI
import S2TCore

@MainActor enum InputContourProbe {
    static func run() throws {
        try verifyReader()
        try verifyBlurJoinContinuity()
        try verifyRendering()
        try verifyJoinContinuity()
        print("PASS: preset attached-bar discovery, stale-bar rejection, stepped union, hidden panel geometry, clear interiors, atomic first appearance and full glow.")
        print("Generated fixtures and injected Accessibility objects only. Live site borders were not sampled.")
    }

    private static func verifyReader() throws {
        let pid: pid_t = 2_810_000
        let app = AXUIElementCreateApplication(pid)
        let elements = (1...7).map { AXUIElementCreateApplication(pid + pid_t($0)) }
        let frames = [CGRect(x: 0, y: 0, width: 1200, height: 900),
            CGRect(x: 116, y: 216, width: 658, height: 80),
            CGRect(x: 100, y: 200, width: 690, height: 130),
            CGRect(x: 750, y: 300, width: 28, height: 28),
            CGRect(x: 100, y: 200, width: 690, height: 158),
            CGRect(x: 120, y: 330, width: 650, height: 28),
            CGRect(x: 690, y: 334, width: 64, height: 20)]
        var barReads = 0, moveBar = false, detached = false
        var requested = Set<String>()
        let reader = FocusedInputReader(attribute: { element, name in
            requested.insert(name)
            if CFEqual(element, app) {
                if name == kAXFocusedWindowAttribute { return elements[0] }
                if name == kAXFocusedUIElementAttribute { return elements[1] }
                return nil
            }
            guard let id = elements.firstIndex(where: { CFEqual($0, element) }) else { return nil }
            switch name {
            case kAXRoleAttribute: return ["AXWindow", "AXTextArea", "AXGroup", "AXButton", "AXGroup", "AXGroup", "AXPopUpButton"][id] as CFString
            case kAXSubroleAttribute: return "" as CFString
            case kAXParentAttribute: return ([nil, 2, 4, 2, 0, 4, 5] as [Int?])[id].map { elements[$0] }
            case kAXPositionAttribute:
                var point = frames[id].origin
                if id == 5 {
                    barReads += 1
                    if moveBar && barReads > 1 { point.x += 20 }
                }
                return AXValueCreate(.cgPoint, &point)
            case kAXSizeAttribute:
                var size = frames[id].size; return AXValueCreate(.cgSize, &size)
            default: return nil
            }
        }, children: { element in
            guard let id = elements.firstIndex(where: { CFEqual($0, element) }) else { return [] }
            return (id == 2 ? [1, 3] : id == 4 ? (detached ? [2] : [2, 5]) : id == 5 ? [6] : []).map { elements[$0] }
        }, fallbackFocus: { _ in nil }, hitTest: { _, _ in nil },
        applicationBundleID: { _ in "com.t3tools.t3code" }, caretBounds: { _ in nil }, enableAccessibility: { _ in })
        try check(reader.read(pid: pid) == frames[4] && reader.contour?.bars.count == 1 && reader.usedPreset == .t3Code,
            "AX reader flattened or omitted the attached footer")
        barReads = 0; moveBar = true
        try check(reader.read(pid: pid) == nil, "AX reader accepted a bar that moved during sampling")
        moveBar = false; detached = true
        try check(reader.read(pid: pid) == frames[2] && reader.contour?.bars.isEmpty == true, "Removed bar survived the next read")
        detached = false
        let automatic = reader.read(pid: pid, disabledPresets: [InputTargetPreset.t3Code.rawValue])
        try check(automatic == frames[4] && reader.usedPreset == nil && reader.contour?.bars.count == 1,
            "Disabling the preset did not preserve automatic attachment detection")
        try check(requested.isDisjoint(with: [kAXValueAttribute, kAXSelectedTextAttribute, kAXSelectedTextRangeAttribute, kAXTitleAttribute]),
            "Attached-bar detection read field content")
    }

    private static func verifyRendering() throws {
        var header = InputContour(rect: CGRect(x: 40, y: 78, width: 736, height: 98), radius: 16, style: .circular)
        header.bars = [.init(rect: CGRect(x: 53, y: 40, width: 710, height: 38), radius: 16, style: .circular, corners: .top)]
        let headerPath = header.path
        var headerMoves = 0, headerCloses = 0
        headerPath.cgPath.applyWithBlock { item in
            if item.pointee.type == .moveToPoint { headerMoves += 1 }
            if item.pointee.type == .closeSubpath { headerCloses += 1 }
        }
        try check(headerMoves == 1 && headerCloses == 1, "Codex header produced an internal outline")
        let headerBoundary = ChromaInputBoundary(contour: header)
        try check(headerBoundary.distance(CGPoint(x: 408, y: 78)) <= 0
            && headerBoundary.distance(CGPoint(x: 46, y: 55)) > 0, "Codex header lost its inset or retained a join")
        let headerMap = InputOutlineBackdrop(contour: header, strength: 0.568).mask(size: CGSize(width: 816, height: 216))
        guard let headerBitmap = headerMap?.representations.first as? NSBitmapImageRep else { throw failure("Codex header native map missing") }
        for point in [CGPoint(x: 408, y: 59), CGPoint(x: 408, y: 78), CGPoint(x: 408, y: 120)] {
            let x = Int(point.x / 816 * CGFloat(headerBitmap.pixelsWide))
            let y = Int(point.y / 216 * CGFloat(headerBitmap.pixelsHigh))
            try check(headerBitmap.colorAt(x: x, y: y)?.alphaComponent == 0, "Codex header native blur entered its interior")
        }
        var contour = InputContour(rect: CGRect(x: 80, y: 80, width: 690, height: 130), radius: 20, style: .circular)
        contour.bars = [.init(rect: CGRect(x: 100, y: 210, width: 650, height: 28), radius: 14, style: .circular, corners: .bottom)]
        let size = CGSize(width: 850, height: 318)
        let path = contour.path
        var moves = 0, closes = 0
        path.cgPath.applyWithBlock { pointer in
            if pointer.pointee.type == .moveToPoint { moves += 1 }
            if pointer.pointee.type == .closeSubpath { closes += 1 }
        }
        try check(moves == 1 && closes == 1, "Input parts did not form one closed outer path")
        let interior = [CGPoint(x: 425, y: 140), CGPoint(x: 425, y: 210), CGPoint(x: 425, y: 225)]
        let cutouts = [CGPoint(x: 85, y: 224), CGPoint(x: 765, y: 224)]
        try check(interior.allSatisfy { path.contains($0) } && cutouts.allSatisfy { !path.contains($0) }, "Compound path is a surrounding rectangle or has an interior seam")
        let boundary = ChromaInputBoundary(contour: contour)
        try check(interior.allSatisfy { boundary.distance($0) <= 0 } && cutouts.allSatisfy { boundary.distance($0) > 0 }, "Blur distance disagrees with the stepped path")
        let outline = InputOutlineBackdrop(contour: contour, strength: 0.568)
        guard let mask = outline.mask(size: size), let bitmap = mask.representations.first as? NSBitmapImageRep else { throw failure("Missing compound native mask") }
        func alpha(_ point: CGPoint) -> CGFloat {
            bitmap.colorAt(x: Int(point.x / size.width * CGFloat(bitmap.pixelsWide)),
                y: Int(point.y / size.height * CGFloat(bitmap.pixelsHigh)))?.alphaComponent ?? -1
        }
        try check(interior.allSatisfy { alpha($0) == 0 } && cutouts.allSatisfy { alpha($0) > 0 }, "Native blur filled the composer or omitted the inset sides")
        var profile = GlowProfile(energy: 0.55, heights: [], sweepStrength: 0.568)
        profile.inputOutline = outline
        profile.response = .init(minimum: 0.259, maximum: 2.219)
        let request = ChromaFrameRequest(geometry: .input(contour), size: size, profile: profile, brightness: profile.speechGain, backdrop: true)
        let started = CACurrentMediaTime()
        let initial = ImageRenderer(content: PreparedChromaGlow(request: request).frame(width: size.width, height: size.height))
        initial.scale = 2
        guard let image = initial.cgImage else { throw failure("No initial stepped outline") }
        let elapsed = (CACurrentMediaTime() - started) * 1000
        let initialPixels = NSBitmapImageRep(cgImage: image)
        func initialAlpha(_ point: CGPoint) -> CGFloat { initialPixels.colorAt(x: Int(point.x * 2), y: Int(point.y * 2))?.alphaComponent ?? -1 }
        try check(initialAlpha(CGPoint(x: 99.5, y: 215)) == 0 && initialAlpha(CGPoint(x: 425, y: 238)) == 0,
            "A temporary footer stroke flashes before full rendering")
        try check(interior.allSatisfy { initialAlpha($0) == 0 } && cutouts.allSatisfy { initialAlpha($0) == 0 }, "Initial edge drew a seam or rectangular cutout")
        try check(elapsed < 100, "Compound edge blocks startup")
        print(String(format: "PASS: no temporary stepped stroke, initial frame %.2f ms.", elapsed))
        let capsule = InputContour(rect: CGRect(x: 80, y: 80, width: 690, height: 130), radius: 65, style: .circular)
        guard let capsuleEdge = ChromaAppearance.assets(geometry: .input(capsule), size: size)?.edge,
              let capsulePixels = capsuleEdge.representations.first as? NSBitmapImageRep else {
            throw failure("Missing capsule edge fixture")
        }
        try check(capsulePixels.pixelsWide >= Int(size.width * 4),
            "Input rim sampling is too coarse for a smooth one-point outline")
        let radius = 65.0, offset = 0.5, diagonal = (radius + offset) / sqrt(2)
        let perimeter = [CGPoint(x: 425, y: 79.5), CGPoint(x: 425, y: 210.5),
            CGPoint(x: 79.5, y: 145), CGPoint(x: 770.5, y: 145),
            CGPoint(x: 145 - diagonal, y: 145 - diagonal), CGPoint(x: 705 + diagonal, y: 145 - diagonal),
            CGPoint(x: 145 - diagonal, y: 145 + diagonal), CGPoint(x: 705 + diagonal, y: 145 + diagonal)]
        let perimeterAlpha = perimeter.map { point in
            capsulePixels.colorAt(x: Int(point.x / size.width * CGFloat(capsulePixels.pixelsWide)),
                y: Int(point.y / size.height * CGFloat(capsulePixels.pixelsHigh)))?.alphaComponent ?? 0
        }
        try check(perimeterAlpha.min() ?? 0 > 0.75 && (perimeterAlpha.max() ?? 1) - (perimeterAlpha.min() ?? 0) < 0.2,
            "Capsule outline is missing or uneven around its perimeter: \(perimeterAlpha)")
        guard ChromaFrame.render(request) != nil else { throw failure("No completed stepped glow") }
        let state = AppState(preview: true)
        state.phase = .recording
        let controller = InputOutlineWindowController(state: state)
        let target = InputOutlineTarget(contour: contour.offsetBy(dx: 200, dy: 300))
        let panel = controller.prepare(target: target)
        defer { panel.orderOut(nil) }
        guard let root = panel.contentView as? ProgressiveBackdropView,
              let actual = root.profile?.inputOutline?.contour,
              let host = root.subviews.first as? NSHostingView<InputOutline> else { throw failure("Missing compound hidden panel") }
        try check(actual.bars.count == 1 && host.rootView.layout.contour == actual && !panel.isVisible
            && panel.ignoresMouseEvents && !panel.canBecomeKey, "Hidden panel lost its bars or activation rules")
        try check(abs(panel.frame.minX + actual.bounds.minX - target.frame.minX) < 0.001
            && abs(panel.frame.maxY - actual.bounds.minY - target.frame.maxY) < 0.001, "Panel added a margin")
        _ = controller.prepare(field: CGRect(x: 300, y: 400, width: 690, height: 130), cornerRadius: 20, cornerStyle: .circular)
        try check(root.profile?.inputOutline?.contour.bars.isEmpty == true, "Single input retained an old footer")
        let cycle = InputGradientCycle.samples(contour: contour)
        try check(cycle.count > 512 && cycle.allSatisfy { $0.angle.isFinite && $0.distance.isFinite }, "Compound color cycle is invalid")
        var fixtureProfile = profile
        fixtureProfile.response.tuning = GlowTuning(backgroundBlur: 0.145, softness: 10, falloff: 1.9144,
            edgeBrightness: 2, edgeBlur: 0, edgeGlow: 0.5, edgeHeight: 0.0536, edgeOpacity: 1, bodyOpacity: 0.615)
        guard let fixture = ChromaFrame.render(.init(geometry: request.geometry, size: size, profile: fixtureProfile,
            brightness: profile.speechGain, backdrop: true)) else { throw failure("Missing tuned fixture") }
        for light in [false, true] {
            try GlowFixture.write(ZStack {
                Color(white: light ? 0.94 : 0.035)
                path.fill(Color(white: light ? 0.99 : 0.065))
                ChromaFrameCanvas(frame: fixture)
            }, size: size, name: "attached-footer-\(light ? "light" : "dark")")
        }
        let layout = InputOutlineLayout(); layout.contour = contour
        state.phase = .transcribing
        try GlowFixture.write(ZStack {
            Color(white: 0.035)
            path.fill(Color(white: 0.065))
            InputOutline(showsBackdrop: false, state: state, layout: layout, reduceMotionOverride: true, timeOverride: 1)
        }, size: size, name: "attached-footer-processing")
    }

    private static func verifyJoinContinuity() throws {
        // Inset a little less than the main corner radius: clipping away the
        // measured overlap would leave an open wedge at each rounded join.
        let nodes = [
            0: ComposerNode(id: 0, role: "AXTextArea", frame: CGRect(x: 116, y: 216, width: 658, height: 80), parent: 1),
            1: ComposerNode(id: 1, role: "AXGroup", frame: CGRect(x: 100, y: 200, width: 690, height: 130), parent: 3, children: [0, 2]),
            2: ComposerNode(id: 2, role: "AXButton", frame: CGRect(x: 750, y: 290, width: 32, height: 32), parent: 1),
            3: ComposerNode(id: 3, role: "AXGroup", frame: CGRect(x: 100, y: 200, width: 690, height: 158), parent: nil, children: [1, 4]),
            4: ComposerNode(id: 4, role: "AXGroup", frame: CGRect(x: 112, y: 315, width: 666, height: 43), parent: 3, children: [5]),
            5: ComposerNode(id: 5, role: "AXPopUpButton", frame: CGRect(x: 690, y: 334, width: 64, height: 20), parent: 4)]
        guard let target = InputTargetPreset.t3Code.resolve(editor: 0, nodes: nodes) else { throw failure("Missing inset footer target") }
        let contour = target.contour.offsetBy(dx: 80, dy: 80), size = CGSize(width: 850, height: 318)
        let path = contour.path, boundary = ChromaInputBoundary(contour: contour)
        let joinY = contour.main.rect.maxY - 0.5
        let connections = [CGPoint(x: contour.bars[0].rect.minX + 0.5, y: joinY),
                           CGPoint(x: contour.bars[0].rect.maxX - 0.5, y: joinY)]
        try check(connections.allSatisfy { path.contains($0) && boundary.distance($0) < 0 },
            "Clipping the footer overlap left gaps at its rounded joins")
        let outline = InputOutlineBackdrop(contour: contour)
        guard let map = outline.mask(size: size), let pixels = map.representations.first as? NSBitmapImageRep else { throw failure("Missing joined mask") }
        for point in connections {
            try check(pixels.colorAt(x: Int(point.x), y: Int(point.y))?.alphaComponent == 0,
                "Native blur enters the restored footer connection")
        }
        var profile = GlowProfile(energy: 0.55, heights: [], sweepStrength: 0.568)
        profile.inputOutline = outline
        profile.response = .init(minimum: 0.259, maximum: 2.219,
            tuning: .init(backgroundBlur: 0.145, softness: 10, falloff: 1.9144, edgeBrightness: 2,
                edgeBlur: 0, edgeGlow: 0.5, edgeHeight: 0.0536, edgeOpacity: 1, bodyOpacity: 0.615))
        guard let frame = ChromaFrame.render(.init(geometry: .input(contour), size: size, profile: profile,
            brightness: profile.speechGain, backdrop: true)) else { throw failure("Missing joined glow") }
        try GlowFixture.write(ZStack { Color(white: 0.035); path.fill(Color(white: 0.065)); ChromaFrameCanvas(frame: frame) },
            size: size, name: "t3-connected-footer")
        print("PASS: both rounded footer connections retain their measured overlap; color and native blur share a clear interior.")
    }

    private static func verifyBlurJoinContinuity() throws {
        var contour = InputContour(rect: CGRect(x: 80, y: 80, width: 690, height: 130), radius: 22, style: .circular)
        contour.bars = [.init(rect: CGRect(x: 92, y: 195, width: 666, height: 43), radius: 14, style: .circular, corners: .bottom)]
        let boundary = ChromaInputBoundary(contour: contour), size = CGSize(width: 850, height: 318)
        let outline = InputOutlineBackdrop(contour: contour)
        for right in [false, true] {
            let bands: [Double] = right ? [0, 0, 0, 0, 0, 0, 1] : [1, 0, 0, 0, 0, 0, 0]
            let distortion = GlowDistortion(bands: bands)
            let inverse = distortion.transform(in: size).inverted()
            let joinX = right ? contour.bars[0].rect.maxX : contour.bars[0].rect.minX
            for expansion in [0.3, 0.55, 1.0, 1.4] {
                guard let map = outline.mask(size: size, distortion: distortion, expansion: expansion, falloff: 1.9144),
                      let bitmap = map.representations.first as? NSBitmapImageRep else { throw failure("Missing moving blur fixture") }
                var samples = 0, minimum = 1.0
                for y in 198..<222 { for x in Int(joinX - 10)..<Int(joinX + 10) {
                    let point = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
                    guard boundary.distance(point) > 0.8, boundary.distance(point.applying(inverse)) < -1 else { continue }
                    samples += 1
                    minimum = min(minimum, bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0)
                } }
                print("Moving footer blur right=\(right), expansion=\(expansion): \(samples) exterior samples, minimum alpha \(minimum)")
                try check(samples > 0 && minimum > 0.5, "Moving the blur exposes a clear gap at the footer join")
                for point in [CGPoint(x: 425, y: 140), CGPoint(x: 425, y: 225)] {
                    try check(bitmap.colorAt(x: Int(point.x), y: Int(point.y))?.alphaComponent == 0, "Blur entered the input interior")
                }
            }
        }
    }

    private static func check(_ condition: Bool, _ message: String) throws { if !condition { throw failure(message) } }
    private static func failure(_ message: String) -> NSError { NSError(domain: "InputContour", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
