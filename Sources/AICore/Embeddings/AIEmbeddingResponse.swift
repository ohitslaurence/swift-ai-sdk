/// A provider-neutral embeddings response.
public struct AIEmbeddingResponse: Sendable, Codable, Equatable {
    public let model: String
    public let embeddings: [AIEmbedding]
    public let usage: AIUsage?
    public let warnings: [AIProviderWarning]

    public init(
        model: String,
        embeddings: [AIEmbedding],
        usage: AIUsage? = nil,
        warnings: [AIProviderWarning] = []
    ) {
        self.model = model
        self.embeddings = embeddings
        self.usage = usage
        self.warnings = warnings
    }
}
