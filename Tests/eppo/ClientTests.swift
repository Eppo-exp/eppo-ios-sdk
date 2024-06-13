//import XCTest
//
//import Foundation
//import OHHTTPStubs
//import OHHTTPStubsSwift
//
//@testable import eppo_flagging
//
//
//public class AssignmentLoggerSpy {
//    var wasCalled = false
//    var lastAssignment: Assignment?
//    var logCount = 0
//    
//    func logger(assignment: Assignment) {
//        wasCalled = true
//        lastAssignment = assignment
//        logCount += 1
//    }
//}
//
//final class eppoClientTests: XCTestCase {
//    var loggerSpy: AssignmentLoggerSpy!
//    var eppoClient: EppoClient!
//    
//    override func setUpWithError() throws {
//        try super.setUpWithError()
//        
//        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
//            let stubData = UFCTestJSON.data(using: .utf8)!
//            return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
//        }
//        
//        loggerSpy = AssignmentLoggerSpy()
//        eppoClient = EppoClient(apiKey: "mock-api-key", assignmentLogger: loggerSpy.logger)
//    }
//    
//    func setUpTestsWithFile(resourceName: String) async throws {
//        let fileURL = Bundle.module.url(
//            forResource: resourceName,
//            withExtension: ""
//        )
//        let testJSON: String = try! String(contentsOfFile: fileURL!.path)
//        
//        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
//            let stubData = testJSON.data(using: .utf8)!
//            return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
//        }
//        
//        loggerSpy = AssignmentLoggerSpy()
//        eppoClient = EppoClient(apiKey: "mock-api-key", assignmentLogger: loggerSpy.logger)
//    }
//    
//    func testLogger() async throws {
//        try await eppoClient.load()
//        
//        let assignment = try eppoClient.getNumericAssignment(
//            flagKey: "numeric_flag",
//            subjectKey: "6255e1a72a84e984aed55668",
//            subjectAttributes: SubjectAttributes(),
//            defaultValue: 0)
//        XCTAssertEqual(assignment, 3.1415926)
//        XCTAssertTrue(loggerSpy.wasCalled)
//        if let lastAssignment = loggerSpy.lastAssignment {
//            XCTAssertEqual(lastAssignment.allocation, "rollout")
//            XCTAssertEqual(lastAssignment.experiment, "numeric_flag-rollout")
//            XCTAssertEqual(lastAssignment.subject, "6255e1a72a84e984aed55668")
//        } else {
//            XCTFail("No last assignment was logged.")
//        }
//    }
//}
