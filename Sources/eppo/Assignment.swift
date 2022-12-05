public class Assignment : CustomStringConvertible {
    var experiment: String = "";
    var variation: String = "";
    var subject: String = "";
    var timestamp: String = "";
    var subjectAttributes: SubjectAttributes;
    
    public var description: String {
        return "Subject " + subject + " assigned to variation " + variation + " in experiment " + experiment;
    }

    public init(
        _ experiment: String,
        _ variation: String,
        _ subject: String,
        _ timestamp: String,
        _ subjectAttributes: SubjectAttributes
    )
    {
        self.experiment = experiment;
        self.variation = variation;
        self.subject = subject;
        self.timestamp = timestamp;
        self.subjectAttributes = subjectAttributes;
    }
}
