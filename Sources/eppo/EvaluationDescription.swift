public enum EvaluationDescription {
    public static func getDescription(
        hasDefinedRules: Bool,
        isExperimentOrPartialRollout: Bool,
        allocationKey: String,
        subjectKey: String,
        variationKey: String
    ) -> String {
        switch (hasDefinedRules, isExperimentOrPartialRollout) {
            case (true, true):
                return "Supplied attributes match rules defined in allocation \"\(allocationKey)\" and \(subjectKey) belongs to the range of traffic assigned to \"\(variationKey)\"."
            case (true, false):
                return "Supplied attributes match rules defined in allocation \"\(allocationKey)\"."
            default:
                return "\(subjectKey) belongs to the range of traffic assigned to \"\(variationKey)\" defined in allocation \"\(allocationKey)\"."
        }
    }
}