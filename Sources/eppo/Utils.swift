import Foundation
import CryptoKit

import var CommonCrypto.CC_MD5_DIGEST_LENGTH
import func CommonCrypto.CC_MD5
import typealias CommonCrypto.CC_LONG

class Utils {
    static func getMD5Hex(input: String) -> String {
        let length = Int(CC_MD5_DIGEST_LENGTH)
        let messageData = input.data(using:.utf8)!
        var digestData = Data(count: length)

        _ = digestData.withUnsafeMutableBytes { digestBytes -> UInt8 in
            messageData.withUnsafeBytes { messageBytes -> UInt8 in
                if let messageBytesBaseAddress = messageBytes.baseAddress, let digestBytesBlindMemory = digestBytes.bindMemory(to: UInt8.self).baseAddress {
                    let messageLength = CC_LONG(messageData.count)
                    CC_MD5(messageBytesBaseAddress, messageLength, digestBytesBlindMemory)
                }
                return 0
            }
        }

        return digestData.map { String(format: "%02hhx", $0) }.joined()
    }
    
    static func getMD5Hex32(input: String) -> String {
        var hashText = getMD5Hex(input: input);
        while (hashText.count < 32) {
            hashText = "0" + hashText;
        }
        
        return hashText;
    }

    static func getShard(_ input: String, _ maxShardValue: Int) -> Int {
        let hashText = getMD5Hex32(input: input);
        let longVal = strtoul(String(hashText.prefix(8)), nil, 16);
        return Int(longVal % UInt(maxShardValue));
    }

    static func isShardInRange(_ shard: Int, _ range: ShardRange) -> Bool {
        return shard >= range.start && shard < range.end;
    }

    static func getISODate(_ date: Date) -> String {
        let dateFormatter = DateFormatter();
        dateFormatter.locale = Locale(identifier: "en_US_POSIX");
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC");
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"

        return dateFormatter.string(from: date).appending("Z");
    }
}
