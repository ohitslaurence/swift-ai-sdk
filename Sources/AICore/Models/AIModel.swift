/// A provider-qualified model identifier.
public struct AIModel: Hashable, Sendable, Codable {
    public let id: String
    public let provider: String?

    public init(_ id: String, provider: String? = nil) {
        self.id = id
        self.provider = provider
    }
}
