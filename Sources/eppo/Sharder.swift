import Foundation
import CryptoKit

protocol Sharder {
    func getShard(input: String, totalShards: Int) -> Int
}

class MD5Sharder: Sharder {
    func getShard(input: String, totalShards: Int) -> Int {
        let inputData = Data(input.utf8)
        let hash = Insecure.MD5.hash(data: inputData)

        // Read first 4 bytes as big-endian UInt32
        var value: UInt32 = 0
        for byte in hash.prefix(4) {
            value = (value << 8) | UInt32(byte)
        }

        return Int(value % UInt32(totalShards))
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
