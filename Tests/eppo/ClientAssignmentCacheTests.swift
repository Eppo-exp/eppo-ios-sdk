//import XCTest
//
//import Foundation
//import OHHTTPStubs
//import OHHTTPStubsSwift
//
//@testable import eppo_flagging
//
//final class EppoClientAssignmentCachingTests: XCTestCase {
//    var loggerSpy: AssignmentLoggerSpy!
//    var eppoClient: EppoClient!
//    
//    override func setUpWithError() throws {
//        try super.setUpWithError()
//        loggerSpy = AssignmentLoggerSpy()
//        eppoClient = EppoClient(apiKey: "mock-api-key",
//                                assignmentLogger: loggerSpy.logger
//                                // InMemoryAssignmentCache is default enabled.
//        )
//    }
//    
//    func testLogsDuplicateAssignmentsWithoutCache() async throws {
//        // Disable the assignment cache.
//        eppoClient = EppoClient(apiKey: "mock-api-key",
//                                assignmentLogger: loggerSpy.logger,
//                                assignmentCache: nil)
//        
//        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
//            let stubData = UFCTestJSON.data(using: .utf8)!
//            return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
//        }
//        try await eppoClient.load()
//        
//        _ = try eppoClient.getNumericAssignment(
//            flagKey: "numeric_flag",
//            subjectKey: "6255e1a72a84e984aed55668",
//            defaultValue: 0
//        )
//        
//        _ = try eppoClient.getNumericAssignment(
//            flagKey: "numeric_flag",
//            subjectKey: "6255e1a72a84e984aed55668",
//            defaultValue: 0
//        )
//        
//        XCTAssertEqual(loggerSpy.logCount, 2, "Should log twice since there is no cache.")
//    }
//    
//    func testDoesNotLogDuplicateAssignmentsWithCache() async throws {
//        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
//            let stubData = UFCTestJSON.data(using: .utf8)!
//            return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
//        }
//        try await eppoClient.load()
//        
//        _ = try eppoClient.getNumericAssignment(
//            flagKey: "numeric_flag",
//            subjectKey: "6255e1a72a84e984aed55668",
//            defaultValue: 0
//        )
//        _ = try eppoClient.getNumericAssignment(
//            flagKey: "numeric_flag",
//            subjectKey: "6255e1a72a84e984aed55668",
//            defaultValue: 0
//        )
//        
//        XCTAssertEqual(loggerSpy.logCount, 1, "Should log once due to cache hit.")
//    }
//    
//    func testLogsForEachUniqueFlag() async throws {
//        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
//            let stubData = UFCTestJSON.data(using: .utf8)!
//            return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
//        }
//        try await eppoClient.load()
//        
//        _ =  try eppoClient.getStringAssignment(
//            flagKey: "start-and-end-date-test",
//            subjectKey: "6255e1a72a84e984aed55668",
//            subjectAttributes: SubjectAttributes(),
//            defaultValue: "")
//        _ = try eppoClient.getNumericAssignment(
//            flagKey: "numeric_flag",
//            subjectKey: "6255e1a72a84e984aed55668",
//            defaultValue: 0
//        )
//        
//        XCTAssertEqual(loggerSpy.logCount, 2, "Should log 2 times due to changing flags.")
//    }
//}
