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
