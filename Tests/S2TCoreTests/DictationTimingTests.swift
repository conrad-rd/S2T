import XCTest
@testable import S2TCore

final class DictationTimingTests: XCTestCase {
    func testKeepsBoundedNumericHistoryIncludingFailures() throws {
        let suite = "com.s2t.timing-test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for index in 0..<25 {
            DictationTiming.record(["stopToEnd": Double(index), "invalid": .nan, "negative": -1],
                outcome: index == 24 ? "failed" : "textSent", defaults: defaults, at: Date(timeIntervalSince1970: Double(index)))
        }
        let history = try XCTUnwrap(defaults.array(forKey: DictationTiming.historyKey) as? [[String: Any]])
        XCTAssertEqual(history.count, 20)
        XCTAssertEqual(history.first?["at"] as? Double, 5)
        XCTAssertEqual(history.last?["outcome"] as? String, "failed")
        XCTAssertEqual(history.last?["durations"] as? [String: Double], ["stopToEnd": 24])
    }
}
