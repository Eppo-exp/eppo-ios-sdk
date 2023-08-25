public class FlagConfig : Decodable {
    var subjectShards: Int;
    var enabled: Bool;
    var typedOverrides: [String: EppoValue];
    var rules: [TargetingRule];
    var allocations: [String: Allocation];
}
