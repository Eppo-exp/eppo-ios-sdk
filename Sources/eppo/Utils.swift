import Foundation
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

        return String(decoding: digestData, as: UTF8.self)
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

    static func isShardInRange(shard: Int, range: ShardRange) -> Bool {
        return shard >= range.start && shard < range.end;
    }
//
//    public static void validateNotEmptyOrNull(String input, String errorMessage) {
//        if (input == null || input.isEmpty()) {
//            throw new IllegalArgumentException(errorMessage);
//        }
//    }
}
