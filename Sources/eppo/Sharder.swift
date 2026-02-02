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
        let value = hash.withUnsafeBytes { bytes in
          (UInt32(bytes[0]) << 24) |
          (UInt32(bytes[1]) << 16) |
          (UInt32(bytes[2]) << 8) |
          (UInt32(bytes[3]))
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
