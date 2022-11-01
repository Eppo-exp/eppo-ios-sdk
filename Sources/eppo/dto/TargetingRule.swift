struct TargetingRule: Decodable {
    var allocationKey: String;
    var conditions: [TargetingCondition];
}
