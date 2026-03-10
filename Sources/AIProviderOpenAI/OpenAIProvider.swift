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
            .gpt(.gpt41),
            .gpt(.gpt41Mini),
            .gpt(.gpt41Nano),
            .gpt(.gpt5),
            .gpt(.gpt5Mini),
            .gpt(.gpt5Nano),
            .gpt(.o3),
            .gpt(.o3Mini),
            .gpt(.o4Mini),
            .openAIEmbedding(.textEmbedding3Small),
            .openAIEmbedding(.textEmbedding3Large),
        ]
    }

    public var capabilities: AIProviderCapabilities {
        AIProviderCapabilities(
            instructions: AIInstructionCapabilities(
                defaultFormat: .message(role: .system),
                reasoningModelFormatOverride: .message(role: .developer),
                reasoningModelIDs: [
                    .gpt(.gpt5),
                    .gpt(.gpt5Mini),
                    .gpt(.gpt5Nano),
                    .gpt(.o3),
                    .gpt(.o3Mini),
                    .gpt(.o4Mini),
                ]
            ),
            structuredOutput: AIStructuredOutputCapabilities(
                supportsJSONMode: true,
                supportsJSONSchema: true,
                defaultStrategy: .providerNative
            ),
            inputs: AIInputCapabilities(
                supportsImages: true,
                supportsDocuments: false,
                supportedImageMediaTypes: [
                    AIImage.AIMediaType.jpeg.rawValue,
                    AIImage.AIMediaType.png.rawValue,
                    AIImage.AIMediaType.gif.rawValue,
                    AIImage.AIMediaType.webp.rawValue,
                ],
                supportedDocumentMediaTypes: []
            ),
            tools: AIToolCapabilities(supportsParallelCalls: true, supportsForcedToolChoice: true),
            streaming: AIStreamingCapabilities(includesUsageInStream: true),
            embeddings: AIEmbeddingCapabilities(
                supportsEmbeddings: true,
                supportedInputKinds: [.text],
                supportsBatchInputs: true,
                supportsDimensionOverride: true,
                maxInputsPerRequest: nil
            )
        )
    }
}
