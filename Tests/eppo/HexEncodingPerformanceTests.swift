import XCTest
import CryptoKit
@testable import EppoFlagging

/// Performance tests for hexEncode.
/// Compares against a known-slow baseline to prevent regression.
class HexEncodingPerformanceTests: XCTestCase {

    // MARK: - Baseline

    /// Known-slow hex encoding: `data.map { String(format: "%02hhx", $0) }.joined()`
    /// Creates intermediate string objects for each byte.
    private func hexEncode_slow(_ data: Data) -> String {
        return data.map { String(format: "%02hhx", $0) }.joined()
    }

    private func generateTestData(_ value: String) -> Data {
        let inputData = Data(value.utf8)
        return Data(Insecure.MD5.hash(data: inputData))
    }

    // MARK: - Tests

    func testHexEncodeIsFasterThanBaseline() {
        let testDataList = (0..<1000).map { _ in generateTestData(UUID().uuidString) }

        let slowStart = CFAbsoluteTimeGetCurrent()
        for data in testDataList {
            _ = hexEncode_slow(data)
        }
        let slowTime = CFAbsoluteTimeGetCurrent() - slowStart

        let currentStart = CFAbsoluteTimeGetCurrent()
        for data in testDataList {
            _ = hexEncode(data)
        }
        let currentTime = CFAbsoluteTimeGetCurrent() - currentStart

        let speedup = slowTime / currentTime
        XCTAssertGreaterThan(speedup, 2.0, "hexEncode should be at least 2x faster than baseline")
    }

    // MARK: - XCTest Measure Benchmarks

    func testBaselinePerformance() {
        let testDataList = (0..<100).map { _ in generateTestData(UUID().uuidString) }
        measure {
            for data in testDataList { _ = hexEncode_slow(data) }
        }
    }

    func testCurrentPerformance() {
        let testDataList = (0..<100).map { _ in generateTestData(UUID().uuidString) }
        measure {
            for data in testDataList { _ = hexEncode(data) }
        }
    }
}
