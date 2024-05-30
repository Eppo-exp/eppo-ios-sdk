import XCTest

@testable import eppo_flagging

final class ConfigurationStoreTests: XCTestCase {
    var configurationStore: ConfigurationStore!
    var mockRequester: ConfigurationRequester!
    var configs: RACConfig!
    
    let emptyFlagConfig = FlagConfig(
        subjectShards: 0, enabled: false, typedOverrides: [:], rules: [], allocations: [:])
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        mockRequester = ConfigurationRequester(httpClient: EppoHttpClientMock())
        configurationStore = ConfigurationStore(requester: mockRequester)
        
        configs = RACConfig(flags: [
            "testFlag": emptyFlagConfig
        ])
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
