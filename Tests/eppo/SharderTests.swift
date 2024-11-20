import XCTest

@testable import EppoFlagging

class SharderTests: XCTestCase {
    
    func testMD5Sharder() {
        let sharder = MD5Sharder()
        let inputs: [(String, Int)] = [
            ("test-input", 5619),
            ("alice", 3170),
            ("bob", 7420),
            ("charlie", 7497),
        ];
        let totalShards = 10000
        inputs.forEach { (input, expectedShard) in
            XCTAssertEqual(sharder.getShard(input: input, totalShards: totalShards), expectedShard)
        }
    }
    
    func testDeterministicSharder() {
        let lookup = ["key1": 2, "key2": 5]
        let sharder = DeterministicSharder(lookup: lookup)
        
        XCTAssertEqual(sharder.getShard(input: "key1", totalShards: 10), 2)
        XCTAssertEqual(sharder.getShard(input: "key2", totalShards: 10), 5)
        XCTAssertEqual(sharder.getShard(input: "key3", totalShards: 10), 0) // Default value
    }
}
