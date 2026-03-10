/// A provider-neutral message role.
public enum AIRole: String, Sendable, Codable, Equatable {
    case user
    case assistant
    case tool
}
