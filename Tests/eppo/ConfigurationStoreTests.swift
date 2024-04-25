import XCTest
@testable import eppo_flagging

final class ConfigurationStoreTests: XCTestCase {
    var configurationStore: ConfigurationStore!
    var mockRequester: ConfigurationRequester!
    
    let emptyFlagConfig = FlagConfig(subjectShards: 0, enabled: false, typedOverrides: [:], rules: [], allocations: [:])
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        mockRequester = ConfigurationRequester(httpClient: EppoHttpClientMock())
        configurationStore = ConfigurationStore(requester: mockRequester)
    }
    
    func testSetAndGetConfiguration() throws {
        configurationStore.setConfiguration(flagKey: "testFlag", config: emptyFlagConfig)
        
        XCTAssertEqual(configurationStore.getConfiguration(flagKey: "testFlag")?.enabled, emptyFlagConfig.enabled)
    }
    
    func testIsInitialized() async throws {
        XCTAssertFalse(configurationStore.isInitialized(), "Store should not be initialized before fetching configurations")
        
        configurationStore.setConfiguration(flagKey: "testFlag", config: emptyFlagConfig)
        
        XCTAssertTrue(configurationStore.isInitialized(), "Store should be initialized after fetching configurations")
    }
}
