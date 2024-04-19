import Foundation
import CryptoKit

protocol Sharder {
    func getShard(input: String, totalShards: Int) -> Int
}

class MD5Sharder: Sharder {
    func getShard(input: String, totalShards: Int) -> Int {
        let inputData = Data(input.utf8)
        let hash = Insecure.MD5.hash(data: inputData)
        let hexString = hash.map { String(format: "%02hhx", $0) }.joined()

        // Get the first 8 characters of the MD5 hex string and parse them as an integer using base 16
        let substringIndex = hexString.index(hexString.startIndex, offsetBy: 8)
        let intFromHash = Int(hexString[..<substringIndex], radix: 16)!

        return intFromHash % totalShards
    }
}

class DeterministicSharder: Sharder {
    var lookup: [String: Int]

    init(lookup: [String: Int]) {
        self.lookup = lookup
    }

    func getShard(input: String, totalShards: Int) -> Int {
        return lookup[input, default: 0]
    }
}
