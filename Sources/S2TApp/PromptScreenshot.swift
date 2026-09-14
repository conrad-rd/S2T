import AppKit

struct PromptScreenshot: Sendable {
    let png: Data
    let pointer: CGPoint
    let region: CGRect
    static var permissionGranted: Bool { CGPreflightScreenCaptureAccess() }
}
