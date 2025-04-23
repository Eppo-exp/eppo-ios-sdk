import XCTest
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import EppoFlagging

final class EppoClientTests: XCTestCase {
    var loggerSpy: AssignmentLoggerSpy!
    var UFCTestJSON: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        loggerSpy = AssignmentLoggerSpy()
        EppoClient.resetSharedInstance()

        // Load test JSON
        let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-v1.json",
            withExtension: ""
        )
        UFCTestJSON = try! String(contentsOfFile: fileURL!.path)
    }

    override func tearDown() {
        EppoClient.resetSharedInstance()
        super.tearDown()
    }
    
    func testSingletonInitializationConcurrency() async throws {
        // Stub the network response
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let stubData = self.UFCTestJSON.data(using: .utf8)!
            return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        // Call `initialize()` twice concurrently
        async let client1 = EppoClient.initialize(
            sdkKey: "test-key",
            assignmentLogger: loggerSpy.logger
        )
        async let client2 = EppoClient.initialize(
            sdkKey: "test-key",
            assignmentLogger: loggerSpy.logger
        )

        // Wait for both to complete
        let (result1, result2) = try await (client1, client2)

        // Assert that both results are the same instance
        XCTAssertTrue(result1 === result2, "Expected both calls to return the same singleton instance")
    }

    func testSingletonInitializationAfterReset() async throws {
        // Stub the network response
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let stubData = self.UFCTestJSON.data(using: .utf8)!
            return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        // First initialization
        let client1 = try await EppoClient.initialize(
            sdkKey: "test-key",
            assignmentLogger: loggerSpy.logger
        )

        // Reset the singleton
        EppoClient.resetSharedInstance()

        // Second initialization
        let client2 = try await EppoClient.initialize(
            sdkKey: "test-key",
            assignmentLogger: loggerSpy.logger
        )

        // Assert that they are different instances
        XCTAssertFalse(client1 === client2, "Expected different instances after reset")
    }
}
