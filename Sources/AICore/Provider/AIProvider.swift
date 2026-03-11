import Foundation

/// The core abstraction implemented by all AI providers.
public protocol AIProvider: Sendable {
    /// Performs a non-streaming completion request.
    func complete(_ request: AIRequest) async throws -> AIResponse

    /// Performs a streaming completion request.
    func stream(_ request: AIRequest) -> AIStream

    /// Performs a provider-neutral embeddings request.
    func embed(_ request: AIEmbeddingRequest) async throws -> AIEmbeddingResponse

    /// The models published by this provider.
    var availableModels: [AIModel] { get }

    /// Provider-level capabilities used by higher-level helpers.
    var capabilities: AIProviderCapabilities { get }
}

extension AIProvider {
    public var capabilities: AIProviderCapabilities { .default }

    public func embed(_ request: AIEmbeddingRequest) async throws -> AIEmbeddingResponse {
        _ = request
        throw AIError.unsupportedFeature("Embeddings are not supported by this provider")
    }

    public func complete(
        _ prompt: String,
        model: AIModel,
        systemPrompt: String? = nil
    ) async throws -> String {
        let response = try await complete(
            AIRequest(
                model: model,
                messages: [.user(prompt)],
                systemPrompt: systemPrompt
            )
        )

        return response.text
    }

    public func stream(
        _ prompt: String,
        model: AIModel,
        systemPrompt: String? = nil
    ) -> AIStream {
        stream(
            AIRequest(
                model: model,
                messages: [.user(prompt)],
                systemPrompt: systemPrompt
            )
        )
    }

    public func complete(
        messages: [AIMessage],
        model: AIModel,
        systemPrompt: String? = nil
    ) async throws -> AIResponse {
        try await complete(
            AIRequest(
                model: model,
                messages: messages,
                systemPrompt: systemPrompt
            )
        )
    }

    public func embed(
        _ text: String,
        model: AIModel,
        dimensions: Int? = nil,
        retryPolicy: RetryPolicy = .default,
        timeout: AITimeout = .default,
        headers: [String: String] = [:]
    ) async throws -> AIEmbedding {
        let response = try await embed(
            AIEmbeddingRequest(
                model: model,
                inputs: [.text(text)],
                dimensions: dimensions,
                retryPolicy: retryPolicy,
                timeout: timeout,
                headers: headers
            )
        )

        guard let embedding = response.embeddings.first else {
            throw AIError.noContentGenerated
        }

        return embedding
    }

    public func embedMany(
        _ texts: [String],
        model: AIModel,
        dimensions: Int? = nil,
        batchSize: Int? = nil,
        retryPolicy: RetryPolicy = .default,
        timeout: AITimeout = .default,
        headers: [String: String] = [:]
    ) async throws -> AIEmbeddingResponse {
        guard !texts.isEmpty else {
            throw AIError.invalidRequest("Embedding inputs must not be empty")
        }

        if let batchSize, batchSize <= 0 {
            throw AIError.invalidRequest("Embedding batch size must be greater than 0")
        }

        if let dimensions, dimensions <= 0 {
            throw AIError.invalidRequest("Embedding dimensions must be greater than 0")
        }

        let inputs = texts.map(AIEmbeddingInput.text)
        let effectiveBatchSize = try resolvedEmbeddingBatchSize(
            textCount: texts.count,
            requestedBatchSize: batchSize,
            capabilities: capabilities.embeddings
        )

        if effectiveBatchSize >= inputs.count {
            return try await embed(
                AIEmbeddingRequest(
                    model: model,
                    inputs: inputs,
                    dimensions: dimensions,
                    retryPolicy: retryPolicy,
                    timeout: timeout,
                    headers: headers
                )
            )
        }

        var aggregatedEmbeddings: [AIEmbedding] = []
        var aggregatedModel: String?
        var aggregatedUsage = AIUsageAccumulator()
        var warnings: [AIProviderWarning] = []

        for batchStart in stride(from: 0, to: inputs.count, by: effectiveBatchSize) {
            try Task.checkCancellation()

            let batchEnd = min(batchStart + effectiveBatchSize, inputs.count)
            let batchInputs = Array(inputs[batchStart..<batchEnd])
            let response = try await embed(
                AIEmbeddingRequest(
                    model: model,
                    inputs: batchInputs,
                    dimensions: dimensions,
                    retryPolicy: retryPolicy,
                    timeout: timeout,
                    headers: headers
                )
            )

            if let existingModel = aggregatedModel, existingModel != response.model {
                warnings.append(
                    AIProviderWarning(
                        code: "inconsistent_embedding_model",
                        message: "Received multiple embedding response model identifiers while aggregating batches",
                        parameter: "model"
                    )
                )
            } else if aggregatedModel == nil {
                aggregatedModel = response.model
            }

            warnings.append(contentsOf: response.warnings)
            aggregatedUsage.add(response.usage)

            let orderedBatchEmbeddings = response.embeddings.sorted { $0.index < $1.index }
            guard orderedBatchEmbeddings.count == batchInputs.count else {
                throw AIError.decodingError(
                    AIErrorContext(
                        message:
                            "Embedding batch returned \(orderedBatchEmbeddings.count) vectors for \(batchInputs.count) inputs"
                    )
                )
            }

            for (offset, embedding) in orderedBatchEmbeddings.enumerated() {
                aggregatedEmbeddings.append(
                    AIEmbedding(
                        index: batchStart + offset,
                        vector: embedding.vector
                    )
                )
            }
        }

        return AIEmbeddingResponse(
            model: aggregatedModel ?? model.id,
            embeddings: aggregatedEmbeddings,
            usage: aggregatedUsage.value,
            warnings: warnings
        )
    }

    private func resolvedEmbeddingBatchSize(
        textCount: Int,
        requestedBatchSize: Int?,
        capabilities: AIEmbeddingCapabilities
    ) throws -> Int {
        if let requestedBatchSize {
            return requestedBatchSize
        }

        if let advertisedBatchSize = capabilities.maxInputsPerRequest {
            guard advertisedBatchSize > 0 else {
                throw AIError.invalidRequest("Embedding batch size must be greater than 0")
            }

            return advertisedBatchSize
        }

        if capabilities.supportsBatchInputs {
            return textCount
        }

        return 1
    }
}
