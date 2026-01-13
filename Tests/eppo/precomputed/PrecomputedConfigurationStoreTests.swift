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
        XCTAssertNil(store.getDecodedConfiguration())
        XCTAssertFalse(store.isInitialized())
    }

    // MARK: - Configuration Storage Tests

    func testSetAndGetConfiguration() {
        store = PrecomputedConfigurationStore(withPersistentCache: false)

        let config = createSampleConfiguration()
        store.setConfiguration(config)

        let retrieved = store.getDecodedConfiguration()
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.decodedSalt, "test-salt")
        XCTAssertEqual(retrieved?.format, "PRECOMPUTED")
        XCTAssertEqual(retrieved?.flags.count, 2)
        XCTAssertTrue(store.isInitialized())
    }

    func testGetFlagByKey() {
        store = PrecomputedConfigurationStore(withPersistentCache: false)

        let config = createSampleConfiguration()
        store.setConfiguration(config)

        let flag1 = store.getDecodedFlag(forKey: "flag1")
        XCTAssertNotNil(flag1)
        XCTAssertEqual(flag1?.variationKey, "variation-1")

        let nonExistent = store.getDecodedFlag(forKey: "non-existent")
        XCTAssertNil(nonExistent)
    }

    func testGetSalt() {
        store = PrecomputedConfigurationStore(withPersistentCache: false)

        XCTAssertNil(store.getDecodedConfiguration()?.decodedSalt)

        let config = createSampleConfiguration()
        store.setConfiguration(config)

        XCTAssertEqual(store.getDecodedConfiguration()?.decodedSalt, "test-salt")
    }

    // MARK: - Thread Safety Tests

    func testThreadSafetyForConcurrentReads() {
        store = PrecomputedConfigurationStore(withPersistentCache: false)

        let config = createSampleConfiguration()
        store.setConfiguration(config)

        let expectation = XCTestExpectation(description: "Concurrent reads complete")
        expectation.expectedFulfillmentCount = 100

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = store.getDecodedConfiguration()
            _ = store.getDecodedFlag(forKey: "flag1")
            _ = store.getDecodedConfiguration()?.decodedSalt
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
                salt: base64Encode("salt-\(index)"),
                format: "PRECOMPUTED",
                fetchedAt: Date(),
                subject: Subject(subjectKey: testPrecompute.subjectKey, subjectAttributes: testPrecompute.subjectAttributes),
                publishedAt: Date()
            )
            store.setConfiguration(config)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertNotNil(store.getDecodedConfiguration())
        XCTAssertTrue(store.isInitialized())
    }

    // MARK: - Persistence Tests

    func testPersistentStorageWrite() {
        // Create store with persistence
        store = PrecomputedConfigurationStore(withPersistentCache: true)

        let expectation = XCTestExpectation(description: "Persistence write completes")
        store.setConfiguration(createSampleConfiguration()) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        let newStore = PrecomputedConfigurationStore(withPersistentCache: true)
        newStore.loadInitialConfiguration()

        let loaded = newStore.getDecodedConfiguration()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.decodedSalt, "test-salt")
        XCTAssertEqual(loaded?.flags.count, 2)
    }

    func testLoadInitialConfiguration() {
        store = PrecomputedConfigurationStore(withPersistentCache: true)

        let expectation = XCTestExpectation(description: "Persistence write completes")
        store.setConfiguration(createSampleConfiguration()) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        let newStore = PrecomputedConfigurationStore(withPersistentCache: true)
        XCTAssertNil(newStore.getDecodedConfiguration()) // Not loaded yet

        newStore.loadInitialConfiguration()
        XCTAssertNotNil(newStore.getDecodedConfiguration()) // Now loaded
        XCTAssertEqual(newStore.getDecodedConfiguration()?.decodedSalt, "test-salt")
    }

    func testClearPersistentCache() {
        store = PrecomputedConfigurationStore(withPersistentCache: true)

        let expectation = XCTestExpectation(description: "Persistence write completes")
        store.setConfiguration(createSampleConfiguration()) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        PrecomputedConfigurationStore.clearPersistentCache()

        let newStore = PrecomputedConfigurationStore(withPersistentCache: true)
        newStore.loadInitialConfiguration()
        XCTAssertNil(newStore.getDecodedConfiguration())
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
            fetchedAt: Date(),
            subject: Subject(subjectKey: testPrecompute.subjectKey, subjectAttributes: testPrecompute.subjectAttributes),
            publishedAt: Date(timeIntervalSinceNow: -3600),
            environment: Environment(name: "test")
        )
    }

    private func createSampleFlag(variationKey: String = "test-variation") -> PrecomputedFlag {
        return PrecomputedFlag(
            allocationKey: base64Encode("test-allocation"),
            variationKey: base64Encode(variationKey),
            variationType: .string,
            variationValue: .valueOf(base64Encode("test-value")),
            extraLogging: [:],
            doLog: true
        )
    }
}
