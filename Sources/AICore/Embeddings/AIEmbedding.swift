/// A provider-neutral embeddings request.
public struct AIEmbeddingRequest: Sendable, Hashable, Codable {
    public var model: AIModel
    public var inputs: [AIEmbeddingInput]
    public var dimensions: Int?
    public var retryPolicy: RetryPolicy
    public var timeout: AITimeout

    public init(
        model: AIModel,
        inputs: [AIEmbeddingInput],
        dimensions: Int? = nil,
        retryPolicy: RetryPolicy = .default,
        timeout: AITimeout = .default
    ) {
        self.model = model
        self.inputs = inputs
        self.dimensions = dimensions
        self.retryPolicy = retryPolicy
        self.timeout = timeout
    }
}

/// A provider-neutral embedding input.
public enum AIEmbeddingInput: Sendable, Hashable, Codable {
    case text(String)
}

/// A provider-neutral embeddings response.
public struct AIEmbeddingResponse: Sendable, Hashable, Codable {
    public let model: String
    public let embeddings: [AIEmbedding]
    public let usage: AIUsage?

    public init(model: String, embeddings: [AIEmbedding], usage: AIUsage? = nil) {
        self.model = model
        self.embeddings = embeddings
        self.usage = usage
    }
}

/// A single embedding vector.
public struct AIEmbedding: Sendable, Hashable, Codable {
    public let index: Int
    public let vector: [Float]

    public init(index: Int, vector: [Float]) {
        self.index = index
        self.vector = vector
    }
}
