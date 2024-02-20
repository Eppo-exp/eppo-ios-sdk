public class Assignment : CustomStringConvertible {
    public var allocation: String = "";
    public var experiment: String = "";
    public var featureFlag: String = "";
    public var variation: String = "";
    public var subject: String = "";
    public var timestamp: String = "";
    public var subjectAttributes: SubjectAttributes;
    
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
