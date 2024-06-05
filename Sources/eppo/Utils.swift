import Foundation
import CryptoKit

class Utils {
    static func getISODate(_ date: Date) -> String {
        let dateFormatter = DateFormatter();
        dateFormatter.locale = Locale(identifier: "en_US_POSIX");
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC");
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"

        return dateFormatter.string(from: date).appending("Z");
    }

    static func getMD5Hex(_ string: String) -> String {
        let data = Data(string.utf8)
        let md5 = Insecure.MD5.hash(data: data)
        return md5.map { String(format: "%02hhx", $0) }.joined()
    }

    static func base64Decode(_ string: String) -> String {
        let data = Data(string.utf8)
        let decoded = String(data: data, encoding: .utf8)
        return decoded ?? ""
    }
}
