import AppKit
import SwiftUI
import S2TCore

@MainActor enum EdgeAppearanceProbe {
    static func verify(_ base: ChromaFrame) throws {
        let original = base.request
        try verifyMainOpacity(base)
        func make(_ tuning: GlowTuning) throws -> ChromaFrame {
            var profile = original.profile
            profile.response.tuning = tuning
            guard let frame = ChromaFrame.render(.init(geometry: original.geometry, size: original.size,
                profile: profile, brightness: original.brightness, backdrop: true)) else { throw failure("Missing edge frame") }
            guard bytes(frame.images[0]) == bytes(base.images[0]),
                  frame.radiusMap.map(bytes) == base.radiusMap.map(bytes) else {
                throw failure("An edge control changed the base glow or background blur")
            }
            return frame
        }
        let baseline = try rendered(base)
        for (name, tuning) in [("blur", GlowTuning(edgeBlur: 8)), ("glow", GlowTuning(edgeGlow: 1.5)),
            ("brightness", GlowTuning(edgeBrightness: 1.6)), ("height", GlowTuning(edgeHeight: 0.5)),
            ("opacity", GlowTuning(edgeOpacity: 0.25))] {
            let image = try rendered(make(tuning))
            guard difference(image, baseline) > 3 else { throw failure("Edge \(name) has no visible effect") }
        }
        let dimmed = try rendered(make(.init(edgeBrightness: 0.5)))
        let translucent = try rendered(make(.init(edgeOpacity: 0.5)))
        guard difference(dimmed, translucent) > 3 else { throw failure("Brightness and opacity are the same adjustment") }
        let hidden = try rendered(make(.init(edgeOpacity: 0)))
        let hiddenWithEffects = try rendered(make(.init(edgeBrightness: 2, edgeBlur: 12, edgeGlow: 2, edgeHeight: 1, edgeOpacity: 0)))
        guard difference(hidden, hiddenWithEffects) <= 2 else { throw failure("Zero edge opacity leaves its halo visible") }

        let zeroHeight = try rendered(make(.init(edgeBlur: 12, edgeGlow: 2, edgeHeight: 0)))
        guard difference(hidden, zeroHeight) <= 2 else { throw failure("Zero edge height leaves the rim or halo visible") }

        var depths: [Double] = [], widths: [Double] = []
        for height in [0.25, 0.5, 0.75, 1] {
            let frame = try make(.init(edgeHeight: height))
            let image = bitmap(frame.images[1])
            let x: Double
            switch original.geometry {
            case .bottom, .windowBottom: x = original.size.width / 2
            case let .notch(layout): x = Double(layout.notch?.midX ?? CGFloat(original.size.width / 2))
            case let .input(contour), let .withinInput(contour): x = contour.bounds.midX
            }
            let column = min(image.pixelsWide - 1, Int(x / original.size.width * Double(image.pixelsWide)))
            var weighted = 0.0, total = 0.0
            for row in 0..<image.pixelsHigh {
                let point = CGPoint(x: x, y: (Double(row) + 0.5) / Double(image.pixelsHigh) * original.size.height)
                let distance = original.geometry.distance(point, size: original.size)
                guard distance >= 0 else { continue }
                let alpha = image.colorAt(x: column, y: row)?.alphaComponent ?? 0
                weighted += distance * alpha
                total += alpha
            }
            guard total > 0 else { throw failure("Height erased the edge") }
            depths.append(weighted / total)
            widths.append(total * original.size.height / Double(image.pixelsHigh))
        }
        // A subpixel rim can stay in the same texel while its coverage increases.
        guard zip(depths, depths.dropFirst()).allSatisfy({ $0 <= $1 }),
              zip(widths, widths.dropFirst()).allSatisfy({ $0 < $1 }) else {
            throw failure("Edge height does not widen smoothly: depths \(depths), integrated widths \(widths)")
        }
        let maximum = try make(.init(edgeBrightness: 2, edgeBlur: 12, edgeGlow: 2, edgeHeight: 1))
        let renderer = ImageRenderer(content: ChromaFrameCanvas(frame: maximum).frame(width: original.size.width, height: original.size.height))
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { throw failure("Cannot render maximum edge settings") }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let inside: CGPoint?
        switch original.geometry {
        case .bottom, .windowBottom: inside = nil
        case let .input(contour), let .withinInput(contour): inside = CGPoint(x: contour.bounds.midX, y: contour.bounds.minY + 2)
        case let .notch(layout): inside = layout.notch.map { CGPoint(x: $0.midX, y: $0.midY) }
        }
        if let inside {
            guard bitmap.colorAt(x: Int(inside.x), y: Int(inside.y))?.alphaComponent == 0 else {
                throw failure("Edge effects entered the input or notch interior")
            }
        }
        print("PASS: independent edge blur/glow/brightness/height/opacity; unchanged base and native map; ordered outward height, opacity zero, clear interior. Depths \(depths.map { String(format: "%.2f", $0) }).")
    }

    private static func verifyMainOpacity(_ base: ChromaFrame) throws {
        func frame(_ opacity: Double, edge: Double = 0) throws -> ChromaFrame {
            var profile = base.request.profile
            profile.response.tuning.bodyOpacity = opacity
            profile.response.tuning.edgeOpacity = edge
            guard let frame = ChromaFrame.render(.init(geometry: base.request.geometry, size: base.request.size,
                profile: profile, brightness: 1, backdrop: true)),
                  bytes(frame.images[1]) == bytes(base.images[1]),
                  frame.radiusMap.map(bytes) == base.radiusMap.map(bytes) else {
                throw failure("Main opacity changed the light-sweep image or native blur map")
            }
            return frame
        }
        func alpha(_ frame: ChromaFrame) throws -> Double {
            let renderer = ImageRenderer(content: ChromaFrameCanvas(frame: frame)
                .frame(width: frame.request.size.width, height: frame.request.size.height))
            renderer.scale = 1
            guard let image = renderer.cgImage else { throw failure("Missing main-opacity rendering") }
            let bitmap = NSBitmapImageRep(cgImage: image)
            var total = 0.0
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                    total += Double(bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0)
                }
            }
            return total
        }
        let full = try alpha(frame(1)), half = try alpha(frame(0.5)), zero = try alpha(frame(0))
        guard full > 0, abs(half / full - 0.5) < 0.03, zero == 0,
              try alpha(frame(0, edge: 1)) > 0,
              difference(try rendered(frame(1, edge: 1)), try rendered(frame(0.5, edge: 1))) > 5 else {
            throw failure("Main opacity did not visibly change the actual Canvas independently of the light sweep")
        }
        print(String(format: "PASS: actual main-glow opacity 100/50/0 percent, half/full rendered alpha %.3f; light sweep remains visible and its image and native blur are unchanged.", half / full))
    }

    static func verifySlider(state: AppState, controls: AppearanceWindowController) async throws {
        let saved = state.glowTuning
        defer { state.glowTuning = saved; controls.selectSection(.glow) }
        state.glowTuning = .init(edgeBlur: 12, edgeGlow: 2)
        controls.selectSection(.edge)
        controls.reveal(.edgeHeight)
        guard let slider = controls.sliders[.edgeHeight], slider.minValue == 0, slider.maxValue == 1 else { throw failure("Missing edge height slider") }
        var actions: [Double] = []
        for height in [0, 0.25, 0.5, 0.75, 1] {
            let start = CACurrentMediaTime()
            slider.doubleValue = height
            slider.sendAction(slider.action, to: slider.target)
            actions.append((CACurrentMediaTime() - start) * 1000)
            try await Task.sleep(nanoseconds: 8_000_000)
        }
        let geometry = AppearancePreviewScene.geometry(state.glowAppearance)
        func received() -> Bool {
            let request = controls.preview.renderer.frame?.request
            return request?.geometry == geometry && request?.profile.response.tuning.edgeHeight == 1
        }
        let deadline = CACurrentMediaTime() + 10
        while !received(), CACurrentMediaTime() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        guard received(), actions.max()! < 16.7 else { throw failure("Edge slider blocked or did not reach the mounted preview: \(actions)") }
        print(String(format: "PASS: %@ edge-height drag with maximum blur/glow, max native action %.3f ms, latest frame reached the preview.", state.glowAppearance.rawValue, actions.max()!))
    }

    private static func bitmap(_ image: NSImage) -> NSBitmapImageRep {
        if let bitmap = image.representations.first as? NSBitmapImageRep { return bitmap }
        return NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
    }
    private static func bytes(_ image: NSImage) -> Data {
        let bitmap = bitmap(image)
        return Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }
    private static func rendered(_ frame: ChromaFrame) throws -> Data {
        let renderer = ImageRenderer(content: ChromaFrameCanvas(frame: frame).frame(width: frame.request.size.width, height: frame.request.size.height))
        renderer.scale = 1
        guard let image = renderer.cgImage, let data = image.dataProvider?.data else { throw failure("Missing rendered edge") }
        return data as Data
    }
    private static func difference(_ a: Data, _ b: Data) -> Int {
        zip(a, b).map { abs(Int($0) - Int($1)) }.max() ?? 0
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "EdgeAppearanceProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
