import XCTest

import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift

@testable import eppo_flagging


final class AssignmentLoggerTests: XCTestCase {
   var loggerSpy: AssignmentLoggerSpy!
   var eppoClient: EppoClient!
   var UFCTestJSON: String!
   
   override func setUpWithError() throws {
       try super.setUpWithError()
       
       let fileURL = Bundle.module.url(
           forResource: "Resources/test-data/ufc/flags-v1-obfuscated.json",
           withExtension: ""
       )
       UFCTestJSON = try! String(contentsOfFile: fileURL!.path)

       stub(condition: isHost("fscdn.eppo.cloud")) { _ in
           let stubData = self.UFCTestJSON.data(using: .utf8)!
           return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
       }
       
       loggerSpy = AssignmentLoggerSpy()
   }
   
    // todo: do obfuscation and not tests.

   func testLogger() async throws {
       eppoClient = try await EppoClient.initialize(sdkKey: "mock-api-key", assignmentLogger: loggerSpy.logger)
       
       let assignment = try eppoClient.getNumericAssignment(
           flagKey: "numeric_flag",
           subjectKey: "6255e1a72a84e984aed55668",
           subjectAttributes: SubjectAttributes(),
           defaultValue: 0)
       XCTAssertEqual(assignment, 3.1415926)
       XCTAssertTrue(loggerSpy.wasCalled)
       if let lastAssignment = loggerSpy.lastAssignment {
           XCTAssertEqual(lastAssignment.allocation, "rollout")
           XCTAssertEqual(lastAssignment.experiment, "numeric_flag-rollout")
           XCTAssertEqual(lastAssignment.variation, "pi")
           XCTAssertEqual(lastAssignment.featureFlag, "numeric_flag")
           XCTAssertEqual(lastAssignment.subject, "6255e1a72a84e984aed55668")
       } else {
           XCTFail("No last assignment was logged.")
       }
   }
}
