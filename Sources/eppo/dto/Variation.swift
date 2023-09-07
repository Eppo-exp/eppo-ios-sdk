struct Variation: Decodable {
    var value: String;
    var typedValue: EppoValue;
    var shardRange: ShardRange;
}
