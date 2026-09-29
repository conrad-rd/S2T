import AppKit
import Combine
import SwiftUI
import S2TCore

@MainActor final class DashboardPane: NSViewController {
    static let backgroundColor = NSColor(srgbRed: 9/255, green: 9/255, blue: 9/255, alpha: 1)
    let ledger: LocalUsageLedger
    let model = DashboardModel()
    private var observer: NSObjectProtocol?
    private var visibilitySubscription: AnyCancellable?

    init(ledger: LocalUsageLedger, state: AppState? = nil) {
        self.ledger = ledger
        super.init(nibName: nil, bundle: nil)
        if let state {
            model.availableSources = LocalUsageSource.allCases.filter { state.isProviderVisible($0.rawValue) }
            visibilitySubscription = state.$hiddenProviders.dropFirst().receive(on: RunLoop.main).sink { [weak self, weak state] _ in
                guard let state else { return }
                self?.model.availableSources = LocalUsageSource.allCases.filter { state.isProviderVisible($0.rawValue) }
            }
        }
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let host = NSHostingView(rootView: DashboardView(model: model))
        host.sizingOptions = []
        host.identifier = .init("settings.dashboard")
        host.setAccessibilityLabel("Local usage dashboard")
        view = host
        observer = NotificationCenter.default.addObserver(forName: LocalUsageLedger.changed, object: ledger, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func refresh() async { model.update(await ledger.snapshot()) }
}
