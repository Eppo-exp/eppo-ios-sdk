public class Assignment : CustomStringConvertible {
    var allocation: String = "";
    var experiment: String = "";
    var featureFlag: String = "";
    var variation: String = "";
    var subject: String = "";
    var timestamp: String = "";
    var subjectAttributes: SubjectAttributes;
    
    public var description: String {
        return "Subject " + subject + " assigned to variation " + variation + " in experiment " + experiment;
    }

    public init(
        _ flagKey: String,
        _ allocationKey: String,
        _ variation: String,
        _ subject: String,
        _ timestamp: String,
        _ subjectAttributes: SubjectAttributes
    )
    {
        self.allocation = allocationKey;
        self.experiment = flagKey + "-" + allocationKey;
        self.featureFlag = flagKey;
        self.variation = variation;
        self.subject = subject;
        self.timestamp = timestamp;
        self.subjectAttributes = subjectAttributes;
    }
}
