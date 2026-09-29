import AppKit
import ScreenCaptureKit
import CoreImage
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import S2TCore

final class PromptScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private static let capturePixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    struct Frame: Sendable {
        final class Image: Sendable {
            let data: Data
            let size: CGSize
            init(data: Data, size: CGSize) { self.data = data; self.size = size }
        }
        let time: Double
        let pointer: CGPoint
        let region: CGRect
        let encoded: Image
        var image: Data { encoded.data }

        init(time: Double, pointer: CGPoint, region: CGRect, image: Data) {
            self.init(time: time, pointer: pointer, region: region, encoded: Image(data: image, size: region.size))
        }
        init(time: Double, pointer: CGPoint, region: CGRect, encoded: Image) {
            self.time = time; self.pointer = pointer; self.region = region; self.encoded = encoded
        }

        func screenshot(cropping selection: CGRect? = nil) throws -> PromptScreenshot {
            try PromptScreenshot.decode(image, pointer: pointer, region: region, selection: selection)
        }
    }

    private let queue = DispatchQueue(label: "com.s2t.prompt.frames", qos: .utility)
    private let imageQueue = DispatchQueue(label: "com.s2t.prompt.crops", qos: .userInitiated)
    private let activityLock = NSLock()
    private var enabled = false
    private let context = CIContext(options: [.cacheIntermediates: false, .priorityRequestLow: true])
    private var latest: [ObjectIdentifier: Frame] = [:]
    private struct Display: Sendable {
        let bounds: CGRect
        let displayID: CGDirectDisplayID
    }
    private var displays: [ObjectIdentifier: Display] = [:]
    private var history = PromptFrameHistory()
    private var active: Bool {
        get { activityLock.lock(); defer { activityLock.unlock() }; return enabled }
        set { activityLock.lock(); enabled = newValue; activityLock.unlock() }
    }
    @MainActor private var streams: [SCStream] = []
    @MainActor private var generation = UUID()
    @MainActor private var shareableDisplays: Task<[SCDisplay], Error>?
    @MainActor var onWarning: ((String) -> Void)?

    @MainActor func start() async throws {
        let id = UUID()
        generation = id
        guard PromptScreenshot.permissionGranted else { throw ServiceError.message("Allow Screen Recording in Prompt mode setup first.") }
        let lookup = Task { try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false).displays }
        shareableDisplays = lookup
        let shared = try await lookup.value
        try Task.checkCancellation()
        guard generation == id else { throw CancellationError() }
        let sources = try shared.map { display in
            let filter = SCContentFilter(display: display, excludingWindows: [])
            if #available(macOS 14.2, *) { filter.includeMenuBar = true }
            let bounds = CGDisplayBounds(display.displayID)
            guard filter.style == .display,
                  abs(filter.contentRect.width - bounds.width) < 1,
                  abs(filter.contentRect.height - bounds.height) < 1 else {
                throw ServiceError.message("Prompt mode could not open the entire display. No window-only recording was started.")
            }
            return (filter, bounds, display.displayID)
        }
        queue.sync { active = true; history.clear(); displays = [:]; latest = [:] }
        do {
            for (filter, bounds, displayID) in sources {
                try Task.checkCancellation()
                guard generation == id else { throw CancellationError() }
                let configuration = SCStreamConfiguration()
                configuration.width = Int(ceil(bounds.width / 2)) * 2
                configuration.height = Int(ceil(bounds.height / 2)) * 2
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 4)
                configuration.queueDepth = 3
                configuration.pixelFormat = Self.capturePixelFormat
                configuration.showsCursor = false
                configuration.capturesAudio = false
                let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
                queue.sync { displays[ObjectIdentifier(stream)] = Display(bounds: bounds, displayID: displayID) }
                streams.append(stream)
                try await stream.startCapture()
                guard generation == id else { try? await stream.stopCapture(); throw CancellationError() }
            }
            guard !streams.isEmpty else { throw ServiceError.message("No display is available for Prompt mode.") }

        } catch {
            // A stop during startup keeps the frames recorded so far; a failed start discards them.
            let failed = generation == id
            await stop()
            if failed { queue.sync { history.clear() } }
            throw error
        }
    }

    @MainActor func pauseSampling() {
        active = false
    }

    @MainActor func stop() async {
        generation = UUID()
        pauseSampling()
        let closing = streams
        streams = []
        for stream in closing { try? await stream.stopCapture() }
        await withCheckedContinuation { completion in
            queue.async { [self] in latest = [:]; displays = [:]; completion.resume() }
        }
    }

    @MainActor func cancel() {
        generation = UUID()
        prefetched?.capture.cancel(); prefetched = nil
        active = false
        queue.async { [self] in history.clear(); latest = [:]; displays = [:] }
        let closing = streams
        streams = []
        Task { for stream in closing { try? await stream.stopCapture() } }
    }

    func takeFrames() async -> [Frame] {
        await withCheckedContinuation { completion in
            queue.async { [self] in completion.resume(returning: history.take()) }
        }
    }

    private struct CaptureRequest: Sendable {
        let display: CGDirectDisplayID
        let area: CGRect
        let source: CGRect
        let scale: CGFloat
    }

    /// A capture started on mouse-down for the click region. The mouse-up reuses it when the
    /// gesture stays a click, so the capture overlaps the time the button is held.
    @MainActor private var prefetched: (rect: CGRect, capture: Task<CGImage, Error>)?
    @MainActor var onTiming: (([String: Double]) -> Void)?

    @MainActor private func request(for selection: CGRect) -> CaptureRequest? {
        let target = NSScreen.screens.compactMap { screen -> (id: CGDirectDisplayID, cocoa: CGRect, quartz: CGRect, scale: CGFloat, area: CGRect)? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            let area = selection.intersection(screen.frame)
            guard !area.isNull, area.width >= 4, area.height >= 4 else { return nil }
            return (id, screen.frame, CGDisplayBounds(id), screen.backingScaleFactor, area)
        }.max { $0.area.width * $0.area.height < $1.area.width * $1.area.height }
        guard let target else { return nil }
        let quartz = PromptScreenshot.quartzRect(fromCocoa: target.area, screenFrame: target.cocoa, quartzBounds: target.quartz)
        return CaptureRequest(display: target.id, area: target.area,
            source: quartz.offsetBy(dx: -target.quartz.minX, dy: -target.quartz.minY), scale: target.scale)
    }

    @MainActor private func capture(_ request: CaptureRequest) -> Task<CGImage, Error>? {
        guard let lookup = shareableDisplays else { return nil }
        return Task { @MainActor in
            guard let display = try await lookup.value.first(where: { $0.displayID == request.display }) else { throw CancellationError() }
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = request.source
            configuration.width = max(1, Int((request.source.width * request.scale).rounded()))
            configuration.height = max(1, Int((request.source.height * request.scale).rounded()))
            configuration.showsCursor = false
            configuration.captureResolution = .best
            return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []),
                configuration: configuration)
        }
    }

    /// Starts capturing a likely click region before the gesture finishes.
    @MainActor func prefetch(_ cocoaRect: CGRect) {
        let selection = cocoaRect.standardized
        prefetched = request(for: selection).flatMap(capture).map { (selection, $0) }
    }

    /// Captures the selection at the moment of the gesture, at the display's full pixel density.
    /// `preview` receives the deck thumbnail as soon as pixels arrive, before the PNG is encoded.
    /// Falls back to the latest recorded frame if the on-demand capture is unavailable.
    @MainActor func manualScreenshot(in cocoaRect: CGRect, preview: (@MainActor (CGImage?, CGRect) -> Void)? = nil,
                                     completion: @escaping @MainActor (PromptScreenshot?) -> Void) {
        let selection = cocoaRect.standardized
        let requested = ProcessInfo.processInfo.systemUptime
        let reused = prefetched?.rect == selection ? prefetched?.capture : nil
        if reused == nil { prefetched?.capture.cancel() }
        prefetched = nil
        guard let request = request(for: selection), let pending = reused ?? capture(request) else {
            frameScreenshot(in: selection, completion: completion); return
        }
        Task { @MainActor [weak self] in
            do {
                let image = try await pending.value
                let captured = ProcessInfo.processInfo.systemUptime
                let thumbnail = await Task.detached(priority: .userInitiated) { PromptScreenshot.thumbnail(from: image) }.value
                preview?(thumbnail, request.area)
                let previewed = ProcessInfo.processInfo.systemUptime
                let screenshot = await Task.detached(priority: .userInitiated) {
                    PromptScreenshot.encode(image, region: request.area, thumbnail: thumbnail)
                }.value
                self?.onTiming?(["releaseToPixels": captured - requested, "releaseToPreview": previewed - requested,
                    "encode": ProcessInfo.processInfo.systemUptime - previewed, "prefetched": reused == nil ? 0 : 1,
                    "pixels": Double(image.width * image.height)])
                completion(screenshot)
            } catch {
                guard let self else { completion(nil); return }
                self.frameScreenshot(in: selection, completion: completion)
            }
        }
    }

    @MainActor private func frameScreenshot(in selection: CGRect, completion: @escaping @MainActor (PromptScreenshot?) -> Void) {
        let screens = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, CGRect, CGRect)? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            return (id, screen.frame, CGDisplayBounds(id))
        }
        // Enqueue the snapshot before stop can clear the stream's latest frames.
        queue.async { [self] in
            var best: (frame: Frame, area: CGRect, cocoa: CGRect, quartz: CGRect)?
            for (id, cocoa, quartz) in screens {
                guard let frame = latest.first(where: { displays[$0.key]?.displayID == id })?.value else { continue }
                let area = PromptScreenshot.quartzRect(fromCocoa: selection, screenFrame: cocoa, quartzBounds: quartz).intersection(frame.region)
                guard !area.isNull, area.width >= 4, area.height >= 4 else { continue }
                if best == nil || area.width * area.height > best!.area.width * best!.area.height {
                    best = (frame, area, cocoa, quartz)
                }
            }
            let chosen = best
            imageQueue.async {
                var screenshot: PromptScreenshot?
                if let chosen, let crop = try? chosen.frame.screenshot(cropping: chosen.area) {
                    screenshot = crop.relocated(to: PromptScreenshot.cocoaRect(fromQuartz: crop.region, screenFrame: chosen.cocoa, quartzBounds: chosen.quartz))
                }
                let result = screenshot
                Task { @MainActor in completion(result) }
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard active, outputType == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return }
        let key = ObjectIdentifier(stream)
        guard let display = displays[key], let pointer = CGEvent(source: nil)?.location,
              let ticks = attachments.first?[.displayTime] as? NSNumber else { return }
        let time = AVAudioTime.seconds(forHostTime: ticks.uint64Value)
        receive(buffer: sampleBuffer.imageBuffer, status: status, time: time, pointer: pointer, key: key, bounds: display.bounds)
    }

    private func receive(buffer: CVPixelBuffer?, status: SCFrameStatus, time: Double, pointer: CGPoint,
                         key: ObjectIdentifier, bounds: CGRect) {
        guard active, time.isFinite, time > 0 else { return }
        let region = bounds
        guard region.width > 0, region.height > 0 else { return }
        let encoded: Frame.Image
        if status == .complete, let buffer {
            let image = CIImage(cvPixelBuffer: buffer)
            guard let data = context.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(),
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.72]) else { return }
            encoded = Frame.Image(data: data, size: image.extent.size)
        } else if status == .idle, let prior = latest[key] {
            encoded = prior.encoded
        } else {
            latest[key] = nil
            return
        }
        guard active else { return }
        let imagePointer = CGPoint(x: (pointer.x - region.minX) * encoded.size.width / region.width,
                                   y: (pointer.y - region.minY) * encoded.size.height / region.height)
        let frame = Frame(time: time, pointer: imagePointer, region: region, encoded: encoded)
        latest[key] = frame
        guard region.contains(pointer) else { return }
        guard history.append(frame) else {
            active = false
            Task { @MainActor [weak self] in
                self?.onWarning?("Prompt mode reached its local frame-memory limit. Earlier references are preserved; finish this prompt before continuing.")
                await self?.stop()
            }
            return
        }
    }

    @MainActor static func verifyNonblockingStop() async throws {
        let recorder = PromptScreenRecorder()
        let finish = DispatchSemaphore(value: 0)
        recorder.active = true
        await withCheckedContinuation { started in
            recorder.queue.async { started.resume(); _ = finish.wait(timeout: .now() + 0.2) }
        }
        let start = ProcessInfo.processInfo.systemUptime
        recorder.pauseSampling()
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
        finish.signal()
        _ = await recorder.takeFrames()
        guard elapsed < 20, !recorder.active else { throw ServiceError.message("Stopping capture waited for image encoding on the main thread.") }
        print(String(format: "Recorder stop: main-thread gate %.3f ms with a blocked encoder queue; no live capture.", elapsed))
    }

    static func benchmarkEncoding() throws {
        let recorder = PromptScreenRecorder()
        let keys = [NSObject(), NSObject()]
        let width = 2560, height = 1440
        var storage: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &storage) == kCVReturnSuccess,
              let buffer = storage else { throw ServiceError.message("Missing synthetic encoding buffer") }
        CVPixelBufferLockBaseAddress(buffer, [])
        let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height { for x in 0..<width {
            let offset = y * stride + x * 4
            bytes[offset] = UInt8((x / 7 + y / 11) % 256)
            bytes[offset + 1] = UInt8((x / 13 + y / 3) % 256)
            bytes[offset + 2] = UInt8((x / 19 + y / 17) % 256)
            bytes[offset + 3] = 255
        } }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let captured = try captureFixture(buffer, context: recorder.context)
        recorder.active = true
        var times: [Double] = []
        for index in 0..<12 {
            let start = CACurrentMediaTime()
            for display in 0..<2 {
                autoreleasepool {
                    recorder.receive(buffer: captured, status: .complete, time: 500 + Double(index) / 4,
                        pointer: CGPoint(x: 600, y: 400), key: ObjectIdentifier(keys[display]),
                        bounds: CGRect(x: display * width, y: 0, width: width, height: height))
                }
            }
            times.append((CACurrentMediaTime() - start) * 1000)
        }
        print(String(format: "Two generated 2560x1440 display callbacks: median %.3f ms, p95 %.3f ms; %d retained frames, %d latest displays.",
            times.sorted()[6], times.sorted()[11], recorder.history.take().count, recorder.latest.count))
        print("Capture surface bytes: \(CVPixelBufferGetDataSize(captured)); former BGRA \(CVPixelBufferGetDataSize(buffer)); same full-size source and four samples/second.")
        let idle = Frame(time: 1, pointer: .zero, region: CGRect(x: 0, y: 0, width: 2560, height: 1440), image: Data(repeating: 1, count: 512 * 1024))
        var history = PromptFrameHistory()
        var accepted = 0
        while history.append(idle) { accepted += 1 }
        guard accepted == 2400 else { throw ServiceError.message("Unchanged frames exhausted the image-byte budget early") }
        print("Unchanged 512 KiB image: \(accepted) timestamp samples retained before the frame-count limit; former byte accounting stopped after 512 samples.")
    }

    private static func captureFixture(_ source: CVPixelBuffer, context: CIContext) throws -> CVPixelBuffer {
        var storage: CVPixelBuffer?
        let width = CVPixelBufferGetWidth(source), height = CVPixelBufferGetHeight(source)
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, capturePixelFormat,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &storage) == kCVReturnSuccess,
              let buffer = storage else { throw ServiceError.message("Missing generated capture-format buffer") }
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        context.render(CIImage(cvPixelBuffer: source), to: buffer,
            bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: CGColorSpaceCreateDeviceRGB())
        return buffer
    }

    static func verifyFrameFreezing() throws -> [Frame] {
        let recorder = PromptScreenRecorder()
        let key = ObjectIdentifier(recorder)
        let bounds = CGRect(x: 0, y: 0, width: 64, height: 48)
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 64, 48, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { throw ServiceError.message("Could not create the synthetic recording buffer.") }
        func paint(_ value: Int32) {
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            memset(CVPixelBufferGetBaseAddress(pixelBuffer)!, value, CVPixelBufferGetBytesPerRow(pixelBuffer) * 48)
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }
        recorder.active = true
        paint(40)
        recorder.receive(buffer: pixelBuffer, status: .complete, time: 500, pointer: CGPoint(x: 16, y: 12), key: key, bounds: bounds)
        let original = recorder.latest[key]!.image
        paint(210)
        recorder.receive(buffer: pixelBuffer, status: .complete, time: 510, pointer: CGPoint(x: 16, y: 12), key: key, bounds: bounds)
        paint(90)
        recorder.receive(buffer: nil, status: .idle, time: 510.25, pointer: CGPoint(x: 20, y: 12), key: key, bounds: bounds)
        recorder.active = false
        recorder.receive(buffer: pixelBuffer, status: .complete, time: 511, pointer: .zero, key: key, bounds: bounds)
        let frames = recorder.history.take()
        guard frames.count == 3, frames[0].time == 500, frames[1].time == 510,
              frames[0].image == original, frames[0].image != frames[1].image,
              frames[1].encoded === frames[2].encoded, frames[2].pointer.x == 20 else {
            throw ServiceError.message("Live buffer reuse, idle frames, timestamps or stop changed a recorded image.")
        }
        recorder.active = true
        let oddBounds = CGRect(x: 0, y: 0, width: 63, height: 47)
        let center = CGPoint(x: 31.5, y: 23.5)
        recorder.receive(buffer: pixelBuffer, status: .complete, time: 512, pointer: center, key: key, bounds: oddBounds)
        recorder.receive(buffer: nil, status: .idle, time: 512.25, pointer: center, key: key, bounds: oddBounds)
        guard recorder.history.take().allSatisfy({ $0.pointer == CGPoint(x: 32, y: 24) }) else {
            throw ServiceError.message("Idle frames changed the pointer scale on an odd-sized display")
        }
        return frames
    }

    static func verifyWholeDisplay() throws -> [Frame] {
        let recorder = PromptScreenRecorder()
        let key = ObjectIdentifier(recorder)
        let bounds = CGRect(x: -96, y: 0, width: 96, height: 64)
        var storage: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 96, 64, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &storage) == kCVReturnSuccess,
              let buffer = storage else { throw ServiceError.message("Could not create the full-display fixture.") }
        recorder.active = true
        for step in 0..<2 {
            CVPixelBufferLockBaseAddress(buffer, [])
            let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<64 {
                for x in 0..<96 {
                    let leftWindow = (8..<40).contains(x) && (12..<52).contains(y)
                    let rightWindow = (56..<88).contains(x) && (12..<52).contains(y)
                    let value: UInt8 = leftWindow ? (step == 0 ? 90 : 170) : rightWindow ? (step == 0 ? 170 : 90) : 30
                    let offset = y * stride + x * 4
                    for channel in 0..<3 { bytes[offset + channel] = value }
                    bytes[offset + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            let captured = try captureFixture(buffer, context: recorder.context)
            recorder.receive(buffer: captured, status: .complete, time: 600 + Double(step),
                pointer: CGPoint(x: -72, y: 32), key: key, bounds: bounds)
        }
        let frames = recorder.history.take()
        guard frames.count == 2 else { throw ServiceError.message("Full-display fixture lost a frame.") }
        for (index, frame) in frames.enumerated() {
            guard let bitmap = NSBitmapImageRep(data: try frame.screenshot().png),
                  bitmap.pixelsWide == 96, bitmap.pixelsHigh == 64, frame.region == bounds else {
                throw ServiceError.message("Recording cropped the display fixture.")
            }
            for (x, y, expected) in [(2, 2, 30), (93, 61, 30), (24, 32, index == 0 ? 90 : 170), (72, 32, index == 0 ? 170 : 90)] {
                guard let color = bitmap.colorAt(x: x, y: y),
                      abs(color.redComponent * 255 - CGFloat(expected)) < 12 else {
                    throw ServiceError.message("Display fixture sample \(index) at \(x),\(y): expected \(expected), received \(String(describing: bitmap.colorAt(x: x, y: y))).")
                }
            }
        }
        return frames
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { [weak self] in self?.latest[ObjectIdentifier(stream)] = nil }
        Task { @MainActor [weak self] in self?.onWarning?("Screen recording stopped on a display. Earlier reference frames are preserved.") }
    }

}

struct PromptFrameHistory {
    let maximumFrames: Int
    let maximumBytes: Int
    private var frames: [PromptScreenRecorder.Frame] = []
    private var images = Set<ObjectIdentifier>()
    private var bytes = 0

    init(maximumFrames: Int = 2400, maximumBytes: Int = 256 * 1024 * 1024) {
        self.maximumFrames = maximumFrames; self.maximumBytes = maximumBytes
    }
    mutating func append(_ frame: PromptScreenRecorder.Frame) -> Bool {
        let id = ObjectIdentifier(frame.encoded)
        let additionalBytes = images.contains(id) ? 0 : frame.image.count
        guard frames.count < maximumFrames, additionalBytes <= maximumBytes - bytes else { return false }
        frames.append(frame); images.insert(id); bytes += additionalBytes
        return true
    }
    mutating func take() -> [PromptScreenRecorder.Frame] {
        let result = frames.sorted { $0.time < $1.time }
        clear()
        return result
    }
    mutating func clear() { frames = []; images = []; bytes = 0 }
}
