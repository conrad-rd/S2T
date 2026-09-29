import AppKit
import SwiftUI
import S2TCore

// Only authored pixels enter this compositor. It never reads windows or screens.
@MainActor enum ProcessingBlurProbe {
    static func run() throws {
        try verifyInputReadability()
        try verifyEdgeFalloff()
        try verifyReferencePerimeter()
        try verifyBroadCornerWrap()
        try verifyMovingReflection()
        try verifyContourLens()
        try verifyJoinedContour()
        let size = CGSize(width: 440, height: 280)
        let contour = InputContour(rect: CGRect(x: 60, y: 60, width: 320, height: 160), radius: 30, style: .circular)
        let stripes = try render(Canvas(opaque: true) { context, _ in
            for x in stride(from: 0, to: 440, by: 4) {
                context.fill(Path(CGRect(x: x, y: 0, width: 4, height: 280)),
                    with: .color((x / 4).isMultiple(of: 2) ? .black : .white))
            }
        }, size: size)
        let clear = try render(Color.clear, size: size)
        let compositor = try GeneratedGlowCompositor(background: stripes, size: size, scale: 1)
        var contrasts: [[Double]] = []
        for time in [0.0, 0.45] {
            let profile = InputProcessingGlow.profile(contour: contour, time: time)
            _ = try compositor.frame(profile: profile, foreground: clear, time: time)
            let image = try compositor.frame(profile: profile, foreground: clear, time: time + 0.001)
            let bitmap = NSBitmapImageRep(cgImage: image)
            let values = [20, 80, 100, 120, 140, 160, 180, 200, 260].map { y in
                let row = (216..<228).map { x in bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!.redComponent }
                return Double(row.max()! - row.min()!)
            }
            let inside = Array(values.dropFirst().dropLast())
            guard values.first! > 0.98, values.last! > 0.98,
                  inside.min()! > 0.65, inside.min()! < 0.98, inside.max()! > 0.9,
                  inside.max()! - inside.min()! > 0.03 else {
                throw failure("Native progressive blur must retain readable contrast while the sheen passes and leave the exterior sharp: \(values)")
            }
            contrasts.append(values)
        }
        let movement = zip(contrasts[0], contrasts[1]).reduce(0) { $0 + abs($1.0 - $1.1) }
        guard movement > 0.07 else { throw failure("Native blur does not travel with the wave: \(contrasts)") }
        print("PASS: production native filter on generated stripes, progressive strength, moving field and sharp exterior. Contrasts: \(contrasts)")
    }

    static func verifyInputReadability() throws {
        let size = CGSize(width: 680, height: 220)
        var contour = InputContour(rect: CGRect(x: 40, y: 30, width: 600, height: 128), radius: 20, style: .circular)
        contour.bars = [.init(rect: CGRect(x: 52, y: 158, width: 576, height: 32), radius: 12,
            style: .circular, corners: .bottom)]
        var average = 0.0, maximum = 0.0, count = 0
        for time in [0.0, 0.45, 0.9, 1.35, 1.8, 2.7] {
            let view = Canvas(opaque: false, colorMode: .extendedLinear) { context, _ in
                WithinInputProcessing.draw(context: &context, contour: contour, time: time, reducedMotion: false)
            }
            let pixels = NSBitmapImageRep(cgImage: try render(view, size: size))
            for y in stride(from: 56, to: 164, by: 3) { for x in stride(from: 160, to: 520, by: 12) {
                let coverage = pixels.colorAt(x: x, y: y)!.alphaComponent
                average += coverage; maximum = max(maximum, coverage); count += 1
            } }
        }
        average /= Double(count)
        guard average < 0.05, maximum < 0.10, maximum > 0.03 else {
            throw failure("The input must remain visible beneath a passing sheen: average coverage \(average), peak \(maximum)")
        }
        print("PASS: readable message-bar center across the color cycle. Average coverage \(average), peak \(maximum).")
    }

    private static func verifyEdgeFalloff() throws {
        let size = CGSize(width: 760, height: 230)
        var contour = InputContour(rect: CGRect(x: 40, y: 30, width: 680, height: 140), radius: 20, style: .circular)
        contour.bars = [.init(rect: CGRect(x: 50, y: 170, width: 660, height: 30), radius: 12,
            style: .circular, corners: .bottom)]
        var maximumStep = 0.0, maximumCurvature = 0.0
        for time in [0.0, 0.8, 2.6] {
            let view = Canvas(opaque: false, colorMode: .extendedLinear) { context, _ in
                WithinInputProcessing.draw(context: &context, contour: contour, time: time, reducedMotion: false)
            }.frame(width: size.width, height: size.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage else { throw failure("Missing edge-falloff fixture") }
            let pixels = NSBitmapImageRep(cgImage: image)
            func luminance(_ x: Int, _ y: Int) -> Double {
                let c = pixels.colorAt(x: x, y: y)!
                return Double((c.redComponent * 0.2126 + c.greenComponent * 0.7152
                    + c.blueComponent * 0.0722) * c.alphaComponent)
            }
            // Sample the actual 2x output across the exterior, inner rim and
            // attached footer shoulders. A clipped white line jumped 87% here.
            for x in 72..<95 {
                maximumStep = max(maximumStep, abs(pixels.colorAt(x: x + 1, y: 200)!.alphaComponent
                    - pixels.colorAt(x: x, y: 200)!.alphaComponent))
            }
            for y in 62..<398 { for x in 82..<154 {
                guard contour.path.contains(CGPoint(x: Double(x) / 2, y: Double(y) / 2)),
                      pixels.colorAt(x: x, y: y)!.alphaComponent > 0.08 else { continue }
                maximumCurvature = max(maximumCurvature,
                    abs(luminance(x - 1, y) - 2 * luminance(x, y) + luminance(x + 1, y)),
                    abs(luminance(x, y - 1) - 2 * luminance(x, y) + luminance(x, y + 1)))
            } }
        }
        guard maximumStep < 0.2, maximumCurvature < 0.065 else {
            throw failure("The edge has an abrupt cutoff or rough corner falloff: \(maximumStep), \(maximumCurvature)")
        }
        print("PASS: smooth 2x edge falloff and blurred footer shoulders. Maximum alpha step \(maximumStep), corner curvature \(maximumCurvature).")
    }

    static func verifyBroadCornerWrap() throws {
        for (width, height, radius, footer) in [(600, 160, 20.0, true), (418, 160, 42.0, false),
                                               (320, 80, 16.0, true), (112, 36, 18.0, false)] {
            let size = CGSize(width: width, height: height)
            let footerHeight = footer ? min(32, height / 4) : 0
            var contour = InputContour(rect: CGRect(x: 0, y: 0, width: width, height: height - footerHeight), radius: radius, style: .circular)
            if footer { contour.bars = [.init(rect: CGRect(x: 12, y: height - footerHeight, width: width - 24, height: footerHeight),
                radius: 12, style: .circular, corners: .bottom)] }
            var ramp = [Float](repeating: 1, count: width * height * 4)
            for y in 0..<height { for x in 0..<width {
                ramp[(y * width + x) * 4] = Float(x) / Float(width)
                ramp[(y * width + x) * 4 + 1] = Float(y) / Float(height)
            } }
            let field = ProcessingGlassRefraction.apply(ramp, width: width, height: height, size: size, contour: contour)
            func source(_ x: Int, _ y: Int) -> SIMD2<Double> {
                let i = (y * width + x) * 4
                return SIMD2(Double(field[i] / field[i + 3]) * Double(width),
                             Double(field[i + 1] / field[i + 3]) * Double(height))
            }
            let bend = source(40, 35).y - 35
            if width == 600 {
                guard bend > 3 && bend < 30 else { throw failure("The corner curl must reach the broad wave, not only the rim: \(bend)") }
            }
            var minimumArea = Double.infinity
            for y in 8..<(height - 8) { for x in 8..<(width - 8) {
                let i = (y * width + x) * 4
                guard field[i + 3] > 0.995, field[i + 7] > 0.995,
                      field[i + width * 4 + 3] > 0.995 else { continue }
                let p = source(x, y), dx = source(x + 1, y) - p, dy = source(x, y + 1) - p
                minimumArea = min(minimumArea, dx.x * dy.y - dx.y * dy.x)
            } }
            guard minimumArea > 0.05 else { throw failure("The \(width)x\(height) corner or footer lens folds back over itself: \(minimumArea)") }
            print("PASS: \(width)x\(height) broad corner wrapping and continuous lens. Minimum mapped area \(minimumArea).")
        }
    }

    private static func verifyMovingReflection() throws {
        let size = CGSize(width: 320, height: 120)
        let contour = InputContour(rect: CGRect(origin: .zero, size: size), radius: 24, style: .circular)
        func reflected(_ light: Float) -> [Float] {
            var source = [Float](repeating: 0.7, count: 320 * 120 * 4)
            for i in stride(from: 0, to: source.count, by: 4) {
                for channel in 0..<3 { source[i + channel] = light * 0.7 }
            }
            return ProcessingGlassRefraction.apply(source, width: 320, height: 120,
                size: size, contour: contour, rim: SIMD3(repeating: 0.65))
        }
        let dark = reflected(0.08), bright = reflected(0.6)
        let sample = (60 * 320 + 8) * 4
        guard bright[sample + 3] - dark[sample + 3] > 0.03, dark[sample + 3] < 0.98 else {
            throw failure("The broad reflection must respond to the passing light instead of forming a constant opaque rail")
        }
        for field in [dark, bright] {
            for i in stride(from: 0, to: field.count, by: 4) {
                guard field[i + 3] <= 1, (0..<3).allSatisfy({ field[i + $0] <= field[i + 3] + 0.0001 }) else {
                    throw failure("Reflected light must retain bounded premultiplied color and coverage")
                }
            }
        }
        print("PASS: wave-driven reflection, translucent dark-edge coverage and bounded light composition.")
    }

    private static func verifyContourLens() throws {
        let width = 360, height = 160
        let size = CGSize(width: width, height: height)
        var contour = InputContour(rect: CGRect(x: 0, y: 0, width: width, height: 128), radius: 20, style: .circular)
        contour.bars = [.init(rect: CGRect(x: 10, y: 128, width: 340, height: 32), radius: 14,
            style: .circular, corners: .bottom)]
        // Coordinate ramps make the production lens's displacement observable.
        // The reference curls the wave inward at the sides while leaving its center intact.
        var ramp = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            ramp[(y * width + x) * 4] = Float(x) / Float(width)
            ramp[(y * width + x) * 4 + 1] = Float(y) / Float(height)
        } }
        let result = ProcessingGlassRefraction.apply(ramp, width: width, height: height, size: size, contour: contour)
        var maximum = 0.0, bentCorner = false
        for y in 4..<(height - 4) { for x in 4..<(width - 4) {
            let index = (y * width + x) * 4
            guard result[index + 3] > 0.995 else { continue }
            let dx = Double(result[index] / result[index + 3]) * Double(width) - Double(x)
            let dy = Double(result[index + 1] / result[index + 3]) * Double(height) - Double(y)
            maximum = max(maximum, hypot(dx, dy))
            if x < 25 && y < 25 && dx > 0.3 && dy > 0.3 { bentCorner = true }
            if x > 135 && x < width - 135 && y > 50 && y < height - 50 {
                guard abs(dx) < 0.1 && abs(dy) < 0.1 else { throw failure("The edge lens moved the central wave") }
            }
        } }
        guard maximum > 10 && maximum < 60 && bentCorner else {
            throw failure("The reference wave must visibly curl around the sides within a bounded edge field: \(maximum)")
        }
        print("PASS: reference side curl, bounded corner refraction and undisturbed center.")
    }

    private static func verifyReferencePerimeter() throws {
        let size = CGSize(width: 418, height: 160)
        let contour = InputContour(rect: CGRect(origin: .zero, size: size), radius: 42, style: .circular)
        guard let field = WithinInputProcessing.loadingImage(size: size, time: 0, gradient: .init(), contour: contour),
              let image = field.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw failure("Missing reference-proportion fixture")
        }
        let pixels = NSBitmapImageRep(cgImage: image)
        // Independent samples from the supplied video's first frame. Compare
        // lightness, since the user's gradient intentionally replaces its hue.
        let samples: [(Int, Int, SIMD3<Double>)] = [
            (3, 80, SIMD3(253, 251, 254)), (10, 80, SIMD3(255, 205, 254)),
            (20, 80, SIMD3(225, 159, 222)), (209, 64, SIMD3(93, 61, 151))
        ]
        for (x, y, captured) in samples {
            let raw = pixels.colorAt(x: x, y: y)!
            let converted = CGColor(colorSpace: pixels.colorSpace.cgColorSpace!,
                components: [raw.redComponent, raw.greenComponent, raw.blueComponent, raw.alphaComponent])!
                .converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)!.components!
            let actual = OKLab.fromSRGB(SIMD3(Double(converted[0]), Double(converted[1]), Double(converted[2])))
            let reference = OKLab.fromSRGB(captured / 255)
            guard abs(actual.x - reference.x) < 0.13 else {
                throw failure("The broad edge light or dark fold drifted from the reference at \(x),\(y): \(actual.x) versus \(reference.x)")
            }
        }
        for y in 0..<pixels.pixelsHigh { for x in 0..<pixels.pixelsWide {
            let color = pixels.colorAt(x: x, y: y)!
            guard color.alphaComponent.isFinite && (0...1).contains(color.alphaComponent) else {
                throw failure("Reference bloom produced invalid coverage")
            }
        } }
        print("PASS: independent reference lightness samples retain the broad luminous edge and dark fold.")
    }

    private static func verifyJoinedContour() throws {
        let size = CGSize(width: 600, height: 160)
        let whole = InputContour(rect: CGRect(origin: .zero, size: size), radius: 24, style: .circular)
        var joined = InputContour(rect: CGRect(x: 0, y: 0, width: 600, height: 112), radius: 24, style: .circular)
        joined.main.corners = .top
        joined.bars = [.init(rect: CGRect(x: 0, y: 112, width: 600, height: 48), radius: 24,
            style: .circular, corners: .bottom)]
        for time in [0.0, 0.45, 0.9, 1.35] {
            func pixels(_ contour: InputContour, blur: Bool) throws -> NSBitmapImageRep {
                let image = blur ? WithinInputProcessing.radiusMap(size: size, time: time, contour: contour)
                    : WithinInputProcessing.loadingImage(size: size, time: time, gradient: .init(), contour: contour)
                guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    throw failure("Missing joined-input fixture")
                }
                return NSBitmapImageRep(cgImage: cg)
            }
            for blur in [false, true] {
                let a = try pixels(whole, blur: blur), b = try pixels(joined, blur: blur)
                var difference = 0.0
                for y in 4..<156 { for x in stride(from: 80, to: 520, by: 40) {
                    let px = Int(Double(x) / size.width * Double(a.pixelsWide))
                    let ca = a.colorAt(x: px, y: y)!.usingColorSpace(.sRGB)!
                    let cb = b.colorAt(x: px, y: y)!.usingColorSpace(.sRGB)!
                    difference = max(difference, abs(ca.redComponent - cb.redComponent),
                        abs(ca.greenComponent - cb.greenComponent), abs(ca.blueComponent - cb.blueComponent),
                        abs(ca.alphaComponent - cb.alphaComponent))
                } }
                guard difference < 0.006 else {
                    throw failure("An attached control row creates an internal \(blur ? "blur" : "color") edge: \(difference)")
                }
            }
        }
        var footer = InputContour(rect: CGRect(x: 0, y: 0, width: 600, height: 112), radius: 24, style: .circular)
        footer.bars = [.init(rect: CGRect(x: 12, y: 112, width: 576, height: 48), radius: 16,
            style: .circular, corners: .bottom)]
        let rim = try render(Canvas(opaque: false, colorMode: .extendedLinear) { context, _ in
            WithinInputProcessing.drawBorder(context: &context, boundary: footer.path,
                size: size, time: 0, gradient: .init())
        }, size: size)
        let rimPixels = NSBitmapImageRep(cgImage: rim)
        for y in 109...115 { for x in stride(from: 80, to: 520, by: 20) {
            guard rimPixels.colorAt(x: x, y: y)!.alphaComponent < 0.001 else {
                throw failure("A visible glass border crosses the attached footer join")
            }
        } }
        print("PASS: identical outer contours have identical processing color and native blur across attached-row joins.")
    }

    static func compoundFixture() throws -> CGImage {
        let size = CGSize(width: 700, height: 240)
        var contour = InputContour(rect: CGRect(x: 24, y: 24, width: 652, height: 132), radius: 20, style: .circular)
        contour.bars = [.init(rect: CGRect(x: 32, y: 156, width: 636, height: 36), radius: 14,
            style: .circular, corners: .bottom)]
        var frames = [CGImage]()
        for dark in [false, true] {
            let background = try render(Canvas(opaque: true, colorMode: .extendedLinear) { context, _ in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(dark ? Color(white: 0.07) : Color(white: 0.96)))
                context.fill(contour.path, with: .color(dark ? Color(white: 0.13) : .white))
                context.draw(Text("A message behind the moving glow").font(.system(size: 15)).foregroundColor(dark ? .white : .black),
                    at: CGPoint(x: 46, y: 44), anchor: .topLeading)
                context.draw(Text("Model     Attach file").font(.system(size: 12)).foregroundColor(dark ? .white : .black),
                    at: CGPoint(x: 46, y: 166), anchor: .topLeading)
            }, size: size)
            let compositor = try GeneratedGlowCompositor(background: background, size: size, scale: 1)
            for index in 0..<4 {
                let time = Double(index) * ReferenceLoadingField.duration
                let foreground = try render(Canvas(opaque: false, colorMode: .extendedLinear) { context, _ in
                    context.drawLayer { effect in
                        WithinInputProcessing.draw(context: &effect, contour: contour, time: time, reducedMotion: false)
                    }
                    context.draw(Text(String(format: "%.1f s", time)).font(.system(size: 12)).foregroundColor(.gray),
                        at: CGPoint(x: 24, y: 214), anchor: .topLeading)
                }, size: size)
                let profile = InputProcessingGlow.profile(contour: contour, time: time)
                _ = try compositor.frame(profile: profile, foreground: foreground, time: time)
                frames.append(try compositor.frame(profile: profile, foreground: foreground, time: time + 0.001))
            }
        }
        let images = frames
        return try render(Canvas(opaque: true) { context, _ in
            for theme in 0..<2 { for row in 0..<4 {
                context.draw(Image(decorative: images[theme * 4 + row], scale: 1),
                    in: CGRect(x: theme * 700, y: row * 240, width: 700, height: 240))
            } }
        }, size: CGSize(width: 1400, height: 960))
    }

    static func fixture() throws -> CGImage {
        let size = CGSize(width: 480, height: 190)
        let contour = InputContour(rect: CGRect(x: 34, y: 34, width: 412, height: 108), radius: 30, style: .circular)
        var frames = [CGImage]()
        for theme in 0..<2 {
            let dark = theme == 0
            let background = try render(Canvas(opaque: true, colorMode: .extendedLinear) { context, _ in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(dark ? Color(white: 0.07) : Color(white: 0.93)))
                context.fill(contour.path, with: .color(dark ? Color(white: 0.13) : .white))
                for row in 0..<3 {
                    context.draw(Text("A message behind the moving glow.").font(.system(size: 15)).foregroundColor(dark ? .white : .black),
                        at: CGPoint(x: 58, y: 51 + row * 29), anchor: .topLeading)
                }
            }, size: size)
            let compositor = try GeneratedGlowCompositor(background: background, size: size, scale: 1)
            for index in 0..<4 {
                let time = Double(index) * ReferenceLoadingField.duration / 2
                let foreground = try render(Canvas(opaque: false, colorMode: .extendedLinear) { context, _ in
                    context.drawLayer { effect in
                        WithinInputProcessing.draw(context: &effect, contour: contour, time: time, reducedMotion: false)
                    }
                    context.draw(Text(String(format: "%.1f s", time)).font(.system(size: 12)).foregroundColor(.gray),
                        at: CGPoint(x: 34, y: 163), anchor: .topLeading)
                }, size: size)
                let profile = InputProcessingGlow.profile(contour: contour, time: time)
                _ = try compositor.frame(profile: profile, foreground: foreground, time: time)
                frames.append(try compositor.frame(profile: profile, foreground: foreground, time: time + 0.001))
            }
        }
        let images = frames
        return try render(Canvas(opaque: true) { context, _ in
            for theme in 0..<2 { for row in 0..<4 {
                let image = Image(decorative: images[theme * 4 + row], scale: 1)
                context.draw(image, in: CGRect(x: theme * 480, y: row * 190, width: 480, height: 190))
            } }
        }, size: CGSize(width: 960, height: 760))
    }

    private static func render<V: View>(_ view: V, size: CGSize) throws -> CGImage {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        guard let image = renderer.cgImage else { throw failure("Could not render authored processing fixture.") }
        return image
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "ProcessingBlur", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
