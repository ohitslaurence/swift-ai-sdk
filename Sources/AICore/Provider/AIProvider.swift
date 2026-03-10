/// The common abstraction implemented by all AI providers.
public protocol AIProvider: Sendable {
    /// Performs a non-streaming request.
    func complete(_ request: AIRequest) async throws -> AIResponse

    /// Performs a streaming request.
    func stream(_ request: AIRequest) -> AIStream

    /// Performs an embeddings request.
    func embed(_ request: AIEmbeddingRequest) async throws -> AIEmbeddingResponse

    /// Lists the models exposed by the provider.
    var availableModels: [AIModel] { get }

    /// Describes provider-level feature support.
    var capabilities: AIProviderCapabilities { get }
}

extension AIProvider {
    public var capabilities: AIProviderCapabilities { .default }

    public func embed(_ request: AIEmbeddingRequest) async throws -> AIEmbeddingResponse {
        throw AIError.unsupportedFeature("Embeddings are not implemented for this provider yet")
    }
}
