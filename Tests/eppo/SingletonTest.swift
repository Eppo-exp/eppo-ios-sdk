import XCTest

import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift

@testable import eppo_flagging

final class EppoTests: XCTestCase {
    var stubCallCount = 0
    var UFCTestJSON: String!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        EppoClient.resetSharedInstance()
        stubCallCount = 0
        
        stub(condition: isHost("fscdn.eppo.cloud") || isHost("test.cloud")) { _ in
            self.stubCallCount += 1
            let stubData = self.UFCTestJSON.data(using: .utf8)!
            return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
    }
    
    func testReusingSingleton() async throws {
        let eppoClient1 = try await EppoClient.initialize(apiKey: "mock-api-key1")
        let eppoClient2 = try await EppoClient.initialize(apiKey: "mock-api-key1")
        XCTAssertEqual(eppoClient1, eppoClient2)
    }
    
    func testChangingApiKey() async throws {
        let eppoClient1 = try await EppoClient.initialize(apiKey: "mock-api-key1")
        let eppoClient2 = try await EppoClient.initialize(apiKey: "mock-api-key2")
        XCTAssertNotEqual(eppoClient1, eppoClient2, "Changing SDK key re-instantiates the singleton")
    }
    
    func testChangingHost() async throws {
        let eppoClient1 = try await EppoClient.initialize(apiKey: "mock-api-key1")
        let eppoClient2 = try await EppoClient.initialize(apiKey: "mock-api-key1", host: "https://test.cloud")
        XCTAssertNotEqual(eppoClient1, eppoClient2, "Changing host re-instantiates the singleton")
    }
    
    func testEppoClientMultithreading() async throws {
        let expectedCount = 50
        let expectation = XCTestExpectation(description: "eppo client expectation")
        expectation.expectedFulfillmentCount = expectedCount
        
        Task {
            await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0 ..< expectedCount {
                    group.addTask {
                        try await eppoClient.loadIfNeeded()
                        _ = try? eppoClient.getStringAssignment(flagKey: "some-assignment-key", subjectKey: "subject_key", subjectAttributes: [:], defaultValue: "default")
                        expectation.fulfill()
                    }
                }
            }
        }
        
        await fulfillment(of: [expectation], timeout: 5)
        XCTAssertEqual(stubCallCount, 1)
    }
}
