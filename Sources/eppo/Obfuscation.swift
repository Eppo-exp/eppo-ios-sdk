import Foundation
import CommonCrypto

func getMD5Hex(_ value: String) -> String {
    let length = Int(CC_MD5_DIGEST_LENGTH)
    let messageData = value.data(using: .utf8)!
    var digestData = Data(count: length)

    _ = digestData.withUnsafeMutableBytes { digestBytes -> UInt8 in
        messageData.withUnsafeBytes { messageBytes -> UInt8 in
            if let messageBytesBaseAddress = messageBytes.baseAddress,
               let digestBytesBlindMemory = digestBytes.bindMemory(to: UInt8.self).baseAddress {
                let messageLength = CC_LONG(messageData.count)
                CC_MD5(messageBytesBaseAddress, messageLength, digestBytesBlindMemory)
            }
            return 0
        }
    }

    return digestData.map { String(format: "%02hhx", $0) }.joined()
}

func base64Decode(_ value: String) -> String? {
    if let decodedData = Data(base64Encoded: value) {
        return String(data: decodedData, encoding: .utf8)
    } else {
        return nil
    }
}

// Define the date formatter at a scope accessible by your function
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
    let result = UTC_ISO_DATE_FORMAT.date(from: isoDateString)
    if let result = result {
        return result
    }

    // Decode the base64 encoded date and try to parse it.
    if let decodedIsoDateString = base64Decode(isoDateString) {
        return UTC_ISO_DATE_FORMAT.date(from: decodedIsoDateString)
    }

    return nil
}
