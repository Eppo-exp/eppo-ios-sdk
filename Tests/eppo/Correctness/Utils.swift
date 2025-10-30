import Foundation

enum TestError: Error {
    case fileNotFound(String)
}

func getTestFiles() throws -> [String] {
    let testDir = Bundle.module.path(forResource: "Resources/test-data/ufc/tests", ofType: nil) ?? ""
    let fileManager = FileManager.default
    let files = try fileManager.contentsOfDirectory(atPath: testDir)
    return files.map { "\(testDir)/\($0)" }
}

struct UFCTestCase: Codable {
    let flag: String
    let variationType: String
    let defaultValue: AnyCodable
    let subjects: [UFCTestSubject]
}

struct UFCTestSubject: Codable {
    let subjectKey: String
    let subjectAttributes: [String: AnyCodable]
    let assignment: AnyCodable
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
