/// Token accounting for a response.
public struct AIUsage: Sendable, Codable, Equatable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let inputTokenDetails: InputTokenDetails?
    public let outputTokenDetails: OutputTokenDetails?

    public init(
        inputTokens: Int,
        outputTokens: Int,
        inputTokenDetails: InputTokenDetails? = nil,
        outputTokenDetails: OutputTokenDetails? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.inputTokenDetails = inputTokenDetails
        self.outputTokenDetails = outputTokenDetails
    }

    public var totalTokens: Int {
        inputTokens + outputTokens
    }

    public struct InputTokenDetails: Sendable, Codable, Equatable {
        public let cachedTokens: Int?
        public let cacheWriteTokens: Int?

        public init(cachedTokens: Int? = nil, cacheWriteTokens: Int? = nil) {
            self.cachedTokens = cachedTokens
            self.cacheWriteTokens = cacheWriteTokens
        }
    }

    public struct OutputTokenDetails: Sendable, Codable, Equatable {
        public let reasoningTokens: Int?

        public init(reasoningTokens: Int? = nil) {
            self.reasoningTokens = reasoningTokens
        }
    }
}
