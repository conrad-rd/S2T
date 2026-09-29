import AppKit
import Combine
import SwiftUI

@main
struct S2TMain {
    @MainActor static func main() {
        UserDefaults.standard.register(defaults: ["NSStatusItemSpacing": 0, "NSStatusItemSelectionPadding": 0])
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--verify-provider-visibility") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await ProviderVisibilityProbe.run(); exit(0) }
                catch { fputs("Provider visibility: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-local-repair") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await LocalModelsProbe.repair(); exit(0) }
                catch { fputs("Local repair: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-prompt-destination") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await PromptDestinationProbe.run(); exit(0) }
                catch { fputs("Prompt destination: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-native-lifecycle") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await NativeLifecycleProbe.run(); exit(0) }
                catch { fputs("Native lifecycle: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-native-state-regressions") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await NativeStateRegressionProbe.run(); exit(0) }
                catch { fputs("Native state: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-early-transcription") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await EarlyTranscriptionProbe.run(); exit(0) }
                catch { fputs("Early transcription: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-recent-recordings") {
            app.setActivationPolicy(.prohibited)
            do { try RecentRecordingsProbe.run(); exit(0) }
            catch { fputs("Recent recordings: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--verify-meetings") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await MeetingProbe.run(); exit(0) }
                catch { fputs("Meetings: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-dashboard") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await DashboardProbe.run(); exit(0) }
                catch { fputs("Dashboard: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--bench-suite") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await BenchmarkProbe.run(); exit(0) }
                catch { fputs("Benchmark: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-appearance-startup") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await AppearanceStartupProbe.run(); exit(0) }
                catch { fputs("Appearance startup: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-recording-startup") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await RecordingStartupProbe.run(); exit(0) }
                catch { fputs("Recording startup: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-classic") {
            app.setActivationPolicy(.prohibited)
            do { try ClassicProbe.run() }
            catch { fputs("Classic: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-glass") {
            app.setActivationPolicy(.prohibited)
            do { try GlassWaveformProbe.run() }
            catch { fputs("Liquid Glass: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--diagnose-input"), CommandLine.arguments.count > flag + 1,
           let pid = pid_t(CommandLine.arguments[flag + 1]) {
            app.setActivationPolicy(.prohibited)
            let annotate = CommandLine.arguments.firstIndex(of: "--annotate").flatMap {
                CommandLine.arguments.count > $0 + 1 ? URL(fileURLWithPath: CommandLine.arguments[$0 + 1]) : nil
            }
            let title = CommandLine.arguments.firstIndex(of: "--window").flatMap {
                CommandLine.arguments.count > $0 + 1 ? CommandLine.arguments[$0 + 1] : nil
            }
            Task { @MainActor in await InputLiveProbe.run(pid: pid, windowTitle: title, annotate: annotate); exit(0) }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-input-universal") {
            app.setActivationPolicy(.prohibited)
            do { try InputUniversalProbe.run() }
            catch { fputs("Universal input: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-within-input") {
            app.setActivationPolicy(.prohibited)
            do { try WithinInputProbe.run() }
            catch { fputs("Within Input: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-window-bottom") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await WindowBottomProbe.run(); exit(0) }
                catch { fputs("Window bottom: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-input-window") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await InputWindowFallbackProbe.run(); exit(0) }
                catch { fputs("Input window fallback: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-input-resize-fields") {
            app.setActivationPolicy(.prohibited)
            do { try InputLatencyProbe.verifyResizedFields() }
            catch { fputs("Input resize fields: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-input-tracking") {
            app.setActivationPolicy(.prohibited)
            do { try InputTrackingProbe.run() }
            catch { fputs("Input tracking: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-input-motion") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await InputMotionProbe.run(); exit(0) }
                catch { fputs("Input motion: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-window-shortcuts") {
            app.setActivationPolicy(.prohibited)
            do { try WindowShortcutProbe.run() }
            catch { fputs("Window shortcuts: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--verify-input-search"), CommandLine.arguments.count > index + 1 {
            app.setActivationPolicy(.prohibited)
            do { try InputSearchProbe.run(url: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            catch { fputs("Input search: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--verify-input-browser"), CommandLine.arguments.count > index + 1 {
            app.setActivationPolicy(.prohibited)
            do { try InputBrowserPresetProbe.run(url: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            catch { fputs("Input browser preset: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-input-contour") {
            app.setActivationPolicy(.prohibited)
            do { try InputContourProbe.run() }
            catch { fputs("Input contour: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-input-resize-performance") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await InputResizePerformanceProbe.run(); exit(0) }
                catch { fputs("Input resize performance: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-input-latency") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await InputLatencyProbe.run(); exit(0) }
                catch { fputs("Input latency: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-glow-clarity") {
            app.setActivationPolicy(.prohibited)
            do { try GlowClarityProbe.run() }
            catch { fputs("Glow clarity: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-custom-gradients") {
            app.setActivationPolicy(.prohibited)
            do { try GradientEditorProbe.run() }
            catch { fputs("Custom gradients: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-gradient-cycle") {
            app.setActivationPolicy(.prohibited)
            do { try ChromaProbe.verifyColorCycle() }
            catch { fputs("Gradient cycle: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-native-speech") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await NativeSpeechProbe.run(); exit(0) }
                catch { fputs("Native speech: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-local-runtime") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await LocalModelsProbe.runtime(); exit(0) }
                catch { fputs("Local runtime: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-local-models") {
            app.setActivationPolicy(.prohibited)
            do { try LocalModelsProbe.run() }
            catch { fputs("Local models: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-writing") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await WritingPaneProbe.run(); exit(0) }
                catch { fputs("Writing: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-models-window") {
            app.setActivationPolicy(.prohibited)
            do { try ModelsWindowProbe.run() }
            catch { fputs("Models window: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-settings-sidebar") {
            app.setActivationPolicy(.prohibited)
            do { try SettingsSidebarProbe.run() }
            catch { fputs("Settings sidebar: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-settings-pages"), CommandLine.arguments.count > index + 1 {
            app.setActivationPolicy(.prohibited)
            do { try SettingsPageRenderer.run(directory: CommandLine.arguments[index + 1]) }
            catch { fputs("Settings pages: \(error.localizedDescription)\n", stderr); exit(1) }
            exit(0)
        }
        if CommandLine.arguments.contains("--verify-settings-top-bar") {
            app.setActivationPolicy(.prohibited)
            do { try SettingsTopBarProbe.run() }
            catch { fputs("Settings top bar: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-appearance-selection") {
            app.setActivationPolicy(.prohibited)
            do { try AppearanceSelectionProbe.run() }
            catch { fputs("Appearance selection: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-appearance-live") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await AppearanceLiveProbe.run(); exit(0) }
                catch { fputs("Live preview: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
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
        if CommandLine.arguments.contains("--verify-glow-consistency") {
            app.setActivationPolicy(.prohibited)
            do { try GlowConsistencyProbe.run() }
            catch { fputs("Glow consistency: \(error.localizedDescription)\n", stderr); exit(1) }
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
        if CommandLine.arguments.contains("--benchmark-selection") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await PromptCaptureFeedback.benchmarkSelectionLatency(); exit(0) }
                catch { fputs("Selection timing: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
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
        if CommandLine.arguments.contains("--verify-jev") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await JevCleanupProbe.run(); exit(0) }
                catch { fputs("Jev check: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-editing") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await EditingProbe.run(); exit(0) }
                catch { fputs("Editing check: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--dictionary-editor-fixture"), CommandLine.arguments.count > index + 1 {
            DictionaryObserverProbe.editor(directory: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            return
        }
        if CommandLine.arguments.contains("--verify-dictionary-native") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await DictionaryObserverProbe.run(); exit(0) }
                catch { fputs("Native dictionary check: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-dictionary") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await DictionaryProbe.run(); exit(0) }
                catch { fputs("Dictionary check: \(error.localizedDescription)\n", stderr); exit(1) }
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
        if CommandLine.arguments.contains("--verify-public-benchmarks") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await BenchmarkFeedProbe.runPublic(); exit(0) }
                catch { fputs("Public benchmarks: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
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
        if CommandLine.arguments.contains("--verify-credits-http") {
            app.setActivationPolicy(.prohibited)
            Task {
                do { try await CreditsProbe.runHTTP(); exit(0) }
                catch { fputs("Credits HTTP verification failed: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains(where: { ["--verify-live-streaming-billing", "--verify-streaming-lifecycle-http", "--verify-streaming-latency"].contains($0) }) {
            fputs("Direct credit streaming has been retired. Use --verify-early-transcription to verify the recording path.\n", stderr)
            exit(2)
        }
        if CommandLine.arguments.contains("--verify-assembly-streaming") {
            app.setActivationPolicy(.prohibited)
            do {
                try Microphone.verifyStreamingAudio()
                print("Assembly streaming microphone verification passed without microphone capture.")
                exit(0)
            } catch { fputs("Assembly streaming verification failed: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--verify-credits") {
            app.setActivationPolicy(.prohibited)
            Task {
                do { try await CreditsProbe.run(); exit(0) }
                catch { fputs("Credits verification failed: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--verify-build") {
            app.setActivationPolicy(.prohibited)
            let controller = MenuBarController(state: AppState(preview: true))
            controller.menuNeedsUpdate(controller.menu)
            let setup = controller.menu.items.first { $0.identifier?.rawValue == "setup" }?.submenu
            if let setup { controller.menuNeedsUpdate(setup) }
            let label = setup?.items.first { $0.identifier?.rawValue == "app.version" }?.title
                ?? DictationSettingsPane.buildLabel
            guard label == BuildIdentity.menuLabel,
                  Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == BuildIdentity.number,
                  Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == BuildIdentity.version else {
                fputs("Build identity mismatch\n", stderr)
                exit(1)
            }
            print("\(BuildIdentity.menuLabel), built \(BuildIdentity.builtAt)")
            print("\(Bundle.main.bundlePath)\nCompiled identity, packaged metadata, and Settings label match.")
            guard !controller.menu.items.contains(where: { $0.identifier?.rawValue == "policies" }) else {
                fputs("Policies must be a settings link, not a menu command\n", stderr)
                exit(1)
            }
            for slug in ["privacy", "terms", "refunds", "storage", "legal", "security"] {
                guard let url = Bundle.main.url(forResource: slug, withExtension: "html", subdirectory: "policies"),
                      let content = try? String(contentsOf: url, encoding: .utf8),
                      content.contains("info@conrad-baulig.com"), !content.contains("<script") else {
                    fputs("Packaged policy missing or unavailable: \(slug)\n", stderr)
                    exit(1)
                }
            }
            print("Six offline policy pages are available and the policies menu command is absent. No windows opened.")
            return
        }
        if CommandLine.arguments.contains("--verify-glow") {
            app.setActivationPolicy(.accessory)
            Task { @MainActor in
                do { try await GlowProbe.run(directory: FileManager.default.temporaryDirectory); exit(0) }
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
        if CommandLine.arguments.dropFirst().contains(where: { $0.hasPrefix("--") }) {
            fputs("Unknown or incomplete command; app startup refused.\n", stderr)
            exit(2)
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
        NSApp.mainMenu = ApplicationMenu.make()
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
        let selection = state.promptSelectionBorder
        shortcut.promptDragObserver = { point in selection.move(toQuartz: point) }
        shortcut.onPromptPointer = { [weak self] type, event in
            self?.state.handlePromptPointer(type: type, event: event) ?? false
        }
        state.$phase.sink { [weak self] phase in
            guard let self else { return }
            self.shortcut.capturesPromptPointer = self.state.sessionIsPrompt && phase == .recording
        }.store(in: &subscriptions)
        shortcut.onPromptAction = { [weak self] action in
            guard let self else { return }
            let starting = self.state.phase != .recording && self.state.phase != .preparing && (action == .start || action == .toggle)
            self.state.handleActivation(action, prompt: true)
            // Show why Prompt mode could not start instead of silently doing nothing.
            if starting, self.state.phase != .preparing, self.state.phase != .recording, self.state.promptStartBlocker != nil {
                self.menuBar?.appearanceWindow.showPromptMode()
            }
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            if state.meetingRecordingActive { await state.meetings.stopAndWait() }
            sender.reply(toApplicationShouldTerminate: await state.preserveForInterruption())
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        state.cancel()
        state.clipboardMonitor.stop()
        state.localModels.stop()
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
