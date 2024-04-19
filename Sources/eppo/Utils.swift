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
}
