public enum OperatorType : String, Decodable {
    case Matches = "MATCHES"
    case GreaterThanEqualTo = "GTE"
    case GreaterThan = "GT"
    case LessThanEqualTo = "LTE"
    case LessThan = "LT"
    case OneOf = "ONE_OF"
    case NotOneOf = "NOT_ONE_OF"
    case None = ""
}
