import XCTest

@testable import eppo_flagging

final class shardTests: XCTestCase {
    func testIsShardInRangePositiveCase() throws {
        let range = ShardRange(start: 10, end: 20);
        XCTAssertTrue(Utils.isShardInRange(shard: 15, range: range));
    }

    func testIsShardInRangeNegativeCase() throws {
        let range = ShardRange(start: 10, end: 20);
        XCTAssertTrue(Utils.isShardInRange(shard: 15, range: range));
    }

    func testGetShard() throws {
        let MAX_SHARD_VALUE = 200;
        let shardValue = Utils.getShard("test-user", MAX_SHARD_VALUE);
        XCTAssertTrue(shardValue >= 0 && shardValue <= MAX_SHARD_VALUE);
    }
}
