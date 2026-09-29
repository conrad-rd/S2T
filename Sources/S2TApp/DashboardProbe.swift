import AppKit
import SwiftUI
import S2TCore

@MainActor enum DashboardProbe {
    static func run() async throws {
        let state = AppState(preview: true)
        let controller = AppearanceWindowController(state: state, presentsWindows: false)
        controller.showDashboard()
        let window = controller.window!
        window.contentView?.layoutSubtreeIfNeeded()
        let pane = controller.dashboardPane
        guard NSFont(name: DashboardTypography.postScriptName, size: 64)?.fontName == "BitcountPropSingle-Regular" else {
            throw failure("Dashboard amounts must resolve to the bundled pixel font without system fallback")
        }
        guard let logoURL = Bundle.main.url(forResource: "s2t", withExtension: "svg", subdirectory: "Dashboard"),
              NSImage(contentsOf: logoURL)?.size.width == 70 else {
            throw failure("The original dashboard logo is missing from the native view")
        }
        guard pane.view is NSHostingView<DashboardView>,
              controller.showingDashboard, !controller.preview.running,
              !window.isVisible, controller.sidebar.table.selectedRow == -1,
              controller.sidebar.logo.isDashboardSelected, pane.view.bounds.width > 600 else {
            throw failure("Dashboard must be a hidden native settings view")
        }
        for theme in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: theme)
            window.contentView?.layoutSubtreeIfNeeded()
            guard controller.sidebar.pageBackgroundColor == DashboardPane.backgroundColor,
                  controller.sidebar.backdrop.wallpaperLayer.isHidden else {
                throw failure("Sidebar and Dashboard backgrounds differ")
            }
        }
        let model = pane.model
        await pane.refresh()
        guard model.snapshot != nil, model.total == 0, model.days == 30,
              model.series.count == 30, model.strokes(0) == 0 else {
            throw failure("Empty native dashboard state is wrong")
        }
        let today = DashboardModel.utc.startOfDay(for: Date()).addingTimeInterval(43_200)
        for (id, offset, amount) in [("today", 0, "4"), ("yesterday", -1, "1"), ("old", -40, "10")] {
            var request = URLRequest(url: URL(string: "https://fixture.invalid/api/v1/requests")!)
            request.httpMethod = "POST"
            let json = "{\"id\":\"\(id)\",\"state\":\"settled\",\"chargedCredits\":\(amount)}"
            let date = DashboardModel.utc.date(byAdding: .day, value: offset, to: today)!
            let record = LocalUsageRecord.read(request: request, data: Data(json.utf8),
                                                status: 200, credits: true, now: date)!
            await state.localUsage.record(record)
        }
        await pane.refresh()
        guard model.total == 15, model.periodRecords.compactMap(\.amount).reduce(0, +) == 5,
              model.series.suffix(2).map(\.value) == [1, 4],
              model.series.suffix(2).map { model.strokes($0.value) } == [7, 28] else {
            throw failure("UTC totals or whole-stroke chart proportions are wrong")
        }
        model.days = 90
        guard model.series.count == 90,
              model.periodRecords.compactMap(\.amount).reduce(0, +) == 15 else {
            throw failure("90-day chart lost daily values")
        }
        model.days = 7
        guard model.series.count == 7,
              model.periodRecords.compactMap(\.amount).reduce(0, +) == 5 else {
            throw failure("7-day chart is wrong")
        }
        model.select(.assemblyAI)
        guard model.total == 0, model.series.count == 7 else {
            throw failure("Sources were mixed")
        }
        controller.setModelsVisible(true)
        guard controller.sidebar.pageBackgroundColor == nil else {
            throw failure("Leaving Dashboard must restore the settings background")
        }
        controller.sidebar.logo.performClick(nil)
        guard controller.showingDashboard, !pane.view.isHidden, !window.isVisible else {
            throw failure("Dashboard navigation failed")
        }
        print("PASS: native Dashboard, isolated local ledger, UTC totals, whole proportional strokes, 7/30/90-day views and hidden settings navigation. No screen capture or live credentials.")
    }
    private static func failure(_ text: String) -> NSError {
        NSError(domain: "DashboardProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
