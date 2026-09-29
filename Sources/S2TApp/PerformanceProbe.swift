import AppKit
import SwiftUI
import S2TCore
import CryptoKit

@MainActor enum PerformanceProbe {
    static func run() {
        if CommandLine.arguments.contains("--dictation") { DictationPerformanceProbe.run(); return }
        if CommandLine.arguments.contains("--fields") { fields(); return }
        var times: [Double] = []
        for index in 0..<65 {
            let level = 0.5 + 0.45 * sin(Double(index) * 0.4)
            let view = BottomGlow(level: level, strength: 1, phase: .recording, timeOverride: Double(index) / 60)
                .frame(width: 1440, height: 240)
            let start = ProcessInfo.processInfo.systemUptime
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            guard renderer.cgImage != nil else { fatalError("Could not render glow benchmark") }
            if index >= 5 { times.append((ProcessInfo.processInfo.systemUptime - start) * 1000) }
        }
        times.sort()
        print(String(format: "60 frames, 1440×240, median %.2f ms, p95 %.2f ms", times[30], times[57]))
        var baseline = 0.0
        let oldTarget = (20 * log10(0.05) + 55) / 48
        var oldFrames = 0
        while baseline < oldTarget * 0.9 {
            baseline = baseline * 0.25 + oldTarget * 0.75
            oldFrames += 1
        }
        var envelope = AudioEnvelope()
        var settled = AudioEnvelope()
        let target = settled.update(rms: 0.05, peak: 0.1, duration: 1)
        var newFrames = 0
        while envelope.level < target * 0.9 {
            _ = envelope.update(rms: 0.05, peak: 0.1, duration: 256.0 / 48000)
            newFrames += 1
        }
        print(String(format: "Synthetic level-step 90%% attack: old %.2f ms; new %.2f ms. Excludes hardware and display latency.", Double(oldFrames) * 1024 / 48, Double(newFrames) * 256 / 48))
    }
    private static func fields() {
        let display = GlowDisplay(frame: CGRect(x: 0, y: 0, width: 1800, height: 1169), safeTop: 32,
            topLeft: CGRect(x: 0, y: 1137, width: 780, height: 32),
            topRight: CGRect(x: 1020, y: 1137, width: 780, height: 32))
        let notch = TopGlowLayout(display: display)
        let fixtures: [(String, ChromaAppearance.Geometry, CGSize)] = [
            ("bottom", .bottom, CGSize(width: 1800, height: GlowProfile.extent)),
            ("notch", .notch(notch), notch.frame.size),
            ("input", .input(CGRect(x: 200, y: 200, width: 600, height: 120), 24), CGSize(width: 1000, height: 520))
        ]
        for (name, geometry, size) in fixtures {
            for moving in [false, true] {
                var times: [Double] = []
                var digest = SHA256()
                for index in 0..<24 {
                    autoreleasepool {
                        let energy = moving ? 0.1 + Double(index % 8) / 10 : 0.0
                        let distortion = GlowDistortion(bands: moving ? [0.1, 0.2, energy, 0.4, 0.2, 0.1, 0.1] : [])
                        let start = ProcessInfo.processInfo.systemUptime
                        let assets = ChromaAppearance.assets(geometry: geometry, size: size)!
                        let images = ChromaExpansion.images([assets.color, assets.edge], geometry: geometry,
                            size: size, factor: 0.3 + energy * 1.7)!
                        var exterior = Path(CGRect(origin: .zero, size: size))
                        if case let .input(contour) = geometry { exterior.addPath(InputOutlineBackdrop(contour: contour).path) }
                        let map = ChromaAppearance.radiusMap(geometry: geometry, size: size, distortion: distortion,
                            exterior: exterior, expansion: 0.3 + energy * 1.7)!
                        if index >= 4 { times.append((ProcessInfo.processInfo.systemUptime - start) * 1000) }
                        if index < 8 {
                            for image in images + [map] {
                                let bitmap = image.representations.first as! NSBitmapImageRep
                                digest.update(data: Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh))
                            }
                        }
                    }
                }
                times.sort()
                let hash = digest.finalize().map { String(format: "%02x", $0) }.joined()
                print(String(format: "%@ %@ median %.2f ms p95 %.2f ms", name, moving ? "speech" : "quiet", times[10], times[19]))
                print("generated-pixels " + hash)
            }
        }
    }

}
