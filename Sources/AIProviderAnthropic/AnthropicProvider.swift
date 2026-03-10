import AICore
import Foundation

/// Anthropic provider scaffold.
public struct AnthropicProvider: AIProvider, Sendable {
    public let apiKey: String
    public let configuration: AIProviderHTTPConfiguration

    public init(
        apiKey: String,
        baseURL: URL? = nil,
        transport: any AIHTTPTransport = URLSessionTransport(),
        defaultHeaders: [String: String] = [:]
    ) {
        self.apiKey = apiKey
        self.configuration = AIProviderHTTPConfiguration(
            baseURL: baseURL,
            transport: transport,
            defaultHeaders: defaultHeaders
        )
    }

    public func complete(_ request: AIRequest) async throws -> AIResponse {
        _ = request
        throw AIError.unsupportedFeature("Anthropic completions are not implemented yet")
    }

    public func stream(_ request: AIRequest) -> AIStream {
        _ = request
        return .failed(.unsupportedFeature("Anthropic streaming is not implemented yet"))
    }

    public var availableModels: [AIModel] {
        [
            .claude(.haiku45),
            .claude(.sonnet45),
            .claude(.sonnet46),
            .claude(.opus46),
        ]
    }

    public var capabilities: AIProviderCapabilities {
        AIProviderCapabilities(
            instructions: AIInstructionCapabilities(defaultFormat: .topLevelSystemPrompt),
            structuredOutput: AIStructuredOutputCapabilities(
                supportsJSONMode: false,
                supportsJSONSchema: true,
                defaultStrategy: .providerNative
            ),
            inputs: AIInputCapabilities(
                supportsImages: true,
                supportsDocuments: true,
                supportedImageMediaTypes: [
                    AIImage.AIMediaType.jpeg.rawValue,
                    AIImage.AIMediaType.png.rawValue,
                    AIImage.AIMediaType.gif.rawValue,
                    AIImage.AIMediaType.webp.rawValue,
                ],
                supportedDocumentMediaTypes: [
                    AIDocument.AIMediaType.pdf.rawValue,
                    AIDocument.AIMediaType.plainText.rawValue,
                ]
            ),
            tools: AIToolCapabilities(supportsParallelCalls: true, supportsForcedToolChoice: true),
            streaming: AIStreamingCapabilities(includesUsageInStream: true),
            embeddings: .default
        )
    }
}
