public class FlagConfig : Decodable {
    var subjectShards: Int;
    var enabled: Bool;
    var overrides: [String: String];
    var rules: [TargetingRule];
    var allocations: [String: Allocation];
}
