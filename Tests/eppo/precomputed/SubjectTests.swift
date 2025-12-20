import XCTest
@testable import EppoFlagging

class SubjectTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testInitializationWithAttributes() {
        let attributes: [String: EppoValue] = [
            "country": .valueOf("USA"),
            "age": .valueOf(25),
            "isPremium": .valueOf(true)
        ]
        
        let subject = Subject(subjectKey: "user-123", subjectAttributes: attributes)
        
        XCTAssertEqual(subject.subjectKey, "user-123")
        XCTAssertEqual(subject.subjectAttributes.count, 3)
        XCTAssertEqual(subject.subjectAttributes["country"], .valueOf("USA"))
        XCTAssertEqual(subject.subjectAttributes["age"], .valueOf(25))
        XCTAssertEqual(subject.subjectAttributes["isPremium"], .valueOf(true))
    }
    
    func testInitializationWithoutAttributes() {
        let subject = Subject(subjectKey: "user-456")
        
        XCTAssertEqual(subject.subjectKey, "user-456")
        XCTAssertTrue(subject.subjectAttributes.isEmpty)
    }
    
    func testInitializationWithEmptyAttributes() {
        let subject = Subject(subjectKey: "user-789", subjectAttributes: [:])
        
        XCTAssertEqual(subject.subjectKey, "user-789")
        XCTAssertTrue(subject.subjectAttributes.isEmpty)
    }
    
    // MARK: - Validation Tests
    
    func testEmptySubjectKeyIsAllowed() {
        // Empty subject keys are allowed
        let subject = Subject(subjectKey: "", subjectAttributes: [:])
        XCTAssertEqual(subject.subjectKey, "")
        XCTAssertTrue(subject.subjectAttributes.isEmpty)
    }
    
    // MARK: - Codable Tests
    
    func testJSONEncodingDecoding() throws {
        let attributes: [String: EppoValue] = [
            "plan": .valueOf("enterprise"),
            "monthlySpend": .valueOf(99.99),
            "features": .valueOf(["feature1", "feature2"])
        ]
        
        let originalSubject = Subject(subjectKey: "company-123", subjectAttributes: attributes)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalSubject)
        
        let decoder = JSONDecoder()
        let decodedSubject = try decoder.decode(Subject.self, from: data)
        
        XCTAssertEqual(decodedSubject.subjectKey, originalSubject.subjectKey)
        XCTAssertEqual(decodedSubject.subjectAttributes["plan"], originalSubject.subjectAttributes["plan"])
        XCTAssertEqual(decodedSubject.subjectAttributes["monthlySpend"], originalSubject.subjectAttributes["monthlySpend"])
        XCTAssertEqual(decodedSubject.subjectAttributes["features"], originalSubject.subjectAttributes["features"])
    }
    
    func testDecodingFromJSON() throws {
        let json = """
        {
            "subjectKey": "device-xyz",
            "subjectAttributes": {
                "os": "iOS",
                "version": 17.0,
                "isTablet": false
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let subject = try decoder.decode(Subject.self, from: data)
        
        XCTAssertEqual(subject.subjectKey, "device-xyz")
        XCTAssertEqual(subject.subjectAttributes["os"], .valueOf("iOS"))
        XCTAssertEqual(try subject.subjectAttributes["version"]?.getDoubleValue(), 17.0)
        XCTAssertEqual(try subject.subjectAttributes["isTablet"]?.getBoolValue(), false)
    }
    
    func testDecodingWithNullAttributes() throws {
        let json = """
        {
            "subjectKey": "user-with-nulls",
            "subjectAttributes": {
                "name": "John",
                "middleName": null,
                "score": 100
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let subject = try decoder.decode(Subject.self, from: data)
        
        XCTAssertEqual(subject.subjectKey, "user-with-nulls")
        XCTAssertEqual(subject.subjectAttributes["name"], .valueOf("John"))
        XCTAssertTrue(subject.subjectAttributes["middleName"]?.isNull() ?? false)
        XCTAssertEqual(try subject.subjectAttributes["score"]?.getDoubleValue(), 100.0)
    }
    
    // MARK: - Equatable Tests
    
    func testEquality() {
        let subject1 = Subject(
            subjectKey: "user-123",
            subjectAttributes: ["role": .valueOf("admin")]
        )
        
        let subject2 = Subject(
            subjectKey: "user-123",
            subjectAttributes: ["role": .valueOf("admin")]
        )
        
        let subject3 = Subject(
            subjectKey: "user-456",
            subjectAttributes: ["role": .valueOf("admin")]
        )
        
        let subject4 = Subject(
            subjectKey: "user-123",
            subjectAttributes: ["role": .valueOf("user")]
        )
        
        XCTAssertEqual(subject1, subject2)
        XCTAssertNotEqual(subject1, subject3) // Different key
        XCTAssertNotEqual(subject1, subject4) // Different attributes
    }
    
    func testEqualityWithComplexAttributes() {
        let attrs1: [String: EppoValue] = [
            "tags": .valueOf(["ios", "mobile"]),
            "score": .valueOf(95.5),
            "active": .valueOf(true)
        ]
        
        let attrs2: [String: EppoValue] = [
            "tags": .valueOf(["ios", "mobile"]),
            "score": .valueOf(95.5),
            "active": .valueOf(true)
        ]
        
        let subject1 = Subject(subjectKey: "user-1", subjectAttributes: attrs1)
        let subject2 = Subject(subjectKey: "user-1", subjectAttributes: attrs2)
        
        XCTAssertEqual(subject1, subject2)
    }
    
    // MARK: - Hashable Tests
    
    func testHashableConformance() {
        let subject1 = Subject(
            subjectKey: "user-123",
            subjectAttributes: ["tier": .valueOf("gold")]
        )
        
        let subject2 = Subject(
            subjectKey: "user-123",
            subjectAttributes: ["tier": .valueOf("silver")]
        )
        
        let subject3 = Subject(
            subjectKey: "user-456",
            subjectAttributes: ["tier": .valueOf("gold")]
        )
        
        var set = Set<Subject>()
        set.insert(subject1)
        set.insert(subject2)
        set.insert(subject3)
        
        // Note: subject1 and subject2 have same key but different attributes
        // Our hash implementation only uses subjectKey, so they might collide
        // but equality check will distinguish them
        XCTAssertTrue(set.contains(subject1))
        XCTAssertTrue(set.contains(subject3))
    }
    
    // MARK: - Edge Cases
    
    func testSubjectWithManyAttributes() {
        var attributes: [String: EppoValue] = [:]
        for i in 1...100 {
            attributes["attr\(i)"] = .valueOf("value\(i)")
        }
        
        let subject = Subject(subjectKey: "user-many-attrs", subjectAttributes: attributes)
        
        XCTAssertEqual(subject.subjectAttributes.count, 100)
        XCTAssertEqual(subject.subjectAttributes["attr50"], .valueOf("value50"))
    }
    
    func testSubjectWithSpecialCharactersInKey() {
        let subject = Subject(
            subjectKey: "user@example.com",
            subjectAttributes: ["source": .valueOf("email")]
        )
        
        XCTAssertEqual(subject.subjectKey, "user@example.com")
    }
    
    func testSubjectWithUnicodeInAttributes() {
        let subject = Subject(
            subjectKey: "international-user",
            subjectAttributes: [
                "name": .valueOf("José García"),
                "city": .valueOf("São Paulo"),
                "emoji": .valueOf("🎉")
            ]
        )
        
        XCTAssertEqual(subject.subjectAttributes["name"], .valueOf("José García"))
        XCTAssertEqual(subject.subjectAttributes["city"], .valueOf("São Paulo"))
        XCTAssertEqual(subject.subjectAttributes["emoji"], .valueOf("🎉"))
    }
}