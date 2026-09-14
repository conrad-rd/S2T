import AppKit
import ScreenCaptureKit
import CoreImage
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import S2TCore

final class PromptScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    struct Frame: Sendable {
        let time: Double
        let pointer: CGPoint
        let region: CGRect
        let image: Data

        func screenshot() throws -> PromptScreenshot {
            guard let source = CGImageSourceCreateWithData(image as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ServiceError.message("A recorded reference frame could not be decoded.") }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw ServiceError.message("A reference image could not be encoded.") }
            CGImageDestinationAddImage(destination, cgImage, nil)
            guard CGImageDestinationFinalize(destination) else { throw ServiceError.message("A reference image could not be encoded.") }
            return PromptScreenshot(png: data as Data, pointer: pointer, region: region)
        }
    }

    private let queue = DispatchQueue(label: "com.s2t.prompt.frames", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var latest: [ObjectIdentifier: Frame] = [:]
    private var displays: [ObjectIdentifier: CGRect] = [:]
    private var history = PromptFrameHistory()
    private var active = false
    @MainActor private var streams: [SCStream] = []
    @MainActor private var generation = UUID()
    @MainActor var onWarning: ((String) -> Void)?

    @MainActor func start() async throws {
        let id = UUID()
        generation = id
        guard PromptScreenshot.permissionGranted else { throw ServiceError.message("Allow Screen Recording in Prompt mode setup first.") }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        try Task.checkCancellation()
        guard generation == id else { throw CancellationError() }
        let sources = try content.displays.map { display in
            let filter = SCContentFilter(display: display, excludingWindows: [])
            if #available(macOS 14.2, *) { filter.includeMenuBar = true }
            let bounds = CGDisplayBounds(display.displayID)
            guard filter.style == .display,
                  abs(filter.contentRect.width - bounds.width) < 1,
                  abs(filter.contentRect.height - bounds.height) < 1 else {
                throw ServiceError.message("Prompt mode could not open the entire display. No window-only recording was started.")
            }
            return (filter, bounds)
        }
        queue.sync { active = true; history.clear(); displays = [:]; latest = [:] }
        do {
            for (filter, bounds) in sources {
                try Task.checkCancellation()
                guard generation == id else { throw CancellationError() }
                let configuration = SCStreamConfiguration()
                configuration.width = Int(bounds.width)
                configuration.height = Int(bounds.height)
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 4)
                configuration.queueDepth = 3
                configuration.pixelFormat = kCVPixelFormatType_32BGRA
                configuration.showsCursor = false
                configuration.capturesAudio = false
                let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
                queue.sync { displays[ObjectIdentifier(stream)] = bounds }
                streams.append(stream)
                try await stream.startCapture()
                guard generation == id else { try? await stream.stopCapture(); throw CancellationError() }
            }
            guard !streams.isEmpty else { throw ServiceError.message("No display is available for Prompt mode.") }

        } catch { await stop(); queue.sync { history.clear() }; throw error }
    }

    @MainActor func pauseSampling() {
        queue.sync { active = false }
    }

    @MainActor func stop() async {
        generation = UUID()
        pauseSampling()
        let closing = streams
        streams = []
        for stream in closing { try? await stream.stopCapture() }
        queue.sync { latest = [:]; displays = [:] }
    }

    @MainActor func cancel() {
        generation = UUID()
        queue.sync { active = false; history.clear(); latest = [:]; displays = [:] }
        let closing = streams
        streams = []
        Task { for stream in closing { try? await stream.stopCapture() } }
    }

    func takeFrames() -> [Frame] { queue.sync { history.take() } }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard active, outputType == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return }
        let key = ObjectIdentifier(stream)
        guard let bounds = displays[key], let pointer = CGEvent(source: nil)?.location,
              let ticks = attachments.first?[.displayTime] as? NSNumber else { return }
        let time = AVAudioTime.seconds(forHostTime: ticks.uint64Value)
        receive(buffer: sampleBuffer.imageBuffer, status: status, time: time, pointer: pointer, key: key, bounds: bounds)
    }

    private func receive(buffer: CVPixelBuffer?, status: SCFrameStatus, time: Double, pointer: CGPoint,
                         key: ObjectIdentifier, bounds: CGRect) {
        guard active, time.isFinite, time > 0 else { return }
        let region = bounds
        guard region.width > 0, region.height > 0 else { return }
        let imageData: Data
        let imagePointer: CGPoint
        if status == .complete, let buffer {
            let image = CIImage(cvPixelBuffer: buffer)
            guard let encoded = context.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(),
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.72]) else { return }
            imageData = encoded
            imagePointer = CGPoint(x: (pointer.x - region.minX) * image.extent.width / region.width,
                                   y: (pointer.y - region.minY) * image.extent.height / region.height)
        } else if status == .idle, let prior = latest[key] {
            imageData = prior.image
            imagePointer = CGPoint(x: (pointer.x - region.minX) * bounds.width / region.width,
                                   y: (pointer.y - region.minY) * bounds.height / region.height)
        } else {
            latest[key] = nil
            return
        }
        let frame = Frame(time: time, pointer: imagePointer, region: region, image: imageData)
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
        let frames = recorder.takeFrames()
        guard frames.count == 3, frames[0].time == 500, frames[1].time == 510,
              frames[0].image == original, frames[0].image != frames[1].image,
              frames[1].image == frames[2].image, frames[2].pointer.x == 20 else {
            throw ServiceError.message("Live buffer reuse, idle frames, timestamps or stop changed a recorded image.")
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
            recorder.receive(buffer: buffer, status: .complete, time: 600 + Double(step),
                pointer: CGPoint(x: -72, y: 32), key: key, bounds: bounds)
        }
        let frames = recorder.takeFrames()
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
    private var bytes = 0

    init(maximumFrames: Int = 2400, maximumBytes: Int = 256 * 1024 * 1024) {
        self.maximumFrames = maximumFrames; self.maximumBytes = maximumBytes
    }
    mutating func append(_ frame: PromptScreenRecorder.Frame) -> Bool {
        guard frames.count < maximumFrames, frame.image.count <= maximumBytes - bytes else { return false }
        frames.append(frame); bytes += frame.image.count
        return true
    }
    mutating func take() -> [PromptScreenRecorder.Frame] {
        let result = frames.sorted { $0.time < $1.time }
        clear()
        return result
    }
    mutating func clear() { frames = []; bytes = 0 }
}
