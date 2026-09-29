import XCTest
@testable import S2TCore

final class GlowGradientTests: XCTestCase {
    func testOKLabReferenceRedAndNeutralMidpoint() {
        let red = OKLab.fromSRGB(SIMD3(1, 0, 0))
        XCTAssertEqual(red.x, 0.62795536, accuracy: 0.0000001)
        XCTAssertEqual(red.y, 0.22486306, accuracy: 0.0000001)
        XCTAssertEqual(red.z, 0.12584630, accuracy: 0.0000001)
        let neutral = GlowGradient(stops: [.init(position: 0, color: .zero), .init(position: 0.5, color: SIMD3(repeating: 1))])
        let midpoint = neutral.sampler.color(at: 0.25)
        for channel in 0..<3 { XCTAssertEqual(midpoint[channel], 0.38857286, accuracy: 0.000001) }
        for rgb in [SIMD3<Double>(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1), SIMD3(0.2, 0.4, 0.7)] {
            let roundTrip = OKLab.toSRGB(OKLab.fromSRGB(rgb))
            for channel in 0..<3 { XCTAssertEqual(roundTrip[channel], rgb[channel], accuracy: 0.000002) }
        }
    }

    func testUnevenStopsAndSeamUseTheSameInterpolation() {
        let black = SIMD3<Double>.zero, white = SIMD3<Double>(repeating: 1)
        let gradient = GlowGradient(stops: [
            .init(position: 0.1, color: black), .init(position: 0.3, color: white)
        ])
        let sampler = gradient.sampler
        XCTAssertEqual(sampler.color(at: 0.1), black)
        XCTAssertEqual(sampler.color(at: 0.3), white)
        for channel in 0..<3 {
            XCTAssertEqual(sampler.color(at: 0.2)[channel], 0.38857286, accuracy: 0.000001)
            XCTAssertEqual(sampler.color(at: 0.7)[channel], 0.38857286, accuracy: 0.000001)
            XCTAssertEqual(sampler.color(at: -0.000001)[channel], sampler.color(at: 0.000001)[channel], accuracy: 0.00001)
            XCTAssertEqual(sampler.color(at: -0.2)[channel], sampler.color(at: 4.8)[channel], accuracy: 0.000001)
        }
    }

    func testStopsCanCrossAndReachBothEndpointsWithoutChangingIdentity() {
        var gradient = GlowGradient()
        let moving = gradient.stops[1]
        gradient.moveStop(id: moving.id, to: 1)
        XCTAssertEqual(gradient.stops.last?.id, moving.id)
        XCTAssertEqual(gradient.stops.last?.position, 1)
        XCTAssertEqual(gradient.stops.last?.color, moving.color)
        gradient.moveStop(id: moving.id, to: 0)
        XCTAssertEqual(gradient.stops.first(where: { $0.id == moving.id })?.position, 0)
        for x in stride(from: 0.0, through: 1.0, by: 0.01) {
            let color = gradient.sampler.color(at: x)
            XCTAssertTrue((0..<3).allSatisfy { color[$0].isFinite })
        }
    }

    func testAddingMoreThanEightColorsAndKeepingOneSolidColor() {
        var gradient = GlowGradient()
        for _ in 0..<16 { gradient.addStop() }
        XCTAssertEqual(gradient.stops.count, 20)
        XCTAssertEqual(Set(gradient.stops.map(\.id)).count, 20)
        gradient.spaceEvenly()
        XCTAssertEqual(gradient.stops.map(\.position), (0..<20).map { Double($0) / 20 })
        let first = gradient.stops[0]
        for stop in gradient.stops.dropFirst() { gradient.removeStop(id: stop.id) }
        XCTAssertEqual(gradient.stops, [first])
        gradient.removeStop(id: first.id)
        XCTAssertEqual(gradient.stops.count, 1)
        XCTAssertEqual(gradient.sampler.color(at: 0.73), first.color)
    }

    func testDefaultsMatchTheAppAndLegacyFlagsDoNotDisableEditing() throws {
        XCTAssertTrue(GlowGradient().isDefault)
        XCTAssertEqual(GlowGradient.defaultStops.map(\.color), GlowColorCycle.colors.map { $0 / 255 })
        let legacy = Data(#"{"enabled":false,"stops":[{"position":0,"color":[1,0,0]},{"position":0.5,"color":[0,1,0]}]}"#.utf8)
        let migrated = try JSONDecoder().decode(GlowGradient.self, from: legacy)
        XCTAssertEqual(migrated.stops.map(\.color), [SIMD3(1, 0, 0), SIMD3(0, 1, 0)])
        XCTAssertFalse(migrated.isDefault)
        let encoded = try JSONEncoder().encode(migrated)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("enabled"))
        XCTAssertEqual(try JSONDecoder().decode(GlowGradient.self, from: encoded), migrated)
        XCTAssertTrue(try JSONDecoder().decode(GlowGradient.self, from: JSONEncoder().encode(GlowGradient())).isDefault)
    }

    func testPersistenceKeepsSeparateModesAndOldPreferences() throws {
        let old = try JSONDecoder().decode(GlowTuning.self, from: Data("{}".utf8))
        XCTAssertTrue(old.gradients.isEmpty)
        var tuning = old
        var bottom = GlowGradient()
        let id = bottom.stops[1].id
        bottom.setColor(SIMD3(0, 1, 0), id: id)
        bottom.moveStop(id: id, to: 0.9)
        bottom.addStop()
        tuning.gradients[GlowAppearance.bottom.rawValue] = bottom
        tuning.gradients[GlowAppearance.aroundInput.rawValue] = .init()
        let saved = try JSONDecoder().decode(GlowTuning.self, from: JSONEncoder().encode(tuning.normalized))
        XCTAssertEqual(saved, tuning)
        XCTAssertEqual(saved.gradients[GlowAppearance.bottom.rawValue], bottom)
        XCTAssertNil(saved.gradients[GlowAppearance.aroundNotch.rawValue])
        XCTAssertTrue(saved.gradients[GlowAppearance.aroundInput.rawValue]!.isDefault)
    }
}
