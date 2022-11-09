struct TargetingCondition : Decodable, Equatable {
    var targetingOperator: OperatorType = OperatorType.None;
    var attribute: String = "";
    var value: EppoValue = EppoValue.valueOf();
    
    enum CodingKeys: String, CodingKey {
        case targetingOperator = "operator"
        case attribute
        case value
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.targetingOperator == rhs.targetingOperator &&
               lhs.attribute == rhs.attribute &&
               lhs.value == rhs.value;
    }
}
