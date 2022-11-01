struct TargetingCondition : Decodable {
    var targetingOperator: String;
    var attribute: String;
    var value: EppoValue;
    
    enum CodingKeys: String, CodingKey {
        case targetingOperator = "operator"
        case attribute
        case value
    }
}
