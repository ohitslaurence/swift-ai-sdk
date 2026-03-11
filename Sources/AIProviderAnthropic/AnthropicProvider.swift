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
        let requestBuilder = AnthropicRequestBuilder(apiKey: apiKey, configuration: configuration)
        let errorMapper = AnthropicErrorMapper()
        let responseParser = AnthropicResponseParser()

        return try await AITimeoutController.withTimeout(request.timeout.total, kind: .total) {
            try await RetryExecutor.execute(policy: request.retryPolicy) { _ in
                try await AITimeoutController.withTimeout(request.timeout.step, kind: .step) {
                    let preparedRequest = try requestBuilder.prepareRequest(for: request, stream: false)
                    let data = try await performDataRequest(
                        preparedRequest.urlRequest,
                        model: request.model,
                        errorMapper: errorMapper
                    )

                    return try responseParser.parse(data, warnings: preparedRequest.warnings)
                }
            }
        }
    }

    public func stream(_ request: AIRequest) -> AIStream {
        let requestBuilder = AnthropicRequestBuilder(apiKey: apiKey, configuration: configuration)
        let errorMapper = AnthropicErrorMapper()
        let streamParser = AnthropicStreamParser()

        return RetryExecutor.executeStream(policy: request.retryPolicy, timeout: request.timeout) { _ in
            let preparedRequest = try requestBuilder.prepareRequest(for: request, stream: true)
            let streamResponse = try await performStreamRequest(
                preparedRequest.urlRequest,
                model: request.model,
                errorMapper: errorMapper
            )

            return streamParser.parse(
                streamResponse,
                model: request.model,
                errorMapper: errorMapper,
                warnings: preparedRequest.warnings
            )
        }
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

    private func performDataRequest(
        _ request: URLRequest,
        model: AIModel,
        errorMapper: AnthropicErrorMapper
    ) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse

        do {
            (data, response) = try await configuration.transport.data(for: request)
        } catch {
            throw errorMapper.mapTransportError(error)
        }

        guard 200..<300 ~= response.statusCode else {
            throw errorMapper.mapResponse(response: response, body: data, model: model)
        }

        return data
    }

    private func performStreamRequest(
        _ request: URLRequest,
        model: AIModel,
        errorMapper: AnthropicErrorMapper
    ) async throws -> AIHTTPStreamResponse {
        let response: AIHTTPStreamResponse

        do {
            response = try await configuration.transport.stream(for: request)
        } catch {
            throw errorMapper.mapTransportError(error)
        }

        guard 200..<300 ~= response.response.statusCode else {
            let body = try await collectBody(response.body, errorMapper: errorMapper)
            throw errorMapper.mapResponse(response: response.response, body: body, model: model)
        }

        return response
    }

    private func collectBody(
        _ body: AsyncThrowingStream<Data, any Error>,
        errorMapper: AnthropicErrorMapper
    ) async throws -> Data {
        var collectedBody = Data()

        do {
            for try await chunk in body {
                collectedBody.append(chunk)
            }
        } catch {
            throw errorMapper.mapTransportError(error)
        }

        return collectedBody
    }
}
