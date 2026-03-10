import AICore
import Foundation

/// OpenAI Chat Completions and Embeddings provider.
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
        let requestBuilder = OpenAIRequestBuilder(
            apiKey: apiKey, organization: organization, configuration: configuration
        )
        let errorMapper = OpenAIErrorMapper()
        let responseParser = OpenAIResponseParser()

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
        let requestBuilder = OpenAIRequestBuilder(
            apiKey: apiKey, organization: organization, configuration: configuration
        )
        let errorMapper = OpenAIErrorMapper()
        let streamParser = OpenAIStreamParser()

        return RetryExecutor.executeStream(policy: request.retryPolicy, timeout: request.timeout) { _ in
            let preparedRequest = try requestBuilder.prepareRequest(for: request, stream: true)
            let streamResponse = try await performStreamRequest(
                preparedRequest.urlRequest,
                model: request.model,
                errorMapper: errorMapper
            )

            return streamParser.parse(streamResponse, warnings: preparedRequest.warnings)
        }
    }

    public func embed(_ request: AIEmbeddingRequest) async throws -> AIEmbeddingResponse {
        let requestBuilder = OpenAIEmbeddingRequestBuilder(
            apiKey: apiKey, organization: organization, configuration: configuration
        )
        let errorMapper = OpenAIErrorMapper()
        let responseParser = OpenAIEmbeddingResponseParser()

        return try await AITimeoutController.withTimeout(request.timeout.total, kind: .total) {
            try await RetryExecutor.execute(policy: request.retryPolicy) { _ in
                try await AITimeoutController.withTimeout(request.timeout.step, kind: .step) {
                    let urlRequest = try requestBuilder.prepareRequest(for: request)
                    let data = try await performDataRequest(
                        urlRequest,
                        model: request.model,
                        errorMapper: errorMapper
                    )

                    return try responseParser.parse(data)
                }
            }
        }
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

    private func performDataRequest(
        _ request: URLRequest,
        model: AIModel,
        errorMapper: OpenAIErrorMapper
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
        errorMapper: OpenAIErrorMapper
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
        errorMapper: OpenAIErrorMapper
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
