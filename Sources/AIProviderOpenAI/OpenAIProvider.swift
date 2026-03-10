import AICore
import Foundation

/// OpenAI provider scaffold.
public struct OpenAIProvider: AIProvider, Sendable {
    public let apiKey: String
    public let organization: String?
    public let configuration: AIProviderHTTPConfiguration

    public init(
        apiKey: String,
        baseURL: URL? = nil,
        organization: String? = nil,
        transport: any AIHTTPTransport = URLSessionTransport(),
        defaultHeaders: [String: String] = [:]
    ) {
        self.apiKey = apiKey
        self.organization = organization
        self.configuration = AIProviderHTTPConfiguration(
            baseURL: baseURL,
            transport: transport,
            defaultHeaders: defaultHeaders
        )
    }

    public func complete(_ request: AIRequest) async throws -> AIResponse {
        _ = request
        throw AIError.unsupportedFeature("OpenAI completions are not implemented yet")
    }

    public func stream(_ request: AIRequest) -> AIStream {
        _ = request
        return .failed(.unsupportedFeature("OpenAI streaming is not implemented yet"))
    }

    public func embed(_ request: AIEmbeddingRequest) async throws -> AIEmbeddingResponse {
        _ = request
        throw AIError.unsupportedFeature("OpenAI embeddings are not implemented yet")
    }

    public var availableModels: [AIModel] {
        [
            .gpt(.gpt4o),
            .gpt(.gpt4oMini),
            .openAIEmbedding(.textEmbedding3Small),
        ]
    }

    public var capabilities: AIProviderCapabilities {
        AIProviderCapabilities(supportsStreaming: true, supportsEmbeddings: true)
    }
}
