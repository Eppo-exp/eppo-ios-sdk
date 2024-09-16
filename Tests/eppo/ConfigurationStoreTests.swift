import XCTest

@testable import eppo_flagging

final class ConfigurationStoreTests: XCTestCase {
    var configurationStore: ConfigurationStore!
    var mockRequester: ConfigurationRequesterProtocol!
    var configs: UniversalFlagConfig!
    
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
        mockRequester = HttpConfigurationRequester(httpClient: EppoHttpClientMock())
        configurationStore = ConfigurationStore()
        
        configs = UniversalFlagConfig(
            createdAt: nil,
            flags: [
                "testFlag": emptyFlagConfig
            ]
        )
    }
    
    func testSetAndGetConfiguration() throws {
        // Pass the RACConfig object to setConfigurations
        configurationStore.setConfigurations(config: configs)
        
        XCTAssertEqual(
            configurationStore.getConfiguration(flagKey: "testFlag")?.enabled, emptyFlagConfig.enabled)
    }
    
    func testIsInitialized() async throws {
        XCTAssertFalse(
            configurationStore.isInitialized(),
            "Store should not be initialized before fetching configurations")
        
        configurationStore.setConfigurations(config: configs)
        
        XCTAssertTrue(
            configurationStore.isInitialized(),
            "Store should be initialized after fetching configurations")
    }
    
}
