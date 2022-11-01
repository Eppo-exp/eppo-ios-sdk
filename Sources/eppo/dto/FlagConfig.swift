class FlagConfig : Decodable {
    var subjectShards: UInt;
    var enabled: Bool;
    var overrides: [String: String];
    var rules: [TargetingRule];
    var allocations: [String: Allocation];
}
