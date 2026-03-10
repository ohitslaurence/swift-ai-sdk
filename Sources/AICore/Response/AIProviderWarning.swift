/// A warning surfaced by a provider or helper.
public struct AIProviderWarning: Sendable, Codable, Equatable {
    public let code: String
    public let message: String
    public let parameter: String?

    public init(code: String, message: String, parameter: String? = nil) {
        self.code = code
        self.message = message
        self.parameter = parameter
    }
}
