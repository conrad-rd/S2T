import AppKit
import Combine
import SwiftUI

@main
struct S2TMain {
    @MainActor static func main() {
        UserDefaults.standard.register(defaults: ["NSStatusItemSpacing": 0, "NSStatusItemSelectionPadding": 0])
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--verify-glow-clarity") {
            app.setActivationPolicy(.prohibited)
            do { try GlowClarityProbe.run() }
            catch { fputs("Glow clarity: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-gradient-cycle") {
            app.setActivationPolicy(.prohibited)
            do { try ChromaProbe.verifyColorCycle() }
            catch { fputs("Gradient cycle: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-models-window") {
            app.setActivationPolicy(.prohibited)
            do { try ModelsWindowProbe.run() }
            catch { fputs("Models window: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-appearance-window") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await AppearanceWindowProbe.run(); exit(0) }
                catch { fputs("Appearance window: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-blur-response") {
            app.setActivationPolicy(.prohibited)
            do { try BlurResponseProbe.run() }
            catch { fputs("Blur response: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-brighter-edge") {
            app.setActivationPolicy(.prohibited)
            do { try BrighterEdgeProbe.run() }
            catch { fputs("Brighter edge: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--export-website-animations"), CommandLine.arguments.count > index + 2 {
            app.setActivationPolicy(.prohibited)
            do { try WebsiteAnimationExport.run(wallpaper: URL(fileURLWithPath: CommandLine.arguments[index + 1]), directory: URL(fileURLWithPath: CommandLine.arguments[index + 2])) }
            catch { fputs("Website animation export: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-prompt-mode") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await PromptModeProbe.run(); exit(0) }
                catch { fputs("Prompt mode: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-appearance-performance") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await AppearancePerformanceProbe.verify(); exit(0) }
                catch { fputs("Appearance performance: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--benchmark-appearance") {
            app.setActivationPolicy(.prohibited)
            do { try AppearancePerformanceProbe.run() }
            catch { fputs("Appearance benchmark failed.\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-appearance-sliders") {
            app.setActivationPolicy(.prohibited)
            do { try AppearanceSlidersProbe.run() }
            catch { fputs("Appearance sliders: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-notch-fit") {
            app.setActivationPolicy(.prohibited)
            do { try NotchFitProbe.run() }
            catch { fputs("Notch fit: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-contour-frames") {
            app.setActivationPolicy(.prohibited)
            do { try ContourFrameProbe.run() }
            catch { fputs("Contour frame check failed.\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-bezel") {
            app.setActivationPolicy(.prohibited)
            do { try BezelProbe.run() }
            catch { fputs("Bezel check: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--clipboard-relaunch-fixture"), CommandLine.arguments.count > index + 3 {
            app.setActivationPolicy(.prohibited)
            do {
                try ClipboardProbe.relaunchFixture(url: URL(fileURLWithPath: CommandLine.arguments[index + 1]),
                    boardName: CommandLine.arguments[index + 2], reading: CommandLine.arguments[index + 3] == "read")
            } catch { fputs("Clipboard relaunch fixture failed.\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-input-presets") {
            app.setActivationPolicy(.prohibited)
            do { try InputPresetProbe.run() }
            catch { fputs("Input preset check: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-input-outline") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await InputOutlineProbe.run(); exit(0) }
                catch { fputs("Input outline check: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--inspect-focused-input") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                await InputOutlineProbe.inspectFocusedInput()
                exit(0)
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-notch") {
            app.setActivationPolicy(.accessory)
            Task { @MainActor in
                do { try await NotchProbe.run(); exit(0) }
                catch { fputs("Notch check: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-clipboard") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await ClipboardProbe.run(); exit(0) }
                catch { fputs("Clipboard check: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-onboarding") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await OnboardingProbe.run(); exit(0) }
                catch { fputs("Onboarding check: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-local-endpoints") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await LocalEndpointProbe.run(); exit(0) }
                catch { fputs("Local endpoint check: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-models") {
            app.setActivationPolicy(.prohibited)
            do { try ModelSettingsProbe.run() }
            catch { fputs("Model settings check: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-api-keys") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await APIKeyProbe.run(); exit(0) }
                catch { fputs("API key check: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-menu-highlights") {
            app.setActivationPolicy(.prohibited)
            do { try MenuHighlightProbe.run() }
            catch { fputs("Menu highlight check: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--backdrop-fixture"), CommandLine.arguments.count > index + 1,
           let screen = Int(CommandLine.arguments[index + 1]) {
            BackdropFixture.run(screenIndex: screen)
            return
        }
        if CommandLine.arguments.contains("--verify-build") {
            app.setActivationPolicy(.prohibited)
            let controller = MenuBarController(state: AppState(preview: true))
            controller.menuNeedsUpdate(controller.menu)
            let setup = controller.menu.items.first { $0.identifier?.rawValue == "setup" }!.submenu!
            controller.menuNeedsUpdate(setup)
            let label = setup.items.first { $0.identifier?.rawValue == "app.version" }?.title
            guard label == BuildIdentity.menuLabel,
                  Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == BuildIdentity.number,
                  Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == BuildIdentity.version else {
                fputs("Build identity mismatch\n", stderr)
                exit(1)
            }
            print("\(BuildIdentity.menuLabel), built \(BuildIdentity.builtAt)")
            print("\(Bundle.main.bundlePath)\nCompiled identity, packaged metadata, and menu label match.")
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--verify-glow"), CommandLine.arguments.count > index + 1 {
            app.setActivationPolicy(.accessory)
            Task { @MainActor in
                do { try await GlowProbe.run(directory: URL(fileURLWithPath: CommandLine.arguments[index + 1])); exit(0) }
                catch { fputs("Glow check: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-menu-icon"), CommandLine.arguments.count > index + 1 {
            app.setActivationPolicy(.prohibited)
            do {
                let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                    let button = NSButton(frame: NSRect(x: 0, y: 0, width: 32, height: 22))
                    button.appearance = NSAppearance(named: appearance)
                    button.isBordered = false
                    button.image = MenuBarArtwork.image()
                    button.imagePosition = .imageOnly
                    button.wantsLayer = true
                    button.layer?.backgroundColor = (name == "light" ? NSColor(white: 0.96, alpha: 1) : NSColor(white: 0.12, alpha: 1)).cgColor
                    let host = NSWindow(contentRect: button.bounds, styleMask: .borderless, backing: .buffered, defer: false)
                    host.contentView = button
                    button.layoutSubtreeIfNeeded()
                    guard let bitmap = button.bitmapImageRepForCachingDisplay(in: button.bounds) else { continue }
                    button.cacheDisplay(in: button.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(name).png"))
                }
            } catch { fputs("Icon render failed: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--verify-menu"), CommandLine.arguments.count > index + 1 {
            app.setActivationPolicy(.accessory)
            Task { @MainActor in
                do { try await MenuBarProbe.run(directory: URL(fileURLWithPath: CommandLine.arguments[index + 1])); exit(0) }
                catch { fputs("Menu check: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--verify-settings"), CommandLine.arguments.count > index + 1 {
            app.setActivationPolicy(.accessory)
            Task { @MainActor in
                do { try await SettingsProbe.run(directory: URL(fileURLWithPath: CommandLine.arguments[index + 1])); exit(0) }
                catch { fputs("Settings check: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-paste-batch") {
            app.setActivationPolicy(.accessory)
            Task { @MainActor in
                do { try await PasteBatchProbe.run(); exit(0) }
                catch { fputs("Paste check: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--verify-insertion"), CommandLine.arguments.count > index + 1 {
            app.setActivationPolicy(.accessory)
            Task { @MainActor in
                do { try await InsertionProbe.run(fixtureURL: URL(fileURLWithPath: CommandLine.arguments[index + 1])); exit(0) }
                catch { fputs("Insertion check: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--measure-transcription"), CommandLine.arguments.count > index + 1 {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await LatencyProbe.run(file: CommandLine.arguments[index + 1]); exit(0) }
                catch { fputs("Timing check failed: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--check-audio-route") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in await AudioRouteProbe.run(); exit(0) }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--benchmark-glow") {
            app.setActivationPolicy(.prohibited)
            PerformanceProbe.run()
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-previews"), CommandLine.arguments.count > index + 1 {
            app.setActivationPolicy(.prohibited)
            do { try PreviewRenderer.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            catch { fputs("Preview rendering failed: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if let identifier = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: {
               $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated
           }) {
            existing.activate()
            return
        }
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var menuBar: MenuBarController?
    private var glow: GlowWindowController?
    private var subscriptions = Set<AnyCancellable>()
    private let shortcut = ActivationShortcut()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController(state: state)
        glow = GlowWindowController(state: state)
        state.$overlayVisible.removeDuplicates().sink { [weak self] visible in
            self?.glow?.update(visible: visible)
        }.store(in: &subscriptions)
        shortcut.onAction = { [weak self] action in
            guard let self else { return }
            self.state.handleActivation(action)
            if !self.state.canRecord && (action == .start || action == .toggle) { self.menuBar?.showMenu() }
        }
        shortcut.onPromptAction = { [weak self] action in
            self?.state.handleActivation(action, prompt: true)
        }
        shortcut.isListening = { [weak self] in self?.state.phase == .recording || self?.state.phase == .preparing }
        shortcut.canCancel = { [weak self] in self?.state.canCancel == true }
        shortcut.onCancel = { [weak self] in self?.state.cancel() }
        shortcut.onCapture = { [weak self] key in self?.state.saveShortcut(key, prompt: false) }
        shortcut.onPromptCapture = { [weak self] key in self?.state.saveShortcut(key, prompt: true) }
        state.requestShortcutAccess = { [weak self] in self?.shortcut.requestAccess() }
        state.refreshShortcut = { [weak self] in self?.shortcut.refresh() }
        state.testShortcut = { [weak self] in self?.shortcut.beginTest() }
        state.stopShortcutTest = { [weak self] in self?.shortcut.cancelTest() }
        state.repairFnShortcut = { [weak self] in self?.shortcut.repairFn() }
        state.beginShortcutCapture = { [weak self] in self?.shortcut.beginCapture() }
        state.beginPromptShortcutCapture = { [weak self] in self?.shortcut.beginCapture(prompt: true) }
        state.cancelShortcutCapture = { [weak self] in self?.shortcut.cancelCapture() }
        state.shortcutSettingsChanged = { [weak self] in
            guard let self, !self.state.needsInstallation else { return }
            self.shortcut.configure(key: self.state.shortcutKey, hold: self.state.holdEnabled, tap: self.state.tapEnabled)
            self.shortcut.configurePrompt(key: self.state.promptModeEnabled && !self.state.promptShortcutConflict ? self.state.promptShortcutKey : nil, hold: self.state.promptHoldEnabled, tap: self.state.promptTapEnabled)
        }
        shortcut.$isCapturing.removeDuplicates().sink { [weak self] capture in self?.state.isCapturingShortcut = capture }.store(in: &subscriptions)
        shortcut.$accessibilityGranted.removeDuplicates().sink { [weak self] granted in self?.state.shortcutAccessGranted = granted }.store(in: &subscriptions)
        shortcut.$available.removeDuplicates().sink { [weak self] available in self?.state.shortcutAvailable = available }.store(in: &subscriptions)
        shortcut.$status.removeDuplicates().sink { [weak self] status in self?.state.shortcutStatus = status }.store(in: &subscriptions)
        shortcut.$isTesting.removeDuplicates().sink { [weak self] value in self?.state.shortcutTestActive = value }.store(in: &subscriptions)
        shortcut.$testPassed.removeDuplicates().sink { [weak self] value in self?.state.shortcutTestPassed = value }.store(in: &subscriptions)
        shortcut.$testStatus.removeDuplicates().sink { [weak self] value in self?.state.shortcutTestStatus = value }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification).sink { [weak self] _ in self?.shortcut.resetGesture() }.store(in: &subscriptions)
        if !state.needsInstallation {
            shortcut.configure(key: state.shortcutKey, hold: state.holdEnabled, tap: state.tapEnabled)
            shortcut.configurePrompt(key: state.promptModeEnabled && !state.promptShortcutConflict ? state.promptShortcutKey : nil, hold: state.promptHoldEnabled, tap: state.promptTapEnabled)
            shortcut.startMonitoring()
        }
        state.refreshSetup()
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification).sink { [weak self] _ in
            self?.state.refreshSetup()
        }.store(in: &subscriptions)
        Timer.publish(every: 2, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.state.refreshSetup()
        }.store(in: &subscriptions)
        if !UserDefaults.standard.bool(forKey: "setupMenuIntroduced") || state.needsInstallation {
            UserDefaults.standard.set(true, forKey: "setupMenuIntroduced")
            DispatchQueue.main.async { [weak self] in self?.menuBar?.showMenu() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBar?.showMenu()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        state.cancel()
        state.clipboardMonitor.stop()
        if !state.needsInstallation { shortcut.stop() }
    }
}

@MainActor enum PreviewRenderer {
    static func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = AppState(preview: true)
        try snapshot(ContentView(state: state), size: NSSize(width: 930, height: 710), to: directory.appendingPathComponent("dictation.png"))
        for page in [AppPage.settings, .connections, .models, .appearance] {
            state.page = page
            try snapshot(ContentView(state: state), size: NSSize(width: 860, height: 820), to: directory.appendingPathComponent("\(page == .settings ? "settings" : page.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")).png"))
        }
        state.page = .settings
        try snapshot(ContentView(state: state), size: NSSize(width: 780, height: 630), to: directory.appendingPathComponent("settings-small.png"))
        state.page = .dictation
        state.phase = .complete
        state.output = "Let's move the design review to Thursday morning. I'd like to walk through the new onboarding flow and leave enough time for feedback.\n\nCan you send the latest screens before then?"
        state.rawTranscript = "um let's move the design review to Thursday morning I'd like to walk through the new onboarding flow and leave enough time for feedback can you send the latest screens before then"
        state.modelUsed = "Example model"
        state.routeDescription = "Selected model"
        try snapshot(ContentView(state: state), size: NSSize(width: 930, height: 710), to: directory.appendingPathComponent("result.png"))
        for (name, level) in [("glow-quiet", 0.05), ("glow-loud", 0.95)] {
            let view = BottomGlow(level: level, strength: 0.8, phase: .recording, timeOverride: 1.8).frame(width: 1440, height: 240).background(S2TTheme.background)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let cgImage = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
                throw NSError(domain: "Preview", code: 3)
            }
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        for (name, level) in [("edge-quiet", 0.05), ("edge-speaking", 0.55), ("edge-loud", 0.95)] {
            for dark in [false, true] {
                let view = BottomGlow(level: level, strength: 0.8, phase: .recording, timeOverride: 1.8)
                    .frame(width: 1440, height: 120)
                    .background(dark ? Color(white: 0.08) : Color(white: 0.96))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let cgImage = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { throw NSError(domain: "Preview", code: 3) }
                try png.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            }
        }
        for (name, phase, time, reduced) in [
            ("loading-transcribing", DictationPhase.transcribing, 0.9, false),
            ("loading-processing", DictationPhase.processing, 1.7, false),
            ("loading-reduced-motion", DictationPhase.processing, 1.7, true)
        ] {
            for dark in [false, true] {
                let view = BottomGlow(level: 1, strength: 0.8, phase: phase, timeOverride: time, reduceMotionOverride: reduced)
                    .frame(width: 1440, height: 120)
                    .background(dark ? Color(white: 0.08) : Color(white: 0.96))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let cgImage = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
                    throw NSError(domain: "Preview", code: 3)
                }
                try png.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            }
        }
    }

    private static func snapshot<V: View>(_ view: V, size: NSSize, to url: URL) throws {
        let host = NSHostingView(rootView: view.environment(\.controlActiveState, .key))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw NSError(domain: "Preview", code: 1) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "Preview", code: 2) }
        try data.write(to: url)
    }
}
