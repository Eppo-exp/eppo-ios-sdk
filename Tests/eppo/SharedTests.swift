import Foundation

@testable import EppoFlagging


class AssignmentLoggerSpy {
    var wasCalled = false
    var lastAssignment: Assignment?
    var logCount = 0
    
    func logger(assignment: Assignment) {
        wasCalled = true
        lastAssignment = assignment
        logCount += 1
    }
}
