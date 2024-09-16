import XCTest

@testable import eppo_flagging

final class ConfigurationStoreTests: XCTestCase {
    var configurationStore: ConfigurationStore!
    var mockRequester: ConfigurationRequester!
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
        mockRequester = ConfigurationRequester(httpClient: EppoHttpClientMock())
        configurationStore = ConfigurationStore(requester: mockRequester)
        
        configuration = Configuration(flagsConfiguration: UniversalFlagConfig(
            createdAt: nil,
            flags: [
                "testFlag": emptyFlagConfig
            ]
        ))
    }
    
    func testSetAndGetConfiguration() throws {
        configurationStore.setConfiguration(configuration: configuration)
        
        XCTAssertEqual(
            configurationStore.getConfiguration(flagKey: "testFlag")?.enabled, emptyFlagConfig.enabled)
    }
    
    func testIsInitialized() async throws {
        XCTAssertFalse(
            configurationStore.isInitialized(),
            "Store should not be initialized before fetching configurations")
        
        configurationStore.setConfiguration(configuration: configuration)
        
        XCTAssertTrue(
            configurationStore.isInitialized(),
            "Store should be initialized after fetching configurations")
    }
    
}
