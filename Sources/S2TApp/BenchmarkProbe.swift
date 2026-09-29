import AppKit
import ApplicationServices
import SwiftUI
import Combine
import S2TCore
import S2TBenchCore

@MainActor enum BenchmarkProbe {
    static func run() async throws {
        func argument(_ name: String, fallback: String) -> String {
            guard let i = CommandLine.arguments.firstIndex(of: name), CommandLine.arguments.count > i + 1 else { return fallback }
            return CommandLine.arguments[i + 1]
        }
        let suite = argument("--bench-suite", fallback: "inputs")
        let seconds = min(60, max(2, Double(argument("--seconds", fallback: "10")) ?? 10))
        let seed = UInt64(argument("--seed", fallback: "42")) ?? 42
        let repeats = min(20, max(1, Int(argument("--repeats", fallback: "3")) ?? 3))
        emit(BenchResult(suite: "environment", name: BuildIdentity.menuLabel, status: .passed,
            detail: "Production engine. Synthetic data and generated offscreen drawing. No screen, microphone, real field, clipboard or credential capture.",
            metrics: ["engine_build": Double(BuildIdentity.number) ?? 0]))
        switch suite {
        case "animations":
            for mode in ["Bottom", "Around Notch", "Around Input", "Within Input"] {
                for moving in [false, true] { try await frames(mode: mode, resizing: moving, seconds: seconds, seed: seed) }
            }
        case "inputs":
            for repetition in 0..<repeats {
                await check("Universal focus and secure-field rejection", suite: suite) { try InputUniversalProbe.run() }
                await check("Growth, shrink and stale geometry", suite: suite) { try InputTrackingProbe.run() }
                await check("Seeded hostile metadata \(repetition + 1)", suite: suite) { try inputStorm(seed: seed &+ UInt64(repetition), count: 400) }
            }
            await check("Compound contours and interior exclusion", suite: suite) { try InputContourProbe.run() }
            await check("Around Input targeting and hidden panels", suite: suite) { try await InputOutlineProbe.run() }
            await check("Within Input geometry and controls", suite: suite) { try WithinInputProbe.run() }
            await check("Missing fields, window changes and recovery", suite: suite) { try await InputWindowFallbackProbe.run() }
        case "reliability":
            await check("Credential routing, stale key checks and errors", suite: suite) { try await APIKeyProbe.run() }
            await check("Model routing and dictionary isolation", suite: suite) { try ModelSettingsProbe.run() }
            await check("Clipboard encryption, persistence and cancellation", suite: suite) { try await ClipboardProbe.run() }
            await check("Permissions, shortcut races and cancellation", suite: suite) { try await OnboardingProbe.run() }
            await check("Native menu behavior", suite: suite) { try MenuHighlightProbe.run() }
            await check("Liquid Glass lifecycle and band independence", suite: suite) { try GlassWaveformProbe.run() }
        default: throw BenchError.message("Unknown benchmark suite.")
        }
    }

    private static func emit(_ result: BenchResult) {
        if let data = try? JSONEncoder().encode(result) {
            print("S2TBENCH " + String(decoding: data, as: UTF8.self)); fflush(stdout)
        }
    }

    private static func check(_ name: String, suite: String, work: () async throws -> Void) async {
        let start = CACurrentMediaTime()
        do {
            try await work()
            emit(BenchResult(suite: suite, name: name, status: .passed, detail: "Production fixture assertions passed.", metrics: ["latency_ms": (CACurrentMediaTime() - start) * 1000]))
        } catch {
            emit(BenchResult(suite: suite, name: name, status: .failed, detail: error.localizedDescription, metrics: ["latency_ms": (CACurrentMediaTime() - start) * 1000]))
        }
    }

    private static func frames(mode: String, resizing: Bool, seconds: Double, seed: UInt64) async throws {
        let renderer = ChromaFrameRenderer()
        var completions: [Double] = []
        var observationStart = Double.infinity
        var lastFrame: ChromaFrame?
        let observation = renderer.$frame.sink { frame in
            if let frame { lastFrame = frame; if CACurrentMediaTime() >= observationStart { completions.append(CACurrentMediaTime()) } }
        }
        defer { observation.cancel(); renderer.cancel() }
        func request(_ index: Int) -> ChromaFrameRequest {
            let energy = 0.12 + 0.83 * (0.5 + 0.5 * sin(Double(index) * 0.27 + Double(seed % 31)))
            var profile = GlowProfile(energy: energy, heights: [], sweepStrength: 1.3)
            profile.distortion = GlowDistortion(bands: (0..<7).map { 0.1 + 0.8 * (0.5 + 0.5 * sin(Double(index + $0 * 7) * 0.21)) })
            profile.response = .init(minimum: 0.25, maximum: 2.2)
            let geometry: ChromaAppearance.Geometry
            let size: CGSize
            let growth = resizing ? CGFloat((index / 15) % 5) * 20 : 0
            if mode == "Bottom" {
                geometry = .bottom; size = CGSize(width: resizing ? 2560 : 1800, height: GlowProfile.extent)
            } else if mode == "Around Notch" {
                let display = GlowDisplay(frame: CGRect(x: 0, y: 0, width: 1800, height: 1169), safeTop: 32,
                    topLeft: CGRect(x: 0, y: 1137, width: 780, height: 32), topRight: CGRect(x: 1020, y: 1137, width: 780, height: 32))
                let layout = TopGlowLayout(display: display, paddingScale: profile.response.paddingScale)
                geometry = .notch(layout); size = layout.frame.size; profile.topLayout = layout
                if resizing { profile.response.tuning.softness = Double((index / 30) % 3) * 5 }
            } else {
                let layout = InputOutlineGeometry(field: CGRect(x: 0, y: 0, width: 736, height: 136 + growth), paddingScale: profile.response.paddingScale)
                let p = layout.outlineRect.origin
                var contour = InputContour(rect: CGRect(x: p.x, y: p.y + 38, width: 736, height: 98 + growth), radius: 16, style: .circular)
                contour.bars = [.init(rect: CGRect(x: p.x + 13, y: p.y, width: 710, height: 42), radius: 16, style: .circular, corners: .top)]
                let within = mode == "Within Input"
                geometry = within ? .withinInput(contour) : .input(contour)
                size = layout.windowFrame.size
                profile.inputOutline = .init(contour: contour, strength: 1.3, withinInput: within)
            }
            return ChromaFrameRequest(geometry: geometry, size: size, profile: profile, brightness: profile.speechGain, backdrop: true)
        }
        let coldStart = CACurrentMediaTime()
        let first = request(0)
        renderer.submit(first)
        while renderer.frame == nil && CACurrentMediaTime() - coldStart < 30 { try await Task.sleep(nanoseconds: 5_000_000) }
        let cold = (CACurrentMediaTime() - coldStart) * 1000
        guard renderer.frame != nil else { emit(BenchResult(suite: "animations", name: mode, status: .failed, detail: "No first frame within 30 seconds.")); return }
        observationStart = CACurrentMediaTime()
        let started = observationStart
        var ticks: [Double] = [], previous = started
        var index = 1
        while CACurrentMediaTime() - started < seconds {
            let now = CACurrentMediaTime()
            ticks.append((now - previous) * 1000); previous = now
            renderer.submit(request(index))
            index += 1
            // Absolute schedule skips missed ticks instead of creating catch-up bursts.
            let next = started + (floor((CACurrentMediaTime() - started) * 60) + 1) / 60
            try await Task.sleep(nanoseconds: UInt64(max(0.001, next - CACurrentMediaTime()) * 1_000_000_000))
        }
        let ended = CACurrentMediaTime()
        let timestamps = [started] + completions + [ended]
        let intervals = zip(timestamps, timestamps.dropFirst()).map { ($1 - $0) * 1000 }
        let statistics = BenchStatistics(intervals)
        let fps = Double(completions.count) / (ended - started)
        let tickStats = BenchStatistics(Array(ticks.dropFirst()))
        let passed = fps >= 57 && (statistics.p99 ?? .infinity) <= 33.334 && (statistics.maximum ?? .infinity) <= 100
        var result = BenchResult(suite: "animations", name: "\(mode) · \(resizing ? "geometry / tuning churn" : "changing spectrum")",
            status: passed ? .passed : .failed,
            detail: "Gate: ≥57 prepared frames/s, p99 ≤33.334 ms, no gap >100 ms. Includes native map generation at full padded size. Offscreen throughput, not screen-presented FPS.",
            metrics: ["prepared_fps": fps, "cold_ms": cold, "p50_ms": statistics.median ?? 0, "p95_ms": statistics.p95 ?? 0,
                "p99_ms": statistics.p99 ?? 0, "worst_ms": statistics.maximum ?? 0, "gaps_over_16_67_ms": Double(statistics.over(16.667)),
                "main_tick_worst_ms": tickStats.maximum ?? 0, "submitted": Double(index - 1), "completed": Double(completions.count),
                "seconds": ended - started, "width": first.size.width, "height": first.size.height])
        result.samples = intervals
        if let lastFrame {
            var drawing: [Double] = []
            for i in 0..<12 {
                try autoreleasepool {
                    let start = CACurrentMediaTime()
                    let image = ImageRenderer(content: ChromaFrameCanvas(frame: lastFrame, cycleTime: Double(i) / 60).frame(width: lastFrame.request.size.width, height: lastFrame.request.size.height))
                    image.scale = 2
                    guard image.cgImage != nil else { throw BenchError.message("Offscreen Canvas drawing failed.") }
                    drawing.append((CACurrentMediaTime() - start) * 1000)
                }
            }
            result.metrics["canvas_2x_p95_ms"] = BenchStatistics(drawing).p95
            result.metrics["canvas_2x_worst_ms"] = drawing.max()
            if (drawing.max() ?? .infinity) > 100 { result.status = .failed; result.detail += " 2× Canvas drawing exceeded 100 ms." }
        }
        emit(result)
    }

    private static func inputStorm(seed: UInt64, count: Int) throws {
        let pid: pid_t = 2_970_000
        let app = AXUIElementCreateApplication(pid), window = AXUIElementCreateApplication(pid + 1), field = AXUIElementCreateApplication(pid + 2)
        var random = BenchRandom(seed: seed)
        var rect = CGRect.zero, secure = false, moving = false, staleFocus = false, sizeReads = 0, focusReads = 0, calls = 0
        var requested = Set<String>()
        let reader = FocusedInputReader(attribute: { node, name in
            calls += 1; requested.insert(name)
            if CFEqual(node, app) {
                if name == kAXFocusedUIElementAttribute { focusReads += 1; return staleFocus && focusReads > 1 ? window : field }
                if name == kAXFocusedWindowAttribute { return window }
                return nil
            }
            let isField = CFEqual(node, field)
            switch name {
            case kAXRoleAttribute: return (isField ? "AXTextField" : "AXWindow") as CFString
            case kAXSubroleAttribute: return (isField && secure ? "AXSecureTextField" : "") as CFString
            case kAXParentAttribute: return isField ? window : nil
            case kAXPositionAttribute:
                var point = isField ? rect.origin : CGPoint(x: -2000, y: -1000)
                return AXValueCreate(.cgPoint, &point)
            case kAXSizeAttribute:
                var size = isField ? rect.size : CGSize(width: 8000, height: 4000)
                if isField { sizeReads += 1; if moving && sizeReads > 1 { size.height += 37 } }
                return AXValueCreate(.cgSize, &size)
            default: return nil
            }
        }, children: { _ in [] }, fallbackFocus: { _ in nil }, hitTest: { _, _ in nil }, applicationBundleID: { _ in "test.benchmark.unfamiliar" }, enableAccessibility: { _ in })
        for index in 0..<count {
            let scenario = index % 4
            secure = scenario == 1; moving = scenario == 2; staleFocus = scenario == 3
            rect = CGRect(x: Double(Int(random.next() % 3000) - 1000) + 0.25, y: Double(random.next() % 900) + 0.75,
                width: Double(50 + random.next() % 1000), height: Double(22 + random.next() % 240))
            calls = 0; sizeReads = 0; focusReads = 0
            let target = reader.read(pid: pid)
            guard scenario == 0 ? target == rect : target == nil else {
                throw BenchError.message("Seed \(seed), case \(index), scenario \(scenario): wrong or stale target.")
            }
            guard calls < 900 else { throw BenchError.message("Metadata budget exceeded at seed \(seed), case \(index).") }
        }
        guard requested.isDisjoint(with: [kAXValueAttribute, kAXTitleAttribute, kAXSelectedTextAttribute, kAXDescriptionAttribute]) else {
            throw BenchError.message("Targeting requested field content.")
        }
    }
}
