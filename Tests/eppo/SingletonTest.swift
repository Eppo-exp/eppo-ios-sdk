import XCTest

import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift

@testable import EppoFlagging

final class EppoTests: XCTestCase {
    var stubCallCount = 0
    var UFCTestJSON: String!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        EppoClient.resetSharedInstance()
        stubCallCount = 0
        
        let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-v1-obfuscated.json",
            withExtension: ""
        )
        UFCTestJSON = try! String(contentsOfFile: fileURL!.path)
        
        stub(condition: isHost("fscdn.eppo.cloud") || isHost("test.cloud")) { _ in
            self.stubCallCount += 1
            let stubData = self.UFCTestJSON.data(using: .utf8)!
            return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
    }
    
    func testReusingSingleton() async throws {
        let eppoClient1 = try await EppoClient.initialize(sdkKey: "mock-api-key1")
        let eppoClient2 = try await EppoClient.initialize(sdkKey: "mock-api-key1")
        XCTAssertIdentical(eppoClient1, eppoClient2)
    }
    
    func testInitializeWithDifferentSdkKey() async throws {
        let eppoClient1 = try await EppoClient.initialize(sdkKey: "mock-api-key1")
        let eppoClient2 = try await EppoClient.initialize(sdkKey: "mock-api-key2")
        XCTAssertIdentical(eppoClient1, eppoClient2, "Changing SDK key does not re-instantiate the singleton")
    }
    
    func testInitializeWithDifferentHost() async throws {
        let eppoClient1 = try await EppoClient.initialize(sdkKey: "mock-api-key1")
        let eppoClient2 = try await EppoClient.initialize(sdkKey: "mock-api-key1", host: "https://test.cloud")
        XCTAssertIdentical(eppoClient1, eppoClient2, "Changing host re-instantiates the singleton")
    }
    
    func testLoadingMultithreading() async throws {
        let expectedCount = 50
        let expectation = XCTestExpectation(description: "eppo client expectation")
        expectation.expectedFulfillmentCount = expectedCount
        
        Task {
            await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0 ..< expectedCount {
                    group.addTask {
                        _ = try await EppoClient.initialize(sdkKey: "mock-api-key")
                        _ = try await EppoClient.shared().load()
                        expectation.fulfill()
                    }
                }
            }
        }
        
        await fulfillment(of: [expectation], timeout: 5)
        XCTAssertEqual(stubCallCount, 51) // initialize + 50 `load` executions
    }
    
    func testEppoClientMultithreading() async throws {
        let expectedCount = 50
        let expectation = XCTestExpectation(description: "eppo client expectation")
        expectation.expectedFulfillmentCount = expectedCount
        
        Task {
            await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0 ..< expectedCount {
                    group.addTask {
                        _ = try await EppoClient.initialize(sdkKey: "mock-api-key")
                        _ = try? EppoClient.shared().getStringAssignment(flagKey: "some-assignment-key", subjectKey: "subject_key", subjectAttributes: [:], defaultValue: "default")
                        expectation.fulfill()
                    }
                }
            }
        }
        
        await fulfillment(of: [expectation], timeout: 5)
        XCTAssertEqual(stubCallCount, 1)
    }
}
