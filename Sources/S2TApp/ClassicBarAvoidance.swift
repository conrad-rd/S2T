import AppKit
import S2TCore

@MainActor final class ClassicBarAvoidance {
    private weak var panel: NSView?
    private let horizontal: NSLayoutConstraint
    private let vertical: NSLayoutConstraint
    private var motion = ClassicBarMotion()
    private var expansion = ClassicBarMotion()
    private let height: NSLayoutConstraint
    private var configured = false
    private var classic = false
    private var timer: Timer?
    private(set) var home = CGRect.zero
    var target: CGPoint { motion.target }

    init(panel: NSView, horizontal: NSLayoutConstraint, vertical: NSLayoutConstraint, height: NSLayoutConstraint) {
        self.panel = panel
        self.horizontal = horizontal
        self.vertical = vertical
        self.height = height
    }
    func setPresentation(classic: Bool) {
        self.classic = classic
        let next = CGPoint(x: classic ? -280 : 0, y: 0)
        if !classic { motion.target = .zero }
        guard !configured || expansion.target != next || !motion.settled else { return }
        expansion.target = next
        if !configured {
            configured = true
            expansion.update(time: CACurrentMediaTime(), reducedMotion: true)
            height.constant = 340 + expansion.position.x
        } else { start() }
    }
    func update(obstacle: CGRect, in source: NSView, side: BezelSide?) {
        guard classic, let panel, let container = panel.superview, !panel.isHidden else { return }
        home = CGRect(x: container.bounds.midX - 250, y: container.bounds.minY + 364 - 60,
            width: 500, height: 60)
        let rect = container.convert(obstacle, from: source)
        let target = ClassicBarPlacement.offset(home: home, obstacle: rect, container: container.bounds,
            side: side, previous: motion.target)
        guard target != motion.target else { return }
        motion.target = target
        start()
    }
    func reset() {
        timer?.invalidate(); timer = nil
        motion = ClassicBarMotion()
        expansion.update(time: CACurrentMediaTime(), reducedMotion: true)
        height.constant = 340 + expansion.position.x
        horizontal.constant = 0
        vertical.constant = -364
    }
    private func start() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { tick(); return }
        guard timer == nil else { return }
        let now = CACurrentMediaTime()
        motion.resume(time: now)
        expansion.resume(time: now)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    private func tick() {
        motion.update(time: CACurrentMediaTime(), reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        expansion.update(time: CACurrentMediaTime(), reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        height.constant = 340 + expansion.position.x
        horizontal.constant = motion.position.x
        vertical.constant = -364 - motion.position.y
        panel?.superview?.layoutSubtreeIfNeeded()
        if motion.settled && expansion.settled { timer?.invalidate(); timer = nil }
    }
    deinit { timer?.invalidate() }
}
