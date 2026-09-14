import Foundation
import CoreGraphics

public struct ComposerNode: Codable {
    public let id: Int
    public let role: String
    public let subrole: String
    public let editable: Bool
    public let frame: CGRect?
    public let parent: Int?
    public let children: [Int]
    public let childrenComplete: Bool

    public init(id: Int, role: String, subrole: String = "", editable: Bool = false, frame: CGRect?,
                parent: Int?, children: [Int] = [], childrenComplete: Bool = true) {
        self.id = id; self.role = role; self.subrole = subrole; self.editable = editable
        self.frame = frame; self.parent = parent; self.children = children; self.childrenComplete = childrenComplete
    }
}

public enum ComposerTargeting {
    public static let containerRoles: Set<String> = ["AXGroup", "AXLayoutArea", "AXScrollArea", "AXToolbar", "AXForm", "AXUnknown", "AXComboBox"]
    public static let controlRoles: Set<String> = ["AXButton", "AXPopUpButton", "AXMenuButton", "AXComboBox", "AXCheckBox", "AXRadioButton", "AXSwitch"]
    public static let accessoryRoles: Set<String> = ["AXList", "AXRow", "AXCell"]
    private static let documentRoles: Set<String> = ["AXList", "AXTable", "AXOutline", "AXWebArea", "AXWindow", "AXApplication"]

    public static func resolve(editor: Int, nodes: [Int: ComposerNode]) -> CGRect? {
        guard let leaf = nodes[editor], leaf.subrole != "AXSecureTextField",
              let original = leaf.frame, valid(original) else { return nil }
        var ancestors = [ComposerNode]()
        var parent = leaf.parent
        var seen: Set<Int> = [editor]
        while let id = parent, seen.insert(id).inserted, ancestors.count < 24, let node = nodes[id] {
            guard containerRoles.contains(node.role), !node.subrole.contains("Navigation"),
                  !["AXLandmarkMain", "AXDocumentArticle", "AXDocument"].contains(node.subrole) else { break }
            ancestors.append(node)
            parent = node.parent
        }
        // Native text views can report their entire scrolled document, not the visible editor.
        var input = original
        if let viewport = ancestors.first(where: { $0.role == "AXScrollArea" })?.frame, valid(viewport), viewport.intersects(original) {
            let clipped = viewport.intersection(original)
            if valid(clipped) { input = clipped }
        }
        var best = input
        var bestControls = Set<Int>()
        let editorAncestors = Set(ancestors.map(\.id))
        var wrappedControls = false
        for candidate in ancestors {
            guard let bounds = candidate.frame, valid(bounds), contains(bounds, input) else { continue }
            let contents = scan(candidate.id, editor: editor, editorAncestors: editorAncestors, nodes: nodes)
            guard contents.complete, !contents.otherEditor, !contents.document else { break }
            let controls = contents.controls.filter { valid($0.value) }
            guard controls.values.allSatisfy({ contains(bounds, $0) }) else { continue }
            if controls.isEmpty {
                // Measure total padding from the editor, so transparent inner wrappers do not stop the climb.
                let allowance = min(input.height * 0.65, input.width * 0.08)
                if bestControls.isEmpty, contents.text.allSatisfy({ contains(input, $0) }),
                   margins(of: bounds, around: input).allSatisfy({ $0 <= allowance }), bounds != input {
                    best = bounds
                }
                continue
            }
            let sizes = controls.values.map { min($0.width, $0.height) }.sorted()
            let unit = sizes[sizes.count / 2]
            let gap = unit * 3.2
            var footprint = input
            for decoration in contents.decorations where contains(bounds, decoration)
                && decoration.width * decoration.height <= unit * unit * 4
                && distance(input, decoration) <= gap {
                footprint = footprint.union(decoration)
            }
            var remaining = controls
            var connected = Set<Int>()
            while !remaining.isEmpty {
                let nearby = remaining.filter { distance(footprint, $0.value) <= gap }
                if nearby.isEmpty { break }
                for (id, rect) in nearby {
                    footprint = footprint.union(rect)
                    connected.insert(id)
                    remaining.removeValue(forKey: id)
                }
            }
            // Every control must belong to the local editor cluster. A remote toolbar is not a composer.
            guard remaining.isEmpty, !connected.isEmpty,
                  margins(of: bounds, around: footprint).allSatisfy({ $0 <= unit }),
                  contents.text.allSatisfy({ contains(footprint.insetBy(dx: -unit, dy: -unit), $0) }) else { continue }
            // Expanding must add controls. Equal-content outer wrappers commonly include disclaimers or page padding.
            let semanticBoundary = candidate.role == "AXForm" || ["AXLandmarkForm", "AXLandmarkSearch"].contains(candidate.subrole)
            let addsToolbar = controls.filter { !bestControls.contains($0.key) }.values.contains {
                $0.maxY > best.maxY + unit * 0.1 || $0.minY < best.minY - unit * 0.1
            }
            let completesSide = controls.filter { !bestControls.contains($0.key) }.values.contains { control in
                let joinsRight = input.maxX >= best.maxX - unit * 0.25 && control.minX >= best.maxX - 1
                    && control.minX - best.maxX <= unit * 0.25
                let joinsLeft = input.minX <= best.minX + unit * 0.25 && control.maxX <= best.minX + 1
                    && best.minX - control.maxX <= unit * 0.25
                return (joinsRight || joinsLeft) && control.maxY >= input.minY && control.minY <= input.maxY
            }
            if bestControls.isEmpty || (connected.isStrictSuperset(of: bestControls) && (addsToolbar || completesSide || semanticBoundary)) {
                best = bounds
                bestControls = connected
                wrappedControls = false
            } else if connected == bestControls, !wrappedControls, bounds != best,
                      margins(of: bounds, around: best).allSatisfy({ $0 >= -1 && $0 <= unit * 0.45 }) {
                best = bounds
                wrappedControls = true
            }
            if semanticBoundary { break }
        }
        return best
    }

    private struct Contents {
        var controls = [Int: CGRect]()
        var text = [CGRect]()
        var decorations = [CGRect]()
        var otherEditor = false
        var document = false
        var complete = true
    }

    private static func scan(_ root: Int, editor: Int, editorAncestors: Set<Int>, nodes: [Int: ComposerNode]) -> Contents {
        var result = Contents()
        var queue = [(root, 0)]
        var seen = Set<Int>()
        while !queue.isEmpty, seen.count < 192 {
            let (id, depth) = queue.removeFirst()
            if id == editor { continue }
            guard seen.insert(id).inserted else { continue }
            guard let node = nodes[id] else { result.complete = false; continue }
            if id != root {
                if !editorAncestors.contains(id), InputOutlineGeometry.isInput(role: node.role, subrole: node.subrole, editable: node.editable) {
                    // Web editors often expose a 1-point hidden textarea for keyboard/IME handling.
                    if let frame = node.frame, valid(frame) { result.otherEditor = true }
                    continue
                }
                if documentRoles.contains(node.role) {
                    // Suggestions and popup lists can be children of the field but live outside its border.
                    if let bounds = nodes[root]?.frame, let frame = node.frame, !bounds.intersects(frame) { continue }
                    if node.role == "AXList", let accessory = accessoryContents(node.id, editor: editor, nodes: nodes) {
                        result.controls.merge(accessory.controls) { first, _ in first }
                        result.text += accessory.text
                        result.decorations += accessory.decorations
                        continue
                    }
                    result.document = true
                    continue
                }
                if !editorAncestors.contains(id), controlRoles.contains(node.role), let frame = node.frame {
                    result.controls[id] = frame
                    continue
                }
                if node.role == "AXStaticText" {
                    if let frame = node.frame, valid(frame) { result.text.append(frame) }
                    continue
                }
                if node.role == "AXImage" || node.subrole == "AXEmptyGroup" {
                    if let frame = node.frame, valid(frame) { result.decorations.append(frame) }
                    continue
                }
            }
            if !node.childrenComplete { result.complete = false }
            if depth >= 32 && !node.children.isEmpty { result.complete = false; continue }
            queue.append(contentsOf: node.children.map { ($0, depth + 1) })
        }
        if !queue.isEmpty { result.complete = false }
        return result
    }

    private static func accessoryContents(_ root: Int, editor: Int, nodes: [Int: ComposerNode]) -> Contents? {
        guard let bounds = nodes[root]?.frame, valid(bounds), let input = nodes[editor]?.frame,
              !bounds.intersects(input) else { return nil }
        var result = Contents()
        var pending = [root]
        var visited = Set<Int>()
        while !pending.isEmpty, visited.count < 32 {
            let id = pending.removeFirst()
            guard visited.insert(id).inserted, let node = nodes[id], node.childrenComplete else { return nil }
            if InputOutlineGeometry.isInput(role: node.role, subrole: node.subrole, editable: node.editable) { return nil }
            if controlRoles.contains(node.role), let frame = node.frame, valid(frame) {
                result.controls[id] = frame
            } else if node.role == "AXStaticText", let frame = node.frame, valid(frame) {
                result.text.append(frame)
            } else if node.role == "AXImage", let frame = node.frame, valid(frame) {
                result.decorations.append(frame)
            } else if containerRoles.contains(node.role) || accessoryRoles.contains(node.role) {
                pending += node.children
            } else { return nil }
        }
        let sizes = result.controls.values.map { min($0.width, $0.height) }.sorted()
        guard pending.isEmpty, !sizes.isEmpty else { return nil }
        let unit = sizes[sizes.count / 2]
        guard bounds.height <= unit * 5, distance(bounds, input) <= unit * 3.2,
              result.text.allSatisfy({ $0.height <= unit * 1.5 && contains(bounds, $0) }),
              result.controls.values.allSatisfy({ contains(bounds, $0) }) else { return nil }
        return result
    }

    private static func valid(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite) && rect.width > 1 && rect.height > 1
    }
    private static func contains(_ outer: CGRect, _ inner: CGRect) -> Bool { outer.insetBy(dx: -1, dy: -1).contains(inner) }
    private static func margins(of outer: CGRect, around inner: CGRect) -> [CGFloat] {
        [inner.minX - outer.minX, outer.maxX - inner.maxX, inner.minY - outer.minY, outer.maxY - inner.maxY]
    }
    private static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        hypot(max(0, max(a.minX - b.maxX, b.minX - a.maxX)), max(0, max(a.minY - b.maxY, b.minY - a.maxY)))
    }
}
