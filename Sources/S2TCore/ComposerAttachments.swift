import Foundation
import CoreGraphics

enum ComposerAttachments {
    static func attachingBars(to target: InputOutlineTarget, boundary: Int, nodes: [Int: ComposerNode], unit: CGFloat) -> InputOutlineTarget {
        let body = target.frame
        var roots = [Int](), current = nodes[boundary]?.parent
        for _ in 0..<8 {
            guard let id = current, let node = nodes[id], ComposerTargeting.containerRoles.contains(node.role),
                  !["AXLandmarkMain", "AXDocument", "AXDocumentArticle"].contains(node.subrole) else { break }
            roots.append(id); current = node.parent
            if let frame = node.frame, frame.height > body.height + unit * 0.2 { break }
        }
        var queue = roots, seen = Set<Int>(), candidates = [CGRect]()
        while !queue.isEmpty, seen.count < 192 {
            let id = queue.removeFirst()
            guard id != boundary, seen.insert(id).inserted, let node = nodes[id], node.childrenComplete else { continue }
            guard ComposerTargeting.containerRoles.contains(node.role),
                  !["AXLandmarkMain", "AXDocument", "AXDocumentArticle"].contains(node.subrole) else { continue }
            if let frame = node.frame, valid(frame), frame.width >= body.width * 0.6,
               frame.minX >= body.minX, frame.maxX <= body.maxX,
               abs(frame.midX - body.midX) <= unit,
               frame.height <= unit * 2, frame.height >= unit * 0.4,
               ((frame.minY >= body.maxY - unit && frame.minY <= body.maxY + unit * 0.05 && frame.maxY >= body.maxY + unit * 0.4)
                || (frame.maxY <= body.minY + unit && frame.maxY >= body.minY - unit * 0.05 && frame.minY <= body.minY - unit * 0.4)),
               isAccessoryBar(id, nodes: nodes, bounds: frame) { candidates.append(frame) }
            queue += node.children
        }
        var contour = target.contour.offsetBy(dx: body.minX, dy: body.minY)
        for below in [false, true] {
            let matches = candidates.filter { ($0.midY > body.midY) == below }
            let innermost = matches.filter { outer in
                !matches.contains { inner in inner != outer && outer.contains(inner) }
            }
            guard let bar = innermost.max(by: { $0.width * $0.height < $1.width * $1.height }) else { continue }
            // Preserve the measured overlap so rounded body corners remain connected.
            let joined = CGRect(x: bar.minX, y: below ? body.maxY : bar.minY,
                width: bar.width, height: below ? bar.maxY - body.maxY : body.minY - bar.minY)
            contour.bars.append(.init(rect: joined.union(bar), radius: min(target.cornerRadius, joined.height / 2),
                style: .circular, corners: below ? .bottom : .top))
        }
        return InputOutlineTarget(contour: contour, kind: target.kind)
    }

    private static func isAccessoryBar(_ root: Int, nodes: [Int: ComposerNode], bounds: CGRect) -> Bool {
        var queue = [root], seen = Set<Int>(), hasControl = false
        while !queue.isEmpty, seen.count < 64 {
            let id = queue.removeFirst()
            guard seen.insert(id).inserted, let node = nodes[id], node.childrenComplete else { return false }
            if InputOutlineGeometry.isInput(role: node.role, subrole: node.subrole, editable: node.editable) { return false }
            if ComposerTargeting.controlRoles.contains(node.role) {
                guard let frame = node.frame, valid(frame), bounds.insetBy(dx: -1, dy: -1).contains(frame) else { return false }
                hasControl = true; continue
            }
            if ["AXStaticText", "AXImage"].contains(node.role) { continue }
            guard ComposerTargeting.containerRoles.contains(node.role),
                  !["AXLandmarkMain", "AXDocument", "AXDocumentArticle"].contains(node.subrole) else { return false }
            queue += node.children
        }
        return queue.isEmpty && hasControl
    }

    private static func valid(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
            && rect.width > 1 && rect.height > 1
    }
}
