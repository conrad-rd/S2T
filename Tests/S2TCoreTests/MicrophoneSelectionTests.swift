import XCTest
@testable import S2TCore

final class MicrophoneSelectionTests: XCTestCase {
    private let devices = [
        MicrophoneCandidate(id: "headset", transport: .bluetooth),
        MicrophoneCandidate(id: "usb", transport: .other),
        MicrophoneCandidate(id: "mac", transport: .builtIn)
    ]

    func testBluetoothDefaultUsesBuiltInMicrophone() {
        XCTAssertEqual(MicrophoneSelection.resolve(selection: "", defaultID: "headset", devices: devices), "mac")
    }

    func testBuiltInIsPreferredEvenWhenSystemDefaultIsWired() {
        XCTAssertEqual(MicrophoneSelection.resolve(selection: "", defaultID: "usb", devices: devices), "mac")
    }

    func testExplicitWiredSelectionOverridesBuiltInDefault() {
        XCTAssertEqual(MicrophoneSelection.resolve(selection: "usb", defaultID: "mac", devices: devices), "usb")
    }

    func testWiredSystemDefaultIsUsedWhenNoBuiltInInputExists() {
        let external = [MicrophoneCandidate(id: "other", transport: .other)] + Array(devices.prefix(2))
        XCTAssertEqual(MicrophoneSelection.resolve(selection: "", defaultID: "usb", devices: external), "usb")
    }

    func testExplicitBluetoothSelectionIsHonored() {
        XCTAssertEqual(MicrophoneSelection.resolve(selection: "headset", defaultID: "mac", devices: devices), "headset")
    }

    func testDisconnectedExplicitInputDoesNotFallBack() {
        XCTAssertNil(MicrophoneSelection.resolve(selection: "missing", defaultID: "headset", devices: devices))
    }

    func testAutomaticNeverFallsBackToBluetooth() {
        XCTAssertNil(MicrophoneSelection.resolve(selection: "", defaultID: "headset", devices: [devices[0]]))
        XCTAssertEqual(MicrophoneSelection.resolve(selection: "", defaultID: "headset", devices: Array(devices.prefix(2))), "usb")
        XCTAssertNil(MicrophoneSelection.resolve(selection: "", defaultID: nil, devices: []))
    }
}
