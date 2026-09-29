import AppKit
import CryptoKit
import S2TCore
import SwiftUI

@MainActor enum DictationPerformanceProbe {
    static func run() {
        if CommandLine.arguments.contains("--composition") { composition(); return }
        for size in [CGSize(width: 1000, height: 700), CGSize(width: 1900, height: 1800)] {
            let contour = InputContour(rect: CGRect(x: 100, y: size.height - 400,
                width: size.width - 200, height: 260), radius: 28)
            let geometry = ChromaAppearance.Geometry.withinInput(contour)
            var stages = Array(repeating: [Double](), count: 3)
            var digest = SHA256()
            for index in 0..<28 {
                autoreleasepool {
                    let energy = 0.3 + Double(index % 8) * 0.06
                    var profile = GlowProfile(energy: energy, heights: [3])
                    profile.inputOutline = InputOutlineBackdrop(contour: contour, withinInput: true)
                    if CommandLine.arguments.contains("--tuned") {
                        profile.inputOutline?.strength = 1.3
                        profile.response = GlowResponseSettings(minimum: 0.6255787037037037, maximum: 1.4270833333333333,
                            tuning: GlowTuning(backgroundBlur: 0.2016767492363498, softness: 12, falloff: 2,
                                edgeBrightness: 2, edgeBlur: 0.97646958885491, edgeGlow: 2, edgeHeight: 0.09180682976554534,
                                inputSizeEnabled: true, inputMinimumSize: 0.5, inputMaximumSize: 0.9947554976851851))
                    }
                    profile.distortion = GlowDistortion(bands: [0.1, 0.2, energy, 0.4, 0.2, 0.1, 0.1])
                    profile.response.tuning = profile.response.tuning.forInput(size: contour.bounds.size)
                    let start = CACurrentMediaTime()
                    let assets = ChromaAppearance.assets(geometry: geometry, size: size, falloff: profile.response.tuning.falloff)!
                    let assetEnd = CACurrentMediaTime()
                    let images = ChromaAppearance.expandedImages(assets: assets, geometry: geometry,
                        size: size, expansion: profile.speechExpansion,
                        edgeHeight: profile.response.tuning.edgeHeight, softness: profile.response.tuning.softness)!
                    let colorEnd = CACurrentMediaTime()
                    let map = GlowBackdrop.mask(profile: profile, size: size)!
                    let end = CACurrentMediaTime()
                    if index >= 4 {
                        stages[0].append((assetEnd - start) * 1000)
                        stages[1].append((colorEnd - assetEnd) * 1000)
                        stages[2].append((end - colorEnd) * 1000)
                    }
                    if index >= 4 && index < 12 {
                        for image in images + [map] {
                            let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
                            digest.update(data: cg.dataProvider!.data! as Data)
                        }
                    }
                }
            }
            let totals = stages[0].indices.map { stages[0][$0] + stages[1][$0] + stages[2][$0] }.sorted()
            print("Within Input \(Int(size.width))x\(Int(size.height)), 24 changing speech frames")
            for (name, samples) in zip(["assets", "expanded color", "native map"], stages) {
                let sorted = samples.sorted()
                print(String(format: "%@ median %.3f ms p95 %.3f ms", name, sorted[12], sorted[22]))
            }
            print(String(format: "total median %.3f ms p95 %.3f ms", totals[12], totals[22]))
            print("generated-pixels " + digest.finalize().map { String(format: "%02x", $0) }.joined())
        }
        print("Generated production fields only. No screen, microphone, clipboard, or focus access. Excludes displayed frame rate and WindowServer composition.")
    }

    private static func composition() {
        for size in [CGSize(width: 1000, height: 700), CGSize(width: 1900, height: 1800)] {
            let contour = InputContour(rect: CGRect(x: 100, y: size.height - 400,
                width: size.width - 200, height: 260), radius: 28)
            var times: [Double] = []
            var digest = SHA256()
            for index in 0..<14 {
                autoreleasepool {
                    var profile = GlowProfile(energy: 0.3 + Double(index % 8) * 0.06, heights: [3])
                    profile.inputOutline = InputOutlineBackdrop(contour: contour, strength: 1.3, withinInput: true)
                    profile.response = GlowResponseSettings(minimum: 0.6255787037037037, maximum: 1.4270833333333333,
                        tuning: GlowTuning(backgroundBlur: 0.2016767492363498, softness: 12, falloff: 2,
                            edgeBrightness: 2, edgeBlur: 0.97646958885491, edgeGlow: 2, edgeHeight: 0.09180682976554534,
                            inputSizeEnabled: true, inputMinimumSize: 0.5, inputMaximumSize: 0.9947554976851851))
                    profile.response.tuning = profile.response.tuning.forInput(size: contour.bounds.size)
                    let request = ChromaFrameRequest(geometry: .withinInput(contour), size: size,
                        profile: profile, brightness: profile.speechGain, backdrop: false)
                    let frame = ChromaFrame.render(request)!
                    let started = CACurrentMediaTime()
                    let renderer = ImageRenderer(content: ChromaFrameCanvas(frame: frame, cycleTime: Double(index) / 60)
                        .frame(width: size.width, height: size.height))
                    renderer.scale = 2
                    let image = renderer.cgImage!
                    let pixels = image.dataProvider!.data! as Data
                    let elapsed = (CACurrentMediaTime() - started) * 1000
                    if index >= 2 { times.append(elapsed) }
                    if index >= 2 && index < 4 { digest.update(data: pixels) }
                }
            }
            times.sort()
            print(String(format: "Within Input %.0fx%.0f, 2x authored Canvas composition: median %.3f ms, p95 %.3f ms",
                size.width, size.height, times[6], times[11]))
            print("composed-pixels " + digest.finalize().map { String(format: "%02x", $0) }.joined())
        }
        print("Generated images through the production Canvas. Includes bitmap output, excludes live WindowServer composition and displayed FPS. No screen capture.")
    }
}
