import Foundation

/// A sink that receives structured telemetry events.
///
/// Sinks must never throw — a failing sink must not fail the AI operation.
public protocol AITelemetrySink: Sendable {
    func record(_ event: AITelemetryEvent) async
}

/// Configuration for the telemetry observation layer.
public struct AITelemetryConfiguration: Sendable {
    public var sinks: [any AITelemetrySink]
    public var redaction: AITelemetryRedaction
    public var includeMetrics: Bool
    public var includeUsage: Bool
    public var includeAccounting: Bool

    public static let `default` = AITelemetryConfiguration(sinks: [])

    public init(
        sinks: [any AITelemetrySink],
        redaction: AITelemetryRedaction = .default,
        includeMetrics: Bool = true,
        includeUsage: Bool = true,
        includeAccounting: Bool = true
    ) {
        self.sinks = sinks
        self.redaction = redaction
        self.includeMetrics = includeMetrics
        self.includeUsage = includeUsage
        self.includeAccounting = includeAccounting
    }
}

/// Wraps a provider with telemetry observation.
///
/// The returned provider intercepts `complete()`, `stream()`, and `embed()`
/// to emit structured events to the configured sinks.
public func withTelemetry(
    _ provider: any AIProvider,
    configuration: AITelemetryConfiguration
) -> any AIProvider {
    TelemetryProvider(provider: provider, configuration: configuration)
}

// MARK: - Internal TelemetryProvider

struct TelemetryProvider: AIProvider, Sendable {
    let provider: any AIProvider
    let configuration: AITelemetryConfiguration

    var availableModels: [AIModel] {
        provider.availableModels
    }

    var capabilities: AIProviderCapabilities {
        provider.capabilities
    }

    func complete(_ request: AIRequest) async throws -> AIResponse {
        let operationID = makeOperationID()
        let clock = ContinuousClock()
        let startInstant = clock.now

        let snapshot = makeRequestSnapshot(request, redaction: configuration.redaction)
        await emit(
            AITelemetryEvent(
                timestamp: Date(),
                operationID: operationID,
                operationKind: .completion,
                kind: .requestStarted(snapshot, attempt: 1)
            ))

        do {
            try Task.checkCancellation()

            let response = try await provider.complete(request)

            let totalDuration = clock.now - startInstant
            let metrics =
                configuration.includeMetrics
                ? AITelemetryMetrics(totalDuration: totalDuration)
                : nil
            let accounting = makeAccounting(usage: response.usage)

            let responseSnapshot = makeResponseSnapshot(
                response,
                redaction: configuration.redaction,
                metrics: metrics,
                accounting: accounting
            )
            await emit(
                AITelemetryEvent(
                    timestamp: Date(),
                    operationID: operationID,
                    operationKind: .completion,
                    kind: .responseReceived(responseSnapshot)
                ))

            return response
        } catch is CancellationError {
            await emit(
                AITelemetryEvent(
                    timestamp: Date(),
                    operationID: operationID,
                    operationKind: .completion,
                    kind: .cancelled
                ))
            throw AIError.cancelled
        } catch let error as AIError {
            let totalDuration = clock.now - startInstant
            let metrics =
                configuration.includeMetrics
                ? AITelemetryMetrics(totalDuration: totalDuration)
                : nil
            await emit(
                AITelemetryEvent(
                    timestamp: Date(),
                    operationID: operationID,
                    operationKind: .completion,
                    kind: .requestFailed(error: error, attempt: 1, metrics: metrics)
                ))
            throw error
        } catch {
            let aiError = AIError.unknown(AIErrorContext(error))
            let totalDuration = clock.now - startInstant
            let metrics =
                configuration.includeMetrics
                ? AITelemetryMetrics(totalDuration: totalDuration)
                : nil
            await emit(
                AITelemetryEvent(
                    timestamp: Date(),
                    operationID: operationID,
                    operationKind: .completion,
                    kind: .requestFailed(error: aiError, attempt: 1, metrics: metrics)
                ))
            throw aiError
        }
    }

    func stream(_ request: AIRequest) -> AIStream {
        let operationID = makeOperationID()
        let clock = ContinuousClock()
        let startInstant = clock.now
        let config = configuration

        let snapshot = makeRequestSnapshot(request, redaction: config.redaction)
        let sourceStream = provider.stream(request)

        let wrappedStream = AsyncThrowingStream<AIStreamEvent, any Error>(
            AIStreamEvent.self,
            bufferingPolicy: .unbounded
        ) { continuation in
            let task = Task {
                await emit(
                    AITelemetryEvent(
                        timestamp: Date(),
                        operationID: operationID,
                        operationKind: .stream,
                        kind: .requestStarted(snapshot, attempt: 1)
                    ))

                var streamEventCount = 0
                var firstEventLatency: Duration?
                var finishReason: AIFinishReason?

                do {
                    for try await event in sourceStream {
                        try Task.checkCancellation()

                        streamEventCount += 1

                        if firstEventLatency == nil {
                            firstEventLatency = clock.now - startInstant
                        }

                        if case .finish(let reason) = event {
                            finishReason = reason
                        }

                        await emit(
                            AITelemetryEvent(
                                timestamp: Date(),
                                operationID: operationID,
                                operationKind: .stream,
                                kind: .streamEvent(event)
                            ))

                        continuation.yield(event)
                    }

                    let totalDuration = clock.now - startInstant
                    let metrics =
                        config.includeMetrics
                        ? AITelemetryMetrics(
                            totalDuration: totalDuration,
                            firstEventLatency: firstEventLatency,
                            streamEventCount: streamEventCount
                        )
                        : nil

                    await emit(
                        AITelemetryEvent(
                            timestamp: Date(),
                            operationID: operationID,
                            operationKind: .stream,
                            kind: .streamCompleted(
                                finishReason: finishReason,
                                metrics: metrics,
                                accounting: nil
                            )
                        ))

                    continuation.finish()
                } catch is CancellationError {
                    await emit(
                        AITelemetryEvent(
                            timestamp: Date(),
                            operationID: operationID,
                            operationKind: .stream,
                            kind: .cancelled
                        ))
                    continuation.finish(throwing: AIError.cancelled)
                } catch let error as AIError {
                    let totalDuration = clock.now - startInstant
                    let metrics =
                        config.includeMetrics
                        ? AITelemetryMetrics(
                            totalDuration: totalDuration,
                            firstEventLatency: firstEventLatency,
                            streamEventCount: streamEventCount
                        )
                        : nil
                    await emit(
                        AITelemetryEvent(
                            timestamp: Date(),
                            operationID: operationID,
                            operationKind: .stream,
                            kind: .requestFailed(error: error, attempt: 1, metrics: metrics)
                        ))
                    continuation.finish(throwing: error)
                } catch {
                    let aiError = AIError.unknown(AIErrorContext(error))
                    let totalDuration = clock.now - startInstant
                    let metrics =
                        config.includeMetrics
                        ? AITelemetryMetrics(
                            totalDuration: totalDuration,
                            firstEventLatency: firstEventLatency,
                            streamEventCount: streamEventCount
                        )
                        : nil
                    await emit(
                        AITelemetryEvent(
                            timestamp: Date(),
                            operationID: operationID,
                            operationKind: .stream,
                            kind: .requestFailed(error: aiError, attempt: 1, metrics: metrics)
                        ))
                    continuation.finish(throwing: aiError)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        return AIStream(
            wrapping: wrappedStream,
            applyLifecyclePolicy: false,
            warningProvider: { await sourceStream.responseWarnings() }
        )
    }

    func embed(_ request: AIEmbeddingRequest) async throws -> AIEmbeddingResponse {
        let operationID = makeOperationID()
        let clock = ContinuousClock()
        let startInstant = clock.now

        let requestSnapshot = makeEmbeddingRequestSnapshot(
            request,
            redaction: configuration.redaction
        )
        await emit(
            AITelemetryEvent(
                timestamp: Date(),
                operationID: operationID,
                operationKind: .embedding,
                kind: .embeddingStarted(requestSnapshot)
            ))

        do {
            try Task.checkCancellation()

            let response = try await provider.embed(request)

            let totalDuration = clock.now - startInstant
            let metrics =
                configuration.includeMetrics
                ? AITelemetryMetrics(totalDuration: totalDuration)
                : nil
            let accounting = makeAccounting(usage: response.usage)

            let responseSnapshot = makeEmbeddingResponseSnapshot(
                response,
                redaction: configuration.redaction,
                metrics: metrics,
                accounting: accounting
            )
            await emit(
                AITelemetryEvent(
                    timestamp: Date(),
                    operationID: operationID,
                    operationKind: .embedding,
                    kind: .embeddingResponse(responseSnapshot)
                ))

            return response
        } catch is CancellationError {
            await emit(
                AITelemetryEvent(
                    timestamp: Date(),
                    operationID: operationID,
                    operationKind: .embedding,
                    kind: .cancelled
                ))
            throw AIError.cancelled
        } catch let error as AIError {
            let totalDuration = clock.now - startInstant
            let metrics =
                configuration.includeMetrics
                ? AITelemetryMetrics(totalDuration: totalDuration)
                : nil
            await emit(
                AITelemetryEvent(
                    timestamp: Date(),
                    operationID: operationID,
                    operationKind: .embedding,
                    kind: .requestFailed(error: error, attempt: 1, metrics: metrics)
                ))
            throw error
        } catch {
            let aiError = AIError.unknown(AIErrorContext(error))
            let totalDuration = clock.now - startInstant
            let metrics =
                configuration.includeMetrics
                ? AITelemetryMetrics(totalDuration: totalDuration)
                : nil
            await emit(
                AITelemetryEvent(
                    timestamp: Date(),
                    operationID: operationID,
                    operationKind: .embedding,
                    kind: .requestFailed(error: aiError, attempt: 1, metrics: metrics)
                ))
            throw aiError
        }
    }

    // MARK: - Emit

    private func emit(_ event: AITelemetryEvent) async {
        for sink in configuration.sinks {
            await safeSinkRecord(sink, event: event)
        }
    }

    private func safeSinkRecord(_ sink: any AITelemetrySink, event: AITelemetryEvent) async {
        await sink.record(event)
    }

    // MARK: - ID Generation

    private func makeOperationID() -> String {
        UUID().uuidString
    }

    // MARK: - Accounting

    private func makeAccounting(usage: AIUsage?) -> AIAccounting? {
        guard configuration.includeAccounting || configuration.includeUsage else {
            return nil
        }

        guard let usage else {
            return nil
        }

        return AIAccounting(usage: usage)
    }

    // MARK: - Request Snapshots

    private func makeRequestSnapshot(
        _ request: AIRequest,
        redaction: AITelemetryRedaction
    ) -> AIGenerationRequestSnapshot {
        let systemPrompt: String? = {
            switch redaction.prompts {
            case .none:
                return nil
            case .summary:
                if let sp = request.systemPrompt {
                    return "[\(sp.count) chars]"
                }
                return nil
            case .full:
                return request.systemPrompt
            }
        }()

        let messages = request.messages.map { message in
            makeMessageSnapshot(message, redaction: redaction)
        }

        let responseFormatKind: AIResponseFormatKind = {
            switch request.responseFormat {
            case .text: return .text
            case .json: return .json
            case .jsonSchema: return .jsonSchema
            }
        }()

        return AIGenerationRequestSnapshot(
            model: request.model,
            systemPrompt: systemPrompt,
            messages: messages,
            toolNames: request.tools.map(\.name),
            toolChoice: request.toolChoice,
            allowParallelToolCalls: request.allowParallelToolCalls,
            responseFormat: responseFormatKind,
            maxTokens: request.maxTokens,
            temperature: request.temperature,
            topP: request.topP,
            stopSequences: request.stopSequences,
            metadata: request.metadata,
            headers: redactHeaders(request.headers, allowed: redaction.allowedHeaderNames)
        )
    }

    private func makeMessageSnapshot(
        _ message: AIMessage,
        redaction: AITelemetryRedaction
    ) -> AIMessageSnapshot {
        let contents = message.content.map { content in
            makeContentSnapshot(content, redaction: redaction)
        }
        return AIMessageSnapshot(role: message.role, content: contents)
    }

    private func makeContentSnapshot(
        _ content: AIContent,
        redaction: AITelemetryRedaction
    ) -> AIContentSnapshot {
        switch content {
        case .text(let value):
            let text: String? = {
                switch redaction.prompts {
                case .none: return nil
                case .summary: return "[\(value.count) chars]"
                case .full: return value
                }
            }()
            return AIContentSnapshot(kind: .text, text: text, mediaType: nil, toolName: nil, toolUseID: nil)

        case .image(let image):
            return AIContentSnapshot(
                kind: .image,
                text: nil,
                mediaType: image.mediaType.rawValue,
                toolName: nil,
                toolUseID: nil
            )

        case .document(let doc):
            return AIContentSnapshot(
                kind: .document,
                text: nil,
                mediaType: doc.mediaType.rawValue,
                toolName: nil,
                toolUseID: nil
            )

        case .toolUse(let toolUse):
            let inputJSON: String? = {
                switch redaction.toolArguments {
                case .none: return nil
                case .summary: return "[\(toolUse.input.count) bytes]"
                case .full: return String(data: toolUse.input, encoding: .utf8)
                }
            }()
            return AIContentSnapshot(
                kind: .toolUse,
                text: inputJSON,
                mediaType: nil,
                toolName: toolUse.name,
                toolUseID: toolUse.id
            )

        case .toolResult(let result):
            let text: String? = {
                switch redaction.toolResults {
                case .none: return nil
                case .summary: return "[\(result.content.count) chars]"
                case .full: return result.content
                }
            }()
            return AIContentSnapshot(
                kind: .toolResult,
                text: text,
                mediaType: nil,
                toolName: nil,
                toolUseID: result.toolUseId
            )
        }
    }

    // MARK: - Response Snapshots

    private func makeResponseSnapshot(
        _ response: AIResponse,
        redaction: AITelemetryRedaction,
        metrics: AITelemetryMetrics?,
        accounting: AIAccounting?
    ) -> AIResponseSnapshot {
        let content = response.content.map { c in
            makeResponseContentSnapshot(c, redaction: redaction)
        }

        return AIResponseSnapshot(
            id: response.id,
            model: response.model,
            content: content,
            finishReason: response.finishReason,
            warnings: response.warnings,
            metrics: metrics,
            accounting: accounting
        )
    }

    private func makeResponseContentSnapshot(
        _ content: AIContent,
        redaction: AITelemetryRedaction
    ) -> AIContentSnapshot {
        switch content {
        case .text(let value):
            let text: String? = {
                switch redaction.responses {
                case .none: return nil
                case .summary: return "[\(value.count) chars]"
                case .full: return value
                }
            }()
            return AIContentSnapshot(kind: .text, text: text, mediaType: nil, toolName: nil, toolUseID: nil)

        case .image(let image):
            return AIContentSnapshot(
                kind: .image,
                text: nil,
                mediaType: image.mediaType.rawValue,
                toolName: nil,
                toolUseID: nil
            )

        case .document(let doc):
            return AIContentSnapshot(
                kind: .document,
                text: nil,
                mediaType: doc.mediaType.rawValue,
                toolName: nil,
                toolUseID: nil
            )

        case .toolUse(let toolUse):
            let inputJSON: String? = {
                switch redaction.toolArguments {
                case .none: return nil
                case .summary: return "[\(toolUse.input.count) bytes]"
                case .full: return String(data: toolUse.input, encoding: .utf8)
                }
            }()
            return AIContentSnapshot(
                kind: .toolUse,
                text: inputJSON,
                mediaType: nil,
                toolName: toolUse.name,
                toolUseID: toolUse.id
            )

        case .toolResult(let result):
            let text: String? = {
                switch redaction.toolResults {
                case .none: return nil
                case .summary: return "[\(result.content.count) chars]"
                case .full: return result.content
                }
            }()
            return AIContentSnapshot(
                kind: .toolResult,
                text: text,
                mediaType: nil,
                toolName: nil,
                toolUseID: result.toolUseId
            )
        }
    }

    // MARK: - Embedding Snapshots

    private func makeEmbeddingRequestSnapshot(
        _ request: AIEmbeddingRequest,
        redaction: AITelemetryRedaction,
        batchIndex: Int? = nil,
        batchCount: Int? = nil
    ) -> AIEmbeddingRequestSnapshot {
        let inputs = request.inputs.map { input in
            makeEmbeddingInputSnapshot(input, redaction: redaction)
        }

        return AIEmbeddingRequestSnapshot(
            model: request.model,
            inputs: inputs,
            dimensions: request.dimensions,
            headers: redactHeaders(request.headers, allowed: redaction.allowedHeaderNames),
            batchIndex: batchIndex,
            batchCount: batchCount
        )
    }

    private func makeEmbeddingInputSnapshot(
        _ input: AIEmbeddingInput,
        redaction: AITelemetryRedaction
    ) -> AIEmbeddingInputSnapshot {
        switch input {
        case .text(let value):
            let text: String? = {
                switch redaction.embeddingInputs {
                case .none: return nil
                case .summary: return "[\(value.count) chars]"
                case .full: return value
                }
            }()
            return AIEmbeddingInputSnapshot(kind: .text, text: text)
        }
    }

    private func makeEmbeddingResponseSnapshot(
        _ response: AIEmbeddingResponse,
        redaction: AITelemetryRedaction,
        metrics: AITelemetryMetrics?,
        accounting: AIAccounting?,
        batchIndex: Int? = nil,
        batchCount: Int? = nil
    ) -> AIEmbeddingResponseSnapshot {
        let embeddings = response.embeddings.map { embedding in
            makeEmbeddingVectorSnapshot(embedding, redaction: redaction)
        }

        return AIEmbeddingResponseSnapshot(
            model: response.model,
            embeddings: embeddings,
            warnings: response.warnings,
            metrics: metrics,
            accounting: accounting,
            batchIndex: batchIndex,
            batchCount: batchCount
        )
    }

    private func makeEmbeddingVectorSnapshot(
        _ embedding: AIEmbedding,
        redaction: AITelemetryRedaction
    ) -> AIEmbeddingVectorSnapshot {
        let vector: [Float]? = {
            switch redaction.embeddingVectors {
            case .none: return nil
            case .summary: return nil
            case .full: return embedding.vector
            }
        }()

        return AIEmbeddingVectorSnapshot(
            index: embedding.index,
            dimensions: embedding.vector.count,
            vector: vector
        )
    }

    // MARK: - Header Redaction

    private static let sensitiveHeaderPrefixes: Set<String> = [
        "authorization",
        "x-api-key",
        "api-key",
        "bearer",
    ]

    private func redactHeaders(
        _ headers: [String: String],
        allowed: Set<String>
    ) -> [String: String] {
        let lowercasedAllowed = Set(allowed.map { $0.lowercased() })

        return headers.filter { key, _ in
            let lowKey = key.lowercased()

            for prefix in Self.sensitiveHeaderPrefixes where lowKey.hasPrefix(prefix) {
                return false
            }

            return lowercasedAllowed.contains(lowKey) || allowed.isEmpty && !isSensitiveHeader(lowKey)
        }
    }

    private func isSensitiveHeader(_ lowercasedKey: String) -> Bool {
        for prefix in Self.sensitiveHeaderPrefixes where lowercasedKey.hasPrefix(prefix) {
            return true
        }
        return false
    }
}
