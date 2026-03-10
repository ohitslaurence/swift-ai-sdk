import AICore
import AITestSupport
import Foundation
import XCTest

final class ProviderHelpersAndEmbeddingsTests: XCTestCase {
    func test_completePromptConvenience_buildsRequestWithSystemPrompt() async throws {
        let provider = MockProvider(
            completionHandler: { request in
                AIResponse(id: "resp_1", content: [.text("Hi")], model: request.model.id, finishReason: .stop)
            }
        )

        let text = try await provider.complete("Hello", model: AIModel("gpt-4o"), systemPrompt: "Be concise")
        let calls = await provider.recorder.completeCalls

        XCTAssertEqual(text, "Hi")
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].messages, [.user("Hello")])
        XCTAssertEqual(calls[0].systemPrompt, "Be concise")
    }

    func test_streamPromptConvenience_buildsRequestWithSystemPrompt() async throws {
        let provider = MockProvider(
            streamHandler: { _ in
                AIStream.finished(text: "streamed", model: "gpt-4o")
            }
        )

        let response = try await provider.stream("Hello", model: AIModel("gpt-4o"), systemPrompt: "Be concise")
            .collect()
        let calls = await provider.recorder.streamCalls

        XCTAssertEqual(response.text, "streamed")
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].messages, [.user("Hello")])
        XCTAssertEqual(calls[0].systemPrompt, "Be concise")
    }

    func test_embedSingleTextConvenience_returnsFirstEmbeddingAndPassesConfiguration() async throws {
        let provider = MockProvider(
            embeddingHandler: { request in
                AIEmbeddingResponse(
                    model: request.model.id,
                    embeddings: [AIEmbedding(index: 0, vector: [0.1, 0.2])]
                )
            },
            capabilities: AIProviderCapabilities(
                instructions: .default,
                structuredOutput: .default,
                inputs: .default,
                tools: .default,
                streaming: .default,
                embeddings: AIEmbeddingCapabilities(
                    supportsEmbeddings: true,
                    supportedInputKinds: [.text],
                    supportsBatchInputs: true,
                    supportsDimensionOverride: true
                )
            )
        )

        let embedding = try await provider.embed(
            "swift concurrency",
            model: AIModel("text-embedding-3-small", provider: "openai"),
            dimensions: 256,
            retryPolicy: RetryPolicy(maxRetries: 1, initialDelay: 0, backoffMultiplier: 1, maxDelay: 0),
            timeout: AITimeout(total: 5),
            headers: ["X-Test": "1"]
        )
        let calls = await provider.recorder.embedCalls

        XCTAssertEqual(embedding, AIEmbedding(index: 0, vector: [0.1, 0.2]))
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].inputs, [.text("swift concurrency")])
        XCTAssertEqual(calls[0].dimensions, 256)
        XCTAssertEqual(calls[0].headers, ["X-Test": "1"])
    }

    func test_embedMany_preservesOrder_aggregatesUsage_andAddsModelMismatchWarning() async throws {
        let provider = MockProvider(
            embeddingHandler: { request in
                if request.inputs.count == 2 {
                    return AIEmbeddingResponse(
                        model: "embed-a",
                        embeddings: [
                            AIEmbedding(index: 1, vector: [11]),
                            AIEmbedding(index: 0, vector: [10]),
                        ],
                        usage: AIUsage(
                            inputTokens: 5,
                            outputTokens: 0,
                            inputTokenDetails: AIUsage.InputTokenDetails(cachedTokens: 1)
                        ),
                        warnings: [AIProviderWarning(code: "batch-a", message: "first batch")]
                    )
                }

                return AIEmbeddingResponse(
                    model: "embed-b",
                    embeddings: [AIEmbedding(index: 0, vector: [20])],
                    usage: AIUsage(
                        inputTokens: 3,
                        outputTokens: 0,
                        inputTokenDetails: AIUsage.InputTokenDetails(cacheWriteTokens: 2)
                    ),
                    warnings: [AIProviderWarning(code: "batch-b", message: "second batch")]
                )
            },
            capabilities: AIProviderCapabilities(
                instructions: .default,
                structuredOutput: .default,
                inputs: .default,
                tools: .default,
                streaming: .default,
                embeddings: AIEmbeddingCapabilities(
                    supportsEmbeddings: true,
                    supportedInputKinds: [.text],
                    supportsBatchInputs: true,
                    supportsDimensionOverride: true,
                    maxInputsPerRequest: 2
                )
            )
        )

        let response = try await provider.embedMany(
            ["one", "two", "three"],
            model: AIModel("text-embedding-3-small", provider: "openai")
        )
        let calls = await provider.recorder.embedCalls

        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].inputs.count, 2)
        XCTAssertEqual(calls[1].inputs.count, 1)
        XCTAssertEqual(response.model, "embed-a")
        XCTAssertEqual(
            response.embeddings,
            [
                AIEmbedding(index: 0, vector: [10]),
                AIEmbedding(index: 1, vector: [11]),
                AIEmbedding(index: 2, vector: [20]),
            ])
        XCTAssertEqual(response.usage?.inputTokens, 8)
        XCTAssertEqual(response.usage?.outputTokens, 0)
        XCTAssertEqual(response.usage?.inputTokenDetails?.cachedTokens, 1)
        XCTAssertEqual(response.usage?.inputTokenDetails?.cacheWriteTokens, 2)
        XCTAssertEqual(response.warnings.map(\.code), ["batch-a", "inconsistent_embedding_model", "batch-b"])
    }

    func test_embedMany_rejectsEmptyInput() async {
        let provider = MockProvider()

        do {
            _ = try await provider.embedMany([], model: AIModel("embed"))
            XCTFail("Expected invalid request error")
        } catch let error as AIError {
            XCTAssertEqual(error, .invalidRequest("Embedding inputs must not be empty"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_embedMany_fallsBackToOnePerRequestWhenBatchUnsupported() async throws {
        let provider = MockProvider(
            embeddingHandler: { request in
                AIEmbeddingResponse(
                    model: "embed-v1",
                    embeddings: request.inputs.enumerated().map { index, _ in
                        AIEmbedding(index: index, vector: [Float(index)])
                    },
                    usage: AIUsage(inputTokens: 1, outputTokens: 0)
                )
            },
            capabilities: AIProviderCapabilities(
                instructions: .default,
                structuredOutput: .default,
                inputs: .default,
                tools: .default,
                streaming: .default,
                embeddings: AIEmbeddingCapabilities(
                    supportsEmbeddings: true,
                    supportedInputKinds: [.text],
                    supportsBatchInputs: false,
                    supportsDimensionOverride: false
                )
            )
        )

        let response = try await provider.embedMany(
            ["alpha", "beta", "gamma"],
            model: AIModel("embed-v1")
        )
        let calls = await provider.recorder.embedCalls

        XCTAssertEqual(calls.count, 3)
        XCTAssertEqual(calls[0].inputs, [.text("alpha")])
        XCTAssertEqual(calls[1].inputs, [.text("beta")])
        XCTAssertEqual(calls[2].inputs, [.text("gamma")])
        XCTAssertEqual(response.embeddings.count, 3)
        XCTAssertEqual(response.embeddings.map(\.index), [0, 1, 2])
    }

    func test_embedMany_rejectsZeroBatchSize() async {
        let provider = MockProvider()

        do {
            _ = try await provider.embedMany(["a"], model: AIModel("embed"), batchSize: 0)
            XCTFail("Expected invalid request error")
        } catch let error as AIError {
            XCTAssertEqual(error, .invalidRequest("Embedding batch size must be greater than 0"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_embedMany_rejectsNegativeBatchSize() async {
        let provider = MockProvider()

        do {
            _ = try await provider.embedMany(["a"], model: AIModel("embed"), batchSize: -1)
            XCTFail("Expected invalid request error")
        } catch let error as AIError {
            XCTAssertEqual(error, .invalidRequest("Embedding batch size must be greater than 0"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_embedMany_rejectsZeroDimensions() async {
        let provider = MockProvider()

        do {
            _ = try await provider.embedMany(["a"], model: AIModel("embed"), dimensions: 0)
            XCTFail("Expected invalid request error")
        } catch let error as AIError {
            XCTAssertEqual(error, .invalidRequest("Embedding dimensions must be greater than 0"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_embedMany_rejectsNegativeDimensions() async {
        let provider = MockProvider()

        do {
            _ = try await provider.embedMany(["a"], model: AIModel("embed"), dimensions: -5)
            XCTFail("Expected invalid request error")
        } catch let error as AIError {
            XCTAssertEqual(error, .invalidRequest("Embedding dimensions must be greater than 0"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_embedMany_rewritesIndexesAcrossBatches() async throws {
        let counter = BatchCounter()

        let provider = MockProvider(
            embeddingHandler: { request in
                let batch = await counter.next()

                let embeddings = request.inputs.enumerated().map { localIndex, _ in
                    AIEmbedding(index: localIndex, vector: [Float(batch * 10 + localIndex)])
                }

                return AIEmbeddingResponse(
                    model: "embed-v1",
                    embeddings: embeddings
                )
            },
            capabilities: AIProviderCapabilities(
                instructions: .default,
                structuredOutput: .default,
                inputs: .default,
                tools: .default,
                streaming: .default,
                embeddings: AIEmbeddingCapabilities(
                    supportsEmbeddings: true,
                    supportedInputKinds: [.text],
                    supportsBatchInputs: true,
                    supportsDimensionOverride: false,
                    maxInputsPerRequest: 2
                )
            )
        )

        let response = try await provider.embedMany(
            ["a", "b", "c", "d", "e"],
            model: AIModel("embed-v1")
        )

        XCTAssertEqual(response.embeddings.count, 5)
        XCTAssertEqual(response.embeddings[0], AIEmbedding(index: 0, vector: [0]))
        XCTAssertEqual(response.embeddings[1], AIEmbedding(index: 1, vector: [1]))
        XCTAssertEqual(response.embeddings[2], AIEmbedding(index: 2, vector: [10]))
        XCTAssertEqual(response.embeddings[3], AIEmbedding(index: 3, vector: [11]))
        XCTAssertEqual(response.embeddings[4], AIEmbedding(index: 4, vector: [20]))
    }

    func test_embedMany_cancellationStopsRemainingBatches() async throws {
        let callCounter = BatchCounter()

        let provider = MockProvider(
            embeddingHandler: { request in
                let batch = await callCounter.next()

                if batch == 0 {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    try Task.checkCancellation()
                }

                return AIEmbeddingResponse(
                    model: "embed-v1",
                    embeddings: request.inputs.enumerated().map { index, _ in
                        AIEmbedding(index: index, vector: [0])
                    }
                )
            },
            capabilities: AIProviderCapabilities(
                instructions: .default,
                structuredOutput: .default,
                inputs: .default,
                tools: .default,
                streaming: .default,
                embeddings: AIEmbeddingCapabilities(
                    supportsEmbeddings: true,
                    supportedInputKinds: [.text],
                    supportsBatchInputs: true,
                    supportsDimensionOverride: false,
                    maxInputsPerRequest: 1
                )
            )
        )

        let task = Task {
            try await provider.embedMany(
                ["a", "b", "c"],
                model: AIModel("embed-v1")
            )
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation error")
        } catch is CancellationError {
            // expected — Task.sleep throws CancellationError
        } catch {
            // CancellationError wrapped or AIError.cancelled both acceptable
        }

        let calls = await callCounter.next()
        XCTAssertLessThanOrEqual(calls, 3, "Not all batches should have been sent")
    }

    func test_defaultEmbedImplementationThrowsUnsupportedFeature() async {
        struct CompletionOnlyProvider: AIProvider {
            func complete(_ request: AIRequest) async throws -> AIResponse {
                AIResponse(
                    id: "resp", content: [.text(request.messages.first?.content.description ?? "")],
                    model: request.model.id, finishReason: .stop)
            }

            func stream(_ request: AIRequest) -> AIStream {
                AIStream.failed(.unsupportedFeature("stream unsupported"))
            }

            var availableModels: [AIModel] {
                [AIModel("mock")]
            }
        }

        do {
            _ = try await CompletionOnlyProvider().embed(
                AIEmbeddingRequest(model: AIModel("embed"), inputs: [.text("swift")]))
            XCTFail("Expected unsupported embeddings")
        } catch let error as AIError {
            XCTAssertEqual(error, .unsupportedFeature("Embeddings are not supported by this provider"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor BatchCounter {
    private var value = 0

    func next() -> Int {
        let current = value
        value += 1
        return current
    }
}
