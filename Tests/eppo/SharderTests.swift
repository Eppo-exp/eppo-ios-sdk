import XCTest

@testable import eppo_flagging

class SharderTests: XCTestCase {
    
    func testMD5Sharder() {
        let sharder = MD5Sharder()
        let input = "testInput"
        let totalShards = 10
        let shard = sharder.getShard(input: input, totalShards: totalShards)
        
        XCTAssertGreaterThanOrEqual(shard, 0)
        XCTAssertLessThan(shard, totalShards)
    }
    
    func testDeterministicSharder() {
        let lookup = ["key1": 2, "key2": 5]
        let sharder = DeterministicSharder(lookup: lookup)
        
        XCTAssertEqual(sharder.getShard(input: "key1", totalShards: 10), 2)
        XCTAssertEqual(sharder.getShard(input: "key2", totalShards: 10), 5)
        XCTAssertEqual(sharder.getShard(input: "key3", totalShards: 10), 0) // Default value
    }
}
