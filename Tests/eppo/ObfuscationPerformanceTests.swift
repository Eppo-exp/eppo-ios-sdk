import XCTest
import CryptoKit
@testable import EppoFlagging

/// Performance tests for getMD5Hex.
/// Compares against a known-slow baseline to prevent regression.
class ObfuscationPerformanceTests: XCTestCase {

    // MARK: - Baseline

    /// Known-slow MD5 hex implementation using `String(format:)` for hex encoding.
    /// Creates intermediate string objects for each byte.
    private func getMD5Hex_slow(_ value: String, salt: String = "") -> String {
        let saltedValue = salt + value
        let messageData = Data(saltedValue.utf8)
        let digest = Insecure.MD5.hash(data: messageData)
        return Data(digest).map { String(format: "%02hhx", $0) }.joined()
    }

    // MARK: - Tests

    func testGetMD5HexIsFasterThanBaseline() {
        let testInputs = (0..<1000).map { _ in UUID().uuidString }

        let slowStart = CFAbsoluteTimeGetCurrent()
        for input in testInputs {
            _ = getMD5Hex_slow(input)
        }
        let slowTime = CFAbsoluteTimeGetCurrent() - slowStart

        let currentStart = CFAbsoluteTimeGetCurrent()
        for input in testInputs {
            _ = getMD5Hex(input)
        }
        let currentTime = CFAbsoluteTimeGetCurrent() - currentStart

        XCTAssertLessThan(currentTime, slowTime, "getMD5Hex should be faster than the baseline slow implementation")
    }

    // MARK: - XCTest Measure Benchmarks

    func testBaselinePerformance() {
        let testInputs = (0..<100).map { _ in UUID().uuidString }
        measure {
            for input in testInputs { _ = getMD5Hex_slow(input) }
        }
    }

    func testCurrentPerformance() {
        let testInputs = (0..<100).map { _ in UUID().uuidString }
        measure {
            for input in testInputs { _ = getMD5Hex(input) }
        }
    }
}
