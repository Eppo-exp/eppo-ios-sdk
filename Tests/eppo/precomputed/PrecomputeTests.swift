import XCTest
@testable import EppoFlagging

class PrecomputeTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testInitializationWithAttributes() {
        let attributes: [String: EppoValue] = [
            "country": .valueOf("USA"),
            "age": .valueOf(25),
            "isPremium": .valueOf(true)
        ]
        
        let subject = Precompute(subjectKey: "user-123", subjectAttributes: attributes)
        
        XCTAssertEqual(subject.subjectKey, "user-123")
        XCTAssertEqual(subject.subjectAttributes.count, 3)
        XCTAssertEqual(subject.subjectAttributes["country"], .valueOf("USA"))
        XCTAssertEqual(subject.subjectAttributes["age"], .valueOf(25))
        XCTAssertEqual(subject.subjectAttributes["isPremium"], .valueOf(true))
    }
    
    func testInitializationWithoutAttributes() {
        let subject = Precompute(subjectKey: "user-456")
        
        XCTAssertEqual(subject.subjectKey, "user-456")
        XCTAssertTrue(subject.subjectAttributes.isEmpty)
    }
    
    func testInitializationWithEmptyAttributes() {
        let subject = Precompute(subjectKey: "user-789", subjectAttributes: [:])
        
        XCTAssertEqual(subject.subjectKey, "user-789")
        XCTAssertTrue(subject.subjectAttributes.isEmpty)
    }
    
    // MARK: - Validation Tests
    
    func testEmptySubjectKeyIsAllowed() {
        // Empty subject keys are allowed
        let subject = Precompute(subjectKey: "", subjectAttributes: [:])
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
        
        let originalSubject = Precompute(subjectKey: "company-123", subjectAttributes: attributes)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalSubject)
        
        let decoder = JSONDecoder()
        let decodedSubject = try decoder.decode(Precompute.self, from: data)
        
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
        let subject = try decoder.decode(Precompute.self, from: data)
        
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
        let subject = try decoder.decode(Precompute.self, from: data)
        
        XCTAssertEqual(subject.subjectKey, "user-with-nulls")
        XCTAssertEqual(subject.subjectAttributes["name"], .valueOf("John"))
        XCTAssertTrue(subject.subjectAttributes["middleName"]?.isNull() ?? false)
        XCTAssertEqual(try subject.subjectAttributes["score"]?.getDoubleValue(), 100.0)
    }
    
    // MARK: - Comparison Tests
    
    func testSubjectComparison() {
        let subject1 = Precompute(
            subjectKey: "user-123",
            subjectAttributes: ["role": .valueOf("admin")]
        )
        
        let subject2 = Precompute(
            subjectKey: "user-123",
            subjectAttributes: ["role": .valueOf("admin")]
        )
        
        let subject3 = Precompute(
            subjectKey: "user-456",
            subjectAttributes: ["role": .valueOf("admin")]
        )
        
        let subject4 = Precompute(
            subjectKey: "user-123",
            subjectAttributes: ["role": .valueOf("user")]
        )
        
        // Test that subjects with same data have same properties
        XCTAssertEqual(subject1.subjectKey, subject2.subjectKey)
        XCTAssertEqual(subject1.subjectAttributes["role"], subject2.subjectAttributes["role"])
        
        // Test that subjects with different keys have different keys
        XCTAssertNotEqual(subject1.subjectKey, subject3.subjectKey)
        
        // Test that subjects with different attributes have different attributes
        XCTAssertNotEqual(subject1.subjectAttributes["role"], subject4.subjectAttributes["role"])
    }
    
    func testComparisonWithComplexAttributes() {
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
        
        let subject1 = Precompute(subjectKey: "user-1", subjectAttributes: attrs1)
        let subject2 = Precompute(subjectKey: "user-1", subjectAttributes: attrs2)
        
        // Verify properties match
        XCTAssertEqual(subject1.subjectKey, subject2.subjectKey)
        XCTAssertEqual(subject1.subjectAttributes["tags"], subject2.subjectAttributes["tags"])
        XCTAssertEqual(subject1.subjectAttributes["score"], subject2.subjectAttributes["score"])
        XCTAssertEqual(subject1.subjectAttributes["active"], subject2.subjectAttributes["active"])
    }
    
    // MARK: - Collection Tests
    
    func testSubjectInCollections() {
        let subject1 = Precompute(
            subjectKey: "user-123",
            subjectAttributes: ["tier": .valueOf("gold")]
        )
        
        let subject2 = Precompute(
            subjectKey: "user-123",
            subjectAttributes: ["tier": .valueOf("silver")]
        )
        
        let subject3 = Precompute(
            subjectKey: "user-456",
            subjectAttributes: ["tier": .valueOf("gold")]
        )
        
        var subjects = [Precompute]()
        subjects.append(subject1)
        subjects.append(subject2)
        subjects.append(subject3)
        
        // Test that subjects can be stored in collections
        XCTAssertEqual(subjects.count, 3)
        
        // Test that we can retrieve subjects by index
        XCTAssertEqual(subjects[0].subjectKey, "user-123")
        XCTAssertEqual(subjects[0].subjectAttributes["tier"], .valueOf("gold"))
        
        XCTAssertEqual(subjects[1].subjectKey, "user-123")
        XCTAssertEqual(subjects[1].subjectAttributes["tier"], .valueOf("silver"))
        
        XCTAssertEqual(subjects[2].subjectKey, "user-456")
        XCTAssertEqual(subjects[2].subjectAttributes["tier"], .valueOf("gold"))
        
        // Test that we can find subjects by custom logic
        let goldTierSubjects = subjects.filter { subject in
            guard let tier = subject.subjectAttributes["tier"] else { return false }
            return tier == .valueOf("gold")
        }
        XCTAssertEqual(goldTierSubjects.count, 2)
    }
    
    // MARK: - Edge Cases
    
    func testSubjectWithSpecialCharactersInKey() {
        let subject = Precompute(
            subjectKey: "user@example.com",
            subjectAttributes: ["source": .valueOf("email")]
        )
        
        XCTAssertEqual(subject.subjectKey, "user@example.com")
    }
    
    func testSubjectWithUnicodeInAttributes() {
        let subject = Precompute(
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
