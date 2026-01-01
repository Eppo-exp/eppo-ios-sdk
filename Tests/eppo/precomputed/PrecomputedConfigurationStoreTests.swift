import XCTest
@testable import EppoFlagging

class PrecomputedConfigurationStoreTests: XCTestCase {
    
    var store: PrecomputedConfigurationStore!
    
    override func setUp() {
        super.setUp()
        PrecomputedConfigurationStore.clearPersistentCache()
    }
    
    override func tearDown() {
        PrecomputedConfigurationStore.clearPersistentCache()
        store = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitializationWithPersistentCache() {
        store = PrecomputedConfigurationStore(withPersistentCache: true)
        XCTAssertNil(store.getConfiguration())
        XCTAssertFalse(store.isInitialized())
    }
    
    
    // MARK: - Configuration Storage Tests
    
    func testSetAndGetConfiguration() {
        store = PrecomputedConfigurationStore(withPersistentCache: false)
        
        let config = createSampleConfiguration()
        store.setConfiguration(config)
        
        let retrieved = store.getConfiguration()
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.salt, base64Encode("test-salt"))
        XCTAssertEqual(retrieved?.format, "PRECOMPUTED")
        XCTAssertEqual(retrieved?.flags.count, 2)
        XCTAssertTrue(store.isInitialized())
    }
    
    func testGetFlagByKey() {
        store = PrecomputedConfigurationStore(withPersistentCache: false)
        
        let config = createSampleConfiguration()
        store.setConfiguration(config)
        
        let flag1 = store.getFlag(forKey: "flag1")
        XCTAssertNotNil(flag1)
        XCTAssertEqual(flag1?.variationKey, "variation-1")
        
        let nonExistent = store.getFlag(forKey: "non-existent")
        XCTAssertNil(nonExistent)
    }
    
    func testGetKeys() {
        store = PrecomputedConfigurationStore(withPersistentCache: false)
        
        let config = createSampleConfiguration()
        store.setConfiguration(config)
        
        let keys = store.getKeys()
        XCTAssertEqual(keys.count, 2)
        XCTAssertTrue(keys.contains("flag1"))
        XCTAssertTrue(keys.contains("flag2"))
    }
    
    func testGetSalt() {
        store = PrecomputedConfigurationStore(withPersistentCache: false)
        
        XCTAssertNil(store.salt) // No configuration yet
        
        let config = createSampleConfiguration()
        store.setConfiguration(config)
        
        XCTAssertEqual(store.salt, base64Encode("test-salt"))
    }
    
    // MARK: - Expiration Tests
    
    func testIsExpired() {
        store = PrecomputedConfigurationStore(withPersistentCache: false)
        
        // No configuration should be considered expired
        XCTAssertTrue(store.isExpired())
        
        // Fresh configuration
        let config = createSampleConfiguration()
        store.setConfiguration(config)
        XCTAssertFalse(store.isExpired(ttlSeconds: 300))
        
        // Test with very short TTL
        XCTAssertTrue(store.isExpired(ttlSeconds: 0))
    }
    
    func testIsExpiredWithOldConfiguration() {
        store = PrecomputedConfigurationStore(withPersistentCache: false)
        
        // Create configuration with old fetch time
        let oldDate = Date(timeIntervalSinceNow: -400) // 400 seconds ago
        let testPrecompute = Precompute(subjectKey: "test-user", subjectAttributes: [:])
        let config = PrecomputedConfiguration(
            flags: [:],
            salt: "old-salt",
            format: "PRECOMPUTED",
            configFetchedAt: oldDate,
            subject: Subject(subjectKey: testPrecompute.subjectKey, subjectAttributes: testPrecompute.subjectAttributes)
        )
        
        store.setConfiguration(config)
        
        XCTAssertTrue(store.isExpired())
        XCTAssertFalse(store.isExpired(ttlSeconds: 500))
    }
    
    // MARK: - Thread Safety Tests
    
    func testThreadSafetyForConcurrentReads() {
        store = PrecomputedConfigurationStore(withPersistentCache: false)
        
        let config = createSampleConfiguration()
        store.setConfiguration(config)
        
        let expectation = XCTestExpectation(description: "Concurrent reads complete")
        expectation.expectedFulfillmentCount = 100
        
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = store.getConfiguration()
            _ = store.getFlag(forKey: "flag1")
            _ = store.salt
            _ = store.isInitialized()
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testThreadSafetyForConcurrentWrites() {
        store = PrecomputedConfigurationStore(withPersistentCache: false)
        
        let expectation = XCTestExpectation(description: "Concurrent writes complete")
        expectation.expectedFulfillmentCount = 50
        
        DispatchQueue.concurrentPerform(iterations: 50) { index in
            let testPrecompute = Precompute(subjectKey: "test-user-\(index)", subjectAttributes: [:])
            let config = PrecomputedConfiguration(
                flags: ["flag\(index)": createSampleFlag()],
                salt: "salt-\(index)",
                format: "PRECOMPUTED",
                configFetchedAt: Date(),
                subject: Subject(subjectKey: testPrecompute.subjectKey, subjectAttributes: testPrecompute.subjectAttributes)
            )
            store.setConfiguration(config)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        XCTAssertNotNil(store.getConfiguration())
        XCTAssertTrue(store.isInitialized())
    }
    
    // MARK: - Persistence Tests
    
    func testPersistentStorageWrite() {
        // Create store with persistence
        store = PrecomputedConfigurationStore(withPersistentCache: true)
        
        let config = createSampleConfiguration()
        store.setConfiguration(config)
        
        let expectation = XCTestExpectation(description: "Persistence write completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        let newStore = PrecomputedConfigurationStore(withPersistentCache: true)
        newStore.loadInitialConfiguration()
        
        let loaded = newStore.getConfiguration()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.salt, base64Encode("test-salt"))
        XCTAssertEqual(loaded?.flags.count, 2)
    }
    
    
    func testLoadInitialConfiguration() {
        store = PrecomputedConfigurationStore(withPersistentCache: true)
        store.setConfiguration(createSampleConfiguration())
        
        Thread.sleep(forTimeInterval: 0.5)
        
        let newStore = PrecomputedConfigurationStore(withPersistentCache: true)
        XCTAssertNil(newStore.getConfiguration()) // Not loaded yet
        
        newStore.loadInitialConfiguration()
        XCTAssertNotNil(newStore.getConfiguration()) // Now loaded
        XCTAssertEqual(newStore.getConfiguration()?.salt, base64Encode("test-salt"))
    }
    
    func testClearPersistentCache() {
        store = PrecomputedConfigurationStore(withPersistentCache: true)
        store.setConfiguration(createSampleConfiguration())
        
        Thread.sleep(forTimeInterval: 0.5)
        
        PrecomputedConfigurationStore.clearPersistentCache()
        
        let newStore = PrecomputedConfigurationStore(withPersistentCache: true)
        newStore.loadInitialConfiguration()
        XCTAssertNil(newStore.getConfiguration())
    }
    
    // MARK: - Helper Methods
    
    private func createSampleConfiguration() -> PrecomputedConfiguration {
        let flags: [String: PrecomputedFlag] = [
            "flag1": createSampleFlag(variationKey: "variation-1"),
            "flag2": createSampleFlag(variationKey: "variation-2")
        ]
        
        let testPrecompute = Precompute(subjectKey: "test-user", subjectAttributes: [:])
        return PrecomputedConfiguration(
            flags: flags,
            salt: base64Encode("test-salt"),
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            subject: Subject(subjectKey: testPrecompute.subjectKey, subjectAttributes: testPrecompute.subjectAttributes),
            configPublishedAt: Date(timeIntervalSinceNow: -3600),
            environment: Environment(name: "test")
        )
    }
    
    private func createSampleFlag(variationKey: String = "test-variation") -> PrecomputedFlag {
        return PrecomputedFlag(
            allocationKey: "test-allocation",
            variationKey: variationKey,
            variationType: .STRING,
            variationValue: .valueOf("test-value"),
            extraLogging: [:],
            doLog: true
        )
    }
}
