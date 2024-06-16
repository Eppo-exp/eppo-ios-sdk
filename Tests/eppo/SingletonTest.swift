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
        EppoClient.resetInstance()
        stubCallCount = 0
        
        let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-v1-obfuscated.json",
            withExtension: ""
        )
        UFCTestJSON = try! String(contentsOfFile: fileURL!.path)
        
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            self.stubCallCount += 1
            let stubData = self.UFCTestJSON.data(using: .utf8)!
            return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        
        _ = EppoClient.configure(apiKey: "mock-api-key")
    }
    
    func testEppoClientMultithreading() async throws {
        
        let expectedCount = 50
        let expectation = XCTestExpectation(description: "eppo client expectation")
        expectation.expectedFulfillmentCount = expectedCount
        
        Task {
            let eppoClient = try EppoClient.getInstance()
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
