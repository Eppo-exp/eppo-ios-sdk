import XCTest
import CommonCrypto
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
        let messageData = value.data(using: .utf8)!
        var digestData = Data(count: Int(CC_MD5_DIGEST_LENGTH))

        _ = digestData.withUnsafeMutableBytes { digestBytes -> UInt8 in
            messageData.withUnsafeBytes { messageBytes -> UInt8 in
                if let messageBytesBaseAddress = messageBytes.baseAddress,
                   let digestBytesBlindMemory = digestBytes.bindMemory(to: UInt8.self).baseAddress {
                    let messageLength = CC_LONG(messageData.count)
                    CC_MD5(messageBytesBaseAddress, messageLength, digestBytesBlindMemory)
                }
                return 0
            }
        }

        return digestData
    }

    // MARK: - Tests

    func testHexEncodeProducesSameResultAsBaseline() {
        let testInputs = ["", "test-input", "alice", UUID().uuidString, String(repeating: "a", count: 1000)]

        for input in testInputs {
            let data = generateTestData(input)
            XCTAssertEqual(hexEncode_slow(data), hexEncode(data))
        }
    }

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
        print("Baseline: \(slowTime * 1000)ms, Current: \(currentTime * 1000)ms, Speedup: \(speedup)x")

        XCTAssertGreaterThan(speedup, 10.0, "hexEncode should be at least 10x faster than baseline")
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
