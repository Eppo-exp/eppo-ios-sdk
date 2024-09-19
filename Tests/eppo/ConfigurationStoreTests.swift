import XCTest

@testable import eppo_flagging

final class ConfigurationStoreTests: XCTestCase {
    var configurationStore: ConfigurationStore!
    var configuration: Configuration!
    
    let emptyFlagConfig = UFC_Flag(
        key: "empty",
        enabled: false,
        variationType: UFC_VariationType.string,
        variations: [:],
        allocations: [],
        totalShards: 0
    )
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        // Create a new instance for each test
        configurationStore = ConfigurationStore()
        configurationStore.clearPersistentCache()
        
        configuration = Configuration(
          flagsConfiguration: UniversalFlagConfig(
            createdAt: nil,
            flags: [
              "testFlag": emptyFlagConfig
            ]
          ),
          obfuscated: false
        )
    }
    
    override func tearDownWithError() throws {
        try super.tearDownWithError()
        
        // Release the reference to ensure it's deallocated
        configurationStore = nil
    }

    func testClearPersistentCache() throws {
        configurationStore.setConfiguration(configuration: configuration)
        XCTAssertNotNil(configurationStore.getConfiguration(), "Configuration should be set")
        
        configurationStore.clearPersistentCache()
        XCTAssertNil(configurationStore.getConfiguration(), "Configuration should be nil after clearing cache")
    }

    func testSetAndGetConfiguration() throws {
        configurationStore.setConfiguration(configuration: configuration)
        
        XCTAssertEqual(
          configurationStore.getConfiguration()?.getFlag(flagKey: "testFlag")?.enabled, emptyFlagConfig.enabled)
    }
    
    func testIsInitialized() async throws {
        XCTAssertNil(
            configurationStore.getConfiguration(),
            "Store should not be initialized before fetching configurations")
        
        configurationStore.setConfiguration(configuration: configuration)
        
        XCTAssertNotNil(
            configurationStore.getConfiguration(),
            "Store should be initialized after fetching configurations")
    }
    
}
