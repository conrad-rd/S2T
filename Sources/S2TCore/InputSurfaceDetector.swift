import Foundation
import CoreGraphics

/// RGBA8 pixels, row-major from the top-left corner.
public struct InputSurfaceBitmap: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count >= width * height * 4)
        self.width = width; self.height = height; self.pixels = pixels
    }
}

/// The painted field around an editor, in bitmap pixels.
public struct InputSurface: Equatable, Sendable {
    public let rect: CGRect
    public let radius: CGFloat
    public let capsule: Bool
    /// The rounded side when an attached list squares the other one.
    public let corners: InputContour.Corners
    /// Narrower bars joined to the field, in bitmap pixels.
    public let bars: [InputContour.Part]
}

/// Finds the visible field that contains an editor. Accessibility frames describe
/// layout wrappers; only the rendered fill and border show where a field starts and ends.
public enum InputSurfaceDetector {
    /// Bitmap sides that coincide with the window's edges. A field may continue past them.
    public struct Edges: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let top = Edges(rawValue: 1), left = Edges(rawValue: 2), bottom = Edges(rawValue: 4), right = Edges(rawValue: 8)
    }
    /// Receives the reason whenever a measurement is rejected. Diagnostics only.
    nonisolated(unsafe) public static var trace: ((String) -> Void)?

    public static func detect(in bitmap: InputSurfaceBitmap, editor: CGRect, scale: CGFloat, windowEdges: Edges = []) -> InputSurface? {
        let w = bitmap.width, h = bitmap.height
        guard w >= 8, h >= 8, scale > 0 else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: w, height: h)
        let seedArea = editor.integral.intersection(bounds.insetBy(dx: 1, dy: 1))
        guard !seedArea.isNull, seedArea.width >= 4, seedArea.height >= 4 else { return nil }
        // Plain inputs report their bordered box. Seeding its edge would start outside the border.
        let core = seedArea.insetBy(dx: min(3 * scale, seedArea.width * 0.25), dy: min(3 * scale, seedArea.height * 0.25)).integral
        let px = bitmap.pixels
        let x0 = Int(core.minX), x1 = Int(core.maxX), y0 = Int(core.minY), y1 = Int(core.maxY)
        guard x1 > x0, y1 > y0 else { return nil }

        // The fill is the most common color behind the editor; glyphs and the caret are sparse.
        var counts = [Int32](repeating: 0, count: 4096)
        for y in y0..<y1 {
            var i = (y * w + x0) * 4
            for _ in x0..<x1 {
                counts[Int(px[i] >> 4) << 8 | Int(px[i + 1] >> 4) << 4 | Int(px[i + 2] >> 4)] += 1
                i += 4
            }
        }
        let total = (x1 - x0) * (y1 - y0)
        guard let mode = counts.indices.max(by: { counts[$0] < counts[$1] }),
              Double(counts[mode]) >= Double(total) * 0.25 else { trace?("no dominant fill behind the editor"); return nil }
        var sum = (0, 0, 0), members = 0
        for y in y0..<y1 {
            var i = (y * w + x0) * 4
            for _ in x0..<x1 {
                if Int(px[i] >> 4) << 8 | Int(px[i + 1] >> 4) << 4 | Int(px[i + 2] >> 4) == mode {
                    sum.0 += Int(px[i]); sum.1 += Int(px[i + 1]); sum.2 += Int(px[i + 2]); members += 1
                }
                i += 4
            }
        }
        let seed = (sum.0 / members, sum.1 / members, sum.2 / members)
        func distance(_ i: Int, _ c: (Int, Int, Int)) -> Int {
            max(abs(Int(px[i]) - c.0), abs(Int(px[i + 1]) - c.1), abs(Int(px[i + 2]) - c.2))
        }
        // Translucent materials vary slightly; flat web fills do not.
        var spread = [Int](repeating: 0, count: 17)
        for y in y0..<y1 {
            var i = (y * w + x0) * 4
            for _ in x0..<x1 {
                let d = distance(i, seed)
                if d <= 16 { spread[d] += 1 }
                i += 4
            }
        }
        var noise = 0, covered = 0
        let near = spread.reduce(0, +)
        for (d, n) in spread.enumerated() {
            covered += n
            if Double(covered) >= Double(near) * 0.9 { noise = d; break }
        }
        let tolerance = min(10, max(3, noise + 3))

        var inside = [UInt8](repeating: 0, count: w * h)
        var queue = [Int32]()
        queue.reserveCapacity(w * h / 4)
        for y in y0..<y1 {
            for x in x0..<x1 where distance((y * w + x) * 4, seed) <= tolerance {
                inside[y * w + x] = 1
                queue.append(Int32(y * w + x))
            }
        }
        var head = 0
        var rowCount = [Int](repeating: 0, count: h)
        while head < queue.count {
            let index = Int(queue[head]); head += 1
            let x = index % w, y = index / w
            rowCount[y] += 1
            for (next, open) in [(index - 1, x > 0), (index + 1, x < w - 1), (index - w, y > 0), (index + w, y < h - 1)]
                where open && inside[next] == 0 {
                if distance(next * 4, seed) <= tolerance {
                    inside[next] = 1
                    queue.append(Int32(next))
                } else { inside[next] = 2 }
            }
        }

        // Suggestion lists often share the field's fill and join it below a divider.
        // A divider is a row where the fill nearly vanishes and then continues.
        let editorRows = (y0..<y1).map { rowCount[$0] }.sorted()
        let reference = CGFloat(editorRows[editorRows.count / 2])
        guard reference > 0 else { return nil }
        let lookahead = Int(ceil(scale * 4))
        func extend(from start: Int, step: Int) -> (edge: Int, divided: Bool) {
            var y = start
            while y + step >= 0 && y + step < h && rowCount[y + step] > 0 {
                let next = y + step
                if CGFloat(rowCount[next]) < reference * 0.35 {
                    var ahead = next + step
                    while ahead >= 0 && ahead < h && abs(ahead - next) <= lookahead {
                        if CGFloat(rowCount[ahead]) >= reference * 0.6 { return (y, true) }
                        ahead += step
                    }
                }
                y = next
            }
            return (y, false)
        }
        let top = extend(from: y0, step: -1), bottom = extend(from: y1 - 1, step: 1)
        var minX = w, maxX = -1, filled = 0
        for y in top.edge...bottom.edge {
            for x in 0..<w where inside[y * w + x] == 1 {
                minX = min(minX, x); maxX = max(maxX, x); filled += 1
            }
        }
        // Reaching the capture edge means the fill continues into the page. A window edge
        // may clip one side of a field, such as a composer docked to the window bottom.
        guard maxX >= minX else { return nil }
        var touched = Edges()
        if minX == 0 { touched.insert(.left) }
        if maxX == w - 1 { touched.insert(.right) }
        if top.edge == 0 { touched.insert(.top) }
        if bottom.edge == h - 1 { touched.insert(.bottom) }
        guard touched.isEmpty || (windowEdges.isSuperset(of: touched) && [.top, .left, .bottom, .right].contains(touched)) else {
            trace?("fill reaches the capture edge \(touched.rawValue) (window \(windowEdges.rawValue))"); return nil
        }
        let interior = CGRect(x: minX, y: top.edge, width: maxX - minX + 1, height: bottom.edge - top.edge + 1)
        // Text, icons and buttons leave holes. A sparse component is a leaked outline, not a field.
        guard Double(filled) >= Double(interior.width * interior.height) * 0.4 else {
            trace?("sparse fill \(filled) in \(interior)"); return nil
        }
        guard interior.intersection(seedArea).width * interior.intersection(seedArea).height
                >= seedArea.width * seedArea.height * 0.6 else { trace?("fill \(interior) misses the editor \(seedArea)"); return nil }

        // Composers may carry a narrower status bar in the same fill. Measure it as an
        // attached part, so the body keeps its own corners.
        var extents = [Int: (lo: Int, hi: Int)]()
        for y in top.edge...bottom.edge {
            var lo = -1, hi = -1
            for x in minX...maxX where inside[y * w + x] == 1 { if lo < 0 { lo = x }; hi = x }
            if lo >= 0 { extents[y] = (lo, hi) }
        }
        let bodyRows = (y0..<y1).compactMap { extents[$0] }
        if !bodyRows.isEmpty, touched.isEmpty {
            let bodyLo = bodyRows.map(\.lo).sorted()[bodyRows.count / 2], bodyHi = bodyRows.map(\.hi).sorted()[bodyRows.count / 2]
            for below in [true, false] {
                guard let bar = attachedBar(extents: extents, from: below ? y1 : y0 - 1, to: below ? bottom.edge : top.edge,
                                            bodyLo: bodyLo, bodyHi: bodyHi, scale: scale) else { continue }
                let body = CGRect(x: minX, y: below ? top.edge : bar.join, width: maxX - minX + 1,
                                  height: below ? bar.join - top.edge : bottom.edge - bar.join + 1)
                let barRect = CGRect(x: bar.lo, y: below ? bar.join : top.edge, width: bar.hi - bar.lo + 1,
                                     height: below ? bottom.edge - bar.join + 1 : bar.join - top.edge)
                let bodyCorners = cornerRadii(inside: inside, w: w, interior: body)
                let barCorners = cornerRadii(inside: inside, w: w, interior: barRect)
                let bodyRadius = below ? (bodyCorners[0] + bodyCorners[1]) / 2 : (bodyCorners[2] + bodyCorners[3]) / 2
                let barRadius = below ? (barCorners[2] + barCorners[3]) / 2 : (barCorners[0] + barCorners[1]) / 2
                // A bar inset less than the body's radius meets the body inside its rounded
                // edge. The rest of that arc continues behind the bar.
                let inset = CGFloat(bar.lo - minX)
                let hidden = inset < bodyRadius ? bodyRadius - (bodyRadius * bodyRadius - (bodyRadius - inset) * (bodyRadius - inset)).squareRoot() : 0
                let edge = borderWidth(px: px, w: w, h: h, interior: body, seed: seed, tolerance: tolerance, scale: scale)
                let main = CGRect(x: body.minX - edge, y: below ? body.minY - edge : body.minY - hidden,
                                  width: body.width + edge * 2, height: body.height + edge + hidden).intersection(bounds)
                let part = InputContour.Part(rect: barRect.insetBy(dx: -edge, dy: 0).union(CGRect(x: barRect.minX - edge, y: below ? barRect.maxY : barRect.minY - edge, width: barRect.width + edge * 2, height: edge)),
                                             radius: min(barRadius + edge, barRect.width / 2), style: .circular, corners: below ? .bottom : .top)
                return InputSurface(rect: main, radius: min(bodyRadius + edge, min(main.width, main.height) / 2), capsule: false, corners: .all, bars: [part])
            }
        }

        let edge = borderWidth(px: px, w: w, h: h, interior: interior, seed: seed, tolerance: tolerance, scale: scale)
        let field = CGRect(x: interior.minX - edge, y: interior.minY - (top.divided ? 0 : edge),
                           width: interior.width + edge * 2,
                           height: interior.height + (top.divided ? 0 : edge) + (bottom.divided ? 0 : edge)).intersection(bounds)
        let corners = cornerRadii(inside: inside, w: w, interior: interior)
        // A clipped field must still show its designed shape on the far side. Square
        // corners against a window edge are a sidebar or pane, not a field.
        if !touched.isEmpty {
            let far = touched == .bottom ? [0, 1] : touched == .top ? [2, 3] : touched == .left ? [1, 3] : [0, 2]
            guard far.allSatisfy({ corners[$0] >= 3 * scale }) else { trace?("square pane against the window edge"); return nil }
        }
        let upper = (corners[0] + corners[1]) / 2, lower = (corners[2] + corners[3]) / 2
        let limit = min(field.width, field.height) / 2
        // A field joined to a list keeps its outer corners and squares the joined side.
        if max(upper, lower) >= 3 * scale, min(upper, lower) < max(upper, lower) * 0.35 {
            return InputSurface(rect: field, radius: min(max(upper, lower) + edge, limit), capsule: false,
                                corners: upper > lower ? .top : .bottom, bars: [])
        }
        let radius = min((corners.sorted()[1] + corners.sorted()[2]) / 2 + edge, limit)
        let capsule = radius >= field.height * 0.45 && field.width >= field.height * 2
        return InputSurface(rect: field, radius: capsule ? field.height / 2 : radius, capsule: capsule, corners: .all, bars: [])
    }

    /// A run of equally wide rows, clearly narrower than the body, where the body ends.
    /// Rounded corners narrow row by row and never form such a run.
    private static func attachedBar(extents: [Int: (lo: Int, hi: Int)], from start: Int, to end: Int,
                                    bodyLo: Int, bodyHi: Int, scale: CGFloat) -> (lo: Int, hi: Int, join: Int)? {
        let step = end >= start ? 1 : -1
        let rows = Array(stride(from: start, through: end, by: step))
        let minimum = Int(ceil(scale * 4)), narrower = Int(ceil(scale * 3))
        var index = 0
        while index < rows.count {
            guard let first = extents[rows[index]] else { return nil }
            var run = index + 1
            while run < rows.count, let next = extents[rows[run]], abs(next.lo - first.lo) <= 1, abs(next.hi - first.hi) <= 1 { run += 1 }
            if run - index >= minimum, first.lo >= bodyLo + narrower, first.hi <= bodyHi - narrower {
                // The bar must reach the end of the field, apart from its own rounded corners.
                let remaining = rows[run...].compactMap { extents[$0] }
                guard remaining.allSatisfy({ $0.lo >= first.lo - 1 && $0.hi <= first.hi + 1 }) else { return nil }
                return (first.lo, first.hi, rows[index])
            }
            index = run
        }
        return nil
    }

    /// Borders and antialiased edges are not part of the fill but belong to the field.
    private static func borderWidth(px: [UInt8], w: Int, h: Int, interior: CGRect, seed: (Int, Int, Int), tolerance: Int, scale: CGFloat) -> CGFloat {
        let limit = Int(ceil(scale * 1.5))
        let reference = 4 * Int(ceil(scale)) + limit
        func mean(_ points: [(Int, Int)]) -> (Int, Int, Int)? {
            let valid = points.filter { $0.0 >= 0 && $0.1 >= 0 && $0.0 < w && $0.1 < h }
            guard !valid.isEmpty else { return nil }
            var s = (0, 0, 0)
            for (x, y) in valid { let i = (y * w + x) * 4; s.0 += Int(px[i]); s.1 += Int(px[i + 1]); s.2 += Int(px[i + 2]) }
            return (s.0 / valid.count, s.1 / valid.count, s.2 / valid.count)
        }
        let minX = Int(interior.minX), maxX = Int(interior.maxX) - 1, minY = Int(interior.minY), maxY = Int(interior.maxY) - 1
        let xs = stride(from: minX + Int(interior.width) / 4, through: maxX - Int(interior.width) / 4, by: 1).map { $0 }
        let ys = stride(from: minY + Int(interior.height) / 4, through: maxY - Int(interior.height) / 4, by: 1).map { $0 }
        let sides: [(Int) -> [(Int, Int)]] = [
            { k in xs.map { ($0, minY - k) } }, { k in xs.map { ($0, maxY + k) } },
            { k in ys.map { (minX - k, $0) } }, { k in ys.map { (maxX + k, $0) } }
        ]
        var widths = [Int]()
        for side in sides {
            guard let page = mean(side(reference)) else { continue }
            var width = limit
            for k in 1...limit {
                guard let c = mean(side(k)) else { break }
                if max(abs(c.0 - page.0), abs(c.1 - page.1), abs(c.2 - page.2)) <= 4 { width = k - 1; break }
            }
            widths.append(width)
        }
        guard !widths.isEmpty else { return round(scale * 0.5) }
        return CGFloat(widths.sorted()[widths.count / 2])
    }

    /// Fits a circular corner to the fill's measured edge: top left, top right, bottom left, bottom right.
    private static func cornerRadii(inside: [UInt8], w: Int, interior: CGRect) -> [CGFloat] {
        let minX = Int(interior.minX), maxX = Int(interior.maxX) - 1, minY = Int(interior.minY), maxY = Int(interior.maxY) - 1
        let limit = Int(min(interior.width, interior.height) / 2)
        guard limit >= 2 else { return [0, 0, 0, 0] }
        var radii = [CGFloat]()
        for (top, left) in [(true, true), (true, false), (false, true), (false, false)] {
            var insets = [CGFloat]()
            for row in 0..<limit {
                let y = top ? minY + row : maxY - row
                var inset = limit
                for step in 0..<limit {
                    let x = left ? minX + step : maxX - step
                    if inside[y * w + x] == 1 { inset = step; break }
                }
                insets.append(CGFloat(inset))
            }
            var best: (radius: CGFloat, error: CGFloat) = (0, .greatestFiniteMagnitude)
            var r: CGFloat = 0
            while r <= CGFloat(limit) {
                var error: CGFloat = 0
                for (row, inset) in insets.enumerated() {
                    let t = CGFloat(row) + 0.5
                    let expected = t < r ? r - (r * r - (r - t) * (r - t)).squareRoot() : 0
                    error += (expected - inset) * (expected - inset)
                }
                if error < best.error { best = (r, error) }
                r += 0.5
            }
            radii.append(best.radius)
        }
        return radii
    }
}
