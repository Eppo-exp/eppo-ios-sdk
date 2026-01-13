import Foundation
import CommonCrypto

func getMD5Hex(_ value: String, salt: String = "") -> String {
    let length = Int(CC_MD5_DIGEST_LENGTH)
    let saltedValue = salt + value
    let messageData = saltedValue.data(using: .utf8)!
    var digestData = Data(count: length)

    _ = digestData.withUnsafeMutableBytes { digestBytes -> UInt8 in
        messageData.withUnsafeBytes { messageBytes -> UInt8 in
            if let messageBytesBaseAddress = messageBytes.baseAddress,
               let digestBytesBlindMemory = digestBytes.bindMemory(to: UInt8.self).baseAddress {
                let messageLength = CC_LONG(messageData.count)
                // This warning can be ignore since we are deliberately using md5 to obfuscate the value.
                CC_MD5(messageBytesBaseAddress, messageLength, digestBytesBlindMemory)
            }
            return 0
        }
    }

    return digestData.map { String(format: "%02hhx", $0) }.joined()
}

func base64Encode(_ value: String) -> String {
    guard let data = value.data(using: .utf8) else {
        return ""
    }
    return data.base64EncodedString()
}

func base64Decode(_ value: String) -> String? {
    if let decodedData = Data(base64Encoded: value) {
        return String(data: decodedData, encoding: .utf8)
    } else {
        return nil
    }
}

func base64DecodeOrThrow(_ value: String) throws -> String {
    guard let decodedData = Data(base64Encoded: value) else {
        throw Base64DecodeError.invalidBase64(value)
    }
    guard let decodedString = String(data: decodedData, encoding: .utf8) else {
        throw Base64DecodeError.invalidUTF8(value)
    }
    return decodedString
}

enum Base64DecodeError: Error, LocalizedError {
    case invalidBase64(String)
    case invalidUTF8(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidBase64(let value):
            return "Invalid base64 string: \(value)"
        case .invalidUTF8(let value):
            return "Invalid UTF-8 encoding in base64 string: \(value)"
        }
    }
}

let UTC_ISO_DATE_FORMAT: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ" // Includes milliseconds
    formatter.locale = Locale(identifier: "en_US_POSIX")  // Use POSIX to avoid unexpected behaviors
    formatter.timeZone = TimeZone(secondsFromGMT: 0) // UTC
    return formatter
}()

func parseUtcISODateElement(_ isoDateString: String) -> Date? {
    guard !isoDateString.isEmpty else {
        return nil
    }

    // If the date is in the correct format, return it.
    if let result = UTC_ISO_DATE_FORMAT.date(from: isoDateString) {
        return result
    }

    // Decode the base64 encoded date and try to parse it.
    if let decodedIsoDateString = base64Decode(isoDateString) {
        return UTC_ISO_DATE_FORMAT.date(from: decodedIsoDateString)
    }

    return nil
}
