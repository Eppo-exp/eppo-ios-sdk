import XCTest

import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift

@testable import eppo_flagging

final class EppoTests: XCTestCase {
    var stubCallCount = 0
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        EppoClient.resetInstance()
        stubCallCount = 0
        
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            self.stubCallCount += 1
            let stubData = RacTestJSON.data(using: .utf8)!
            return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
    }
    
    func testEppoClientMultithreading() async throws {
        
        let expectedCount = 50
        let expectation = XCTestExpectation(description: "eppo client expectation")
        expectation.expectedFulfillmentCount = expectedCount

        Task {
            await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0 ..< expectedCount {
                    group.addTask {
                        let eppoClient = try await EppoClient.initialize(apiKey: "mock-api-key")
                        _ = try? eppoClient.getStringAssignment("subject_key", "some-assignment-key", [:])
                        expectation.fulfill()
                    }
                }
            }
        }
        
        await fulfillment(of: [expectation], timeout: 5)
        XCTAssertEqual(stubCallCount, 1)
    }
}
