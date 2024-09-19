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
        // Clean up any existing configuration file
        cleanUpConfigurationFile()
        // Create a new instance for each test
        configurationStore = ConfigurationStore()
        
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
        // Clean up the configuration file
        cleanUpConfigurationFile()
        // Release the reference to ensure it's deallocated
        configurationStore = nil
    }
    
    private func cleanUpConfigurationFile() {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let fileURL = urls[0].appendingPathComponent("configuration.json")
        
        try? fileManager.removeItem(at: fileURL)
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
