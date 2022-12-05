struct TargetingRule: Decodable, Equatable {
    var allocationKey: String = "";
    var conditions: [TargetingCondition] = [];

    public init() {}

    static func == (lhs: Self, rhs: Self) -> Bool {
        if lhs.allocationKey != rhs.allocationKey { return false; }
        if lhs.conditions.count != rhs.conditions.count { return false; }

        // Equality implies that the arrays contain the same elements,
        // not that they're in the same order
        for lhCondition in lhs.conditions {
            if !rhs.conditions.contains(where: { (tc) in return lhCondition == tc; }) {
                return false;
            }
        }

        return true;
    }
}
