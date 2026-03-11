import AICore
import AIProviderOpenAI
import AITestSupport
import Foundation
import XCTest

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - Test Helpers

private actor RequestCapture {
    private var _body: Data?
    private var _url: URL?
    private var _headers: [String: String]?

    func set(_ request: URLRequest) {
        _body = request.httpBody
        _url = request.url
        _headers = request.allHTTPHeaderFields
    }

    var body: Data? { _body }
    var url: URL? { _url }
    var headers: [String: String]? { _headers }
}

private actor RequestHistoryCapture {
    private var _requests: [URLRequest] = []

    func appendAndCount(_ request: URLRequest) -> Int {
        _requests.append(request)
        return _requests.count
    }

    var requests: [URLRequest] { _requests }
}

private func bodyJSON(_ capture: RequestCapture) async throws -> [String: Any] {
    guard let body = await capture.body else {
        throw NSError(domain: "test", code: 0, userInfo: [NSLocalizedDescriptionKey: "No request body"])
    }
    return try JSONSerialization.jsonObject(with: body) as! [String: Any]
}

private func bodyJSON(_ data: Data) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: data) as! [String: Any]
}

private func httpResponse(
    statusCode: Int = 200,
    headers: [String: String] = [:]
) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.openai.com/v1/chat/completions")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: headers
    )!
}

private func completionJSON(
    id: String = "chatcmpl-abc",
    model: String = "gpt-4o",
    content: String = "Hello!",
    finishReason: String = "stop",
    promptTokens: Int = 10,
    completionTokens: Int = 5
) -> Data {
    """
    {
        "id": "\(id)",
        "object": "chat.completion",
        "model": "\(model)",
        "choices": [{
            "index": 0,
            "message": {
                "role": "assistant",
                "content": "\(content)"
            },
            "finish_reason": "\(finishReason)"
        }],
        "usage": {
            "prompt_tokens": \(promptTokens),
            "completion_tokens": \(completionTokens)
        }
    }
    """.data(using: .utf8)!
}

private func sseStream(_ lines: [String]) -> AsyncThrowingStream<Data, any Error> {
    AsyncThrowingStream { continuation in
        let data = Data(lines.joined(separator: "\n").utf8)
        continuation.yield(data)
        continuation.finish()
    }
}

private func makeProvider(
    apiKey: String = "sk-test",
    baseURL: URL? = nil,
    organization: String? = nil,
    dataHandler: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse) = { _ in
        fatalError("dataHandler not configured")
    },
    streamHandler: @escaping @Sendable (URLRequest) async throws -> AIHTTPStreamResponse = { _ in
        fatalError("streamHandler not configured")
    }
) -> OpenAIProvider {
    OpenAIProvider(
        apiKey: apiKey,
        baseURL: baseURL,
        organization: organization,
        transport: MockTransport(dataHandler: dataHandler, streamHandler: streamHandler)
    )
}

// MARK: - Test 1: Simple Completion

final class OpenAISimpleCompletionTests: XCTestCase {
    func test_simpleCompletionDecodesIntoAIResponse() async throws {
        let provider = makeProvider { _ in
            (completionJSON(), httpResponse())
        }

        let request = AIRequest(model: .gpt(.gpt4o), messages: [.user("Hi")])
        let response = try await provider.complete(request)

        XCTAssertEqual(response.id, "chatcmpl-abc")
        XCTAssertEqual(response.text, "Hello!")
        XCTAssertEqual(response.model, "gpt-4o")
        XCTAssertEqual(response.usage.inputTokens, 10)
        XCTAssertEqual(response.usage.outputTokens, 5)
        XCTAssertEqual(response.finishReason, .stop)
    }
}

// MARK: - Test 2: Streaming

final class OpenAIStreamingTests: XCTestCase {
    func test_streamingYieldsTextDeltasAndFinishes() async throws {
        let provider = makeProvider(
            streamHandler: { _ in
                let lines = [
                    "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}\n",
                    "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"content\":\" world\"},\"finish_reason\":null}]}\n",
                    "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n",
                    "data: [DONE]\n",
                ]

                return AIHTTPStreamResponse(
                    response: httpResponse(),
                    body: sseStream(lines)
                )
            }
        )

        let request = AIRequest(model: .gpt(.gpt4o), messages: [.user("Hi")])
        let response = try await provider.stream(request).collect()

        XCTAssertEqual(response.id, "chatcmpl-1")
        XCTAssertEqual(response.text, "Hello world")
        XCTAssertEqual(response.finishReason, .stop)
    }
}

// MARK: - Test 3: Legacy System Message

final class OpenAISystemMessageTests: XCTestCase {
    func test_legacyChatModelsSerializeSystemPromptAsSystemMessage() async throws {
        let capture = RequestCapture()

        let provider = makeProvider { request in
            await capture.set(request)
            return (completionJSON(), httpResponse())
        }

        let request = AIRequest(
            model: .gpt(.gpt4o),
            messages: [.user("Hi")],
            systemPrompt: "Be helpful"
        )
        _ = try await provider.complete(request)

        let json = try await bodyJSON(capture)
        let messages = json["messages"] as! [[String: Any]]
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[0]["content"] as? String, "Be helpful")
    }
}

// MARK: - Test 4: Reasoning Model Developer Message

final class OpenAIReasoningModelTests: XCTestCase {
    func test_reasoningModelsSerializeSystemPromptAsDeveloperMessage() async throws {
        let capture = RequestCapture()

        let provider = makeProvider { request in
            await capture.set(request)
            return (completionJSON(model: "o3"), httpResponse())
        }

        let request = AIRequest(
            model: .gpt(.o3),
            messages: [.user("Hi")],
            systemPrompt: "Be helpful"
        )
        _ = try await provider.complete(request)

        let json = try await bodyJSON(capture)
        let messages = json["messages"] as! [[String: Any]]
        XCTAssertEqual(messages[0]["role"] as? String, "developer")
        XCTAssertEqual(messages[0]["content"] as? String, "Be helpful")
    }

    func test_gpt5AlsoUsesDeveloperRole() async throws {
        let capture = RequestCapture()

        let provider = makeProvider { request in
            await capture.set(request)
            return (completionJSON(model: "gpt-5"), httpResponse())
        }

        let request = AIRequest(
            model: .gpt(.gpt5),
            messages: [.user("Hi")],
            systemPrompt: "Be helpful"
        )
        _ = try await provider.complete(request)

        let json = try await bodyJSON(capture)
        let messages = json["messages"] as! [[String: Any]]
        XCTAssertEqual(messages[0]["role"] as? String, "developer")
    }
}

// MARK: - Test 5: Vision

final class OpenAIVisionTests: XCTestCase {
    func test_visionRequestsEncodeBase64ImageURLs() async throws {
        let capture = RequestCapture()

        let provider = makeProvider { request in
            await capture.set(request)
            return (completionJSON(), httpResponse())
        }

        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let image = AIImage(data: imageData, mediaType: .jpeg)

        let request = AIRequest(
            model: .gpt(.gpt4o),
            messages: [.user([.text("What is this?"), .image(image)])]
        )
        _ = try await provider.complete(request)

        let json = try await bodyJSON(capture)
        let messages = json["messages"] as! [[String: Any]]
        let content = messages[0]["content"] as! [[String: Any]]

        XCTAssertEqual(content[0]["type"] as? String, "text")
        XCTAssertEqual(content[1]["type"] as? String, "image_url")

        let imageUrl = content[1]["image_url"] as! [String: String]
        let url = imageUrl["url"]!
        XCTAssertTrue(url.hasPrefix("data:image/jpeg;base64,"))
    }
}

// MARK: - Test 6: Tool Definitions

final class OpenAIToolDefinitionTests: XCTestCase {
    func test_toolDefinitionsSerializeAsFunctionTools() async throws {
        let capture = RequestCapture()

        let provider = makeProvider { request in
            await capture.set(request)
            return (completionJSON(), httpResponse())
        }

        let tool = AITool(
            name: "get_weather",
            description: "Get the weather",
            inputSchema: .object(
                properties: ["city": .string()],
                required: ["city"]
            )
        ) { _ in "sunny" }

        let request = AIRequest(
            model: .gpt(.gpt4o),
            messages: [.user("Weather?")],
            tools: [tool]
        )
        _ = try await provider.complete(request)

        let json = try await bodyJSON(capture)
        let tools = json["tools"] as! [[String: Any]]

        XCTAssertEqual(tools[0]["type"] as? String, "function")
        let function = tools[0]["function"] as! [String: Any]
        XCTAssertEqual(function["name"] as? String, "get_weather")
        XCTAssertEqual(function["description"] as? String, "Get the weather")
    }
}

// MARK: - Test 7: Tool Use Response

final class OpenAIToolUseResponseTests: XCTestCase {
    func test_toolCallsDecodeFromAssistantResponse() async throws {
        let responseData = """
            {
                "id": "chatcmpl-tool",
                "model": "gpt-4o",
                "choices": [{
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": null,
                        "tool_calls": [{
                            "id": "call_123",
                            "type": "function",
                            "function": {
                                "name": "get_weather",
                                "arguments": "{\\"city\\":\\"London\\"}"
                            }
                        }]
                    },
                    "finish_reason": "tool_calls"
                }],
                "usage": {"prompt_tokens": 10, "completion_tokens": 5}
            }
            """.data(using: .utf8)!

        let provider = makeProvider { _ in
            (responseData, httpResponse())
        }

        let request = AIRequest(model: .gpt(.gpt4o), messages: [.user("Weather?")])
        let response = try await provider.complete(request)

        XCTAssertEqual(response.finishReason, .toolUse)
        guard case .toolUse(let toolUse) = response.content.first else {
            XCTFail("Expected tool use content")
            return
        }

        XCTAssertEqual(toolUse.id, "call_123")
        XCTAssertEqual(toolUse.name, "get_weather")
        XCTAssertEqual(String(data: toolUse.input, encoding: .utf8), "{\"city\":\"London\"}")
    }
}

// MARK: - Test 8: JSON Mode

final class OpenAIJSONModeTests: XCTestCase {
    func test_jsonResponseFormatSetsJsonObject() async throws {
        let capture = RequestCapture()

        let provider = makeProvider { request in
            await capture.set(request)
            return (completionJSON(content: "{\\\"color\\\":\\\"blue\\\"}"), httpResponse())
        }

        let request = AIRequest(
            model: .gpt(.gpt4o),
            messages: [.user("List a color as JSON")],
            responseFormat: .json
        )
        _ = try await provider.complete(request)

        let json = try await bodyJSON(capture)
        let responseFormat = json["response_format"] as! [String: Any]
        XCTAssertEqual(responseFormat["type"] as? String, "json_object")
    }
}

// MARK: - Test 9: JSON Schema Mode

final class OpenAIJSONSchemaTests: XCTestCase {
    func test_jsonSchemaResponseFormatSetsStrictJsonSchema() async throws {
        let capture = RequestCapture()

        let provider = makeProvider { request in
            await capture.set(request)
            return (completionJSON(), httpResponse())
        }

        let schema = AIJSONSchema.object(
            properties: ["name": .string()],
            required: ["name"]
        )

        let request = AIRequest(
            model: .gpt(.gpt4o),
            messages: [.user("Name?")],
            responseFormat: .jsonSchema(schema)
        )
        _ = try await provider.complete(request)

        let json = try await bodyJSON(capture)
        let responseFormat = json["response_format"] as! [String: Any]
        XCTAssertEqual(responseFormat["type"] as? String, "json_schema")

        let jsonSchema = responseFormat["json_schema"] as! [String: Any]
        XCTAssertNotNil(jsonSchema["name"])
        XCTAssertEqual(jsonSchema["strict"] as? Bool, true)
        XCTAssertNotNil(jsonSchema["schema"])
    }
}

// MARK: - Test 10: max_completion_tokens

final class OpenAIMaxTokensTests: XCTestCase {
    func test_maxCompletionTokensPreferredOverMaxTokens() async throws {
        let capture = RequestCapture()

        let provider = makeProvider { request in
            await capture.set(request)
            return (completionJSON(), httpResponse())
        }

        let request = AIRequest(
            model: .gpt(.gpt4o),
            messages: [.user("Hi")],
            maxTokens: 100
        )
        _ = try await provider.complete(request)

        let json = try await bodyJSON(capture)
        XCTAssertEqual(json["max_completion_tokens"] as? Int, 100)
        XCTAssertNil(json["max_tokens"])
    }
}

// MARK: - Test 11: Unsupported stop on o3/o4-mini

final class OpenAIStopWarningTests: XCTestCase {
    func test_unsupportedStopOnO3EmitsWarning() async throws {
        let capture = RequestCapture()

        let provider = makeProvider { request in
            await capture.set(request)
            return (completionJSON(model: "o3"), httpResponse())
        }

        let request = AIRequest(
            model: .gpt(.o3),
            messages: [.user("Hi")],
            stopSequences: ["END"]
        )
        let response = try await provider.complete(request)

        let json = try await bodyJSON(capture)
        XCTAssertNil(json["stop"])
        XCTAssertTrue(response.warnings.contains(where: { $0.code == "unsupported_stop_sequences" }))
    }

    func test_unsupportedStopOnO4MiniEmitsWarning() async throws {
        let provider = makeProvider { _ in
            (completionJSON(model: "o4-mini"), httpResponse())
        }

        let request = AIRequest(
            model: .gpt(.o4Mini),
            messages: [.user("Hi")],
            stopSequences: ["END"]
        )
        let response = try await provider.complete(request)

        XCTAssertTrue(response.warnings.contains(where: { $0.code == "unsupported_stop_sequences" }))
    }
}

// MARK: - Test 12: Unsupported Document Input

final class OpenAIDocumentInputTests: XCTestCase {
    func test_documentInputThrowsUnsupported() async throws {
        let provider = makeProvider { _ in
            (completionJSON(), httpResponse())
        }

        let doc = AIDocument(data: Data("hello".utf8), mediaType: .plainText)
        let request = AIRequest(
            model: .gpt(.gpt4o),
            messages: [.user([.document(doc)])]
        )

        do {
            _ = try await provider.complete(request)
            XCTFail("Expected unsupportedFeature error")
        } catch let error as AIError {
            if case .unsupportedFeature = error {
                // expected
            } else {
                XCTFail("Expected unsupportedFeature, got \(error)")
            }
        }
    }
}

// MARK: - Test 13: Stream Options Include Usage

final class OpenAIStreamOptionsTests: XCTestCase {
    func test_streamingRequestsIncludeStreamOptionsUsage() async throws {
        let capture = RequestCapture()

        let provider = makeProvider(
            streamHandler: { request in
                await capture.set(request)

                let lines = [
                    "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}\n",
                    "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n",
                    "data: [DONE]\n",
                ]

                return AIHTTPStreamResponse(
                    response: httpResponse(),
                    body: sseStream(lines)
                )
            }
        )

        let request = AIRequest(model: .gpt(.gpt4o), messages: [.user("Hi")])
        _ = try await provider.stream(request).collect()

        let json = try await bodyJSON(capture)
        let streamOptions = json["stream_options"] as! [String: Any]
        XCTAssertEqual(streamOptions["include_usage"] as? Bool, true)
        XCTAssertEqual(json["stream"] as? Bool, true)
    }
}

// MARK: - Test 14: baseURL Override

final class OpenAIBaseURLTests: XCTestCase {
    func test_baseURLOverrideRewritesRequestURLs() async throws {
        let capture = RequestCapture()

        let provider = makeProvider(baseURL: URL(string: "https://custom.api.com")!) { request in
            await capture.set(request)
            return (completionJSON(), httpResponse())
        }

        let request = AIRequest(model: .gpt(.gpt4o), messages: [.user("Hi")])
        _ = try await provider.complete(request)

        let url = await capture.url
        XCTAssertEqual(url?.absoluteString, "https://custom.api.com/v1/chat/completions")
    }
}

// MARK: - Test 15: 429 Retry-After

final class OpenAIRetryAfterTests: XCTestCase {
    func test_rateLimited429ParsesRetryAfterMs() async throws {
        let provider = makeProvider { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/chat/completions")!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["retry-after-ms": "5000"]
            )!

            return (Data("{}".utf8), response)
        }

        let request = AIRequest(
            model: .gpt(.gpt4o),
            messages: [.user("Hi")],
            retryPolicy: .none
        )

        do {
            _ = try await provider.complete(request)
            XCTFail("Expected rateLimited error")
        } catch let error as AIError {
            if case .rateLimited(let retryAfter) = error {
                XCTAssertEqual(retryAfter, 5.0)
            } else {
                XCTFail("Expected rateLimited, got \(error)")
            }
        }
    }
}

// MARK: - Test 16: Detailed Usage

final class OpenAIDetailedUsageTests: XCTestCase {
    func test_detailedUsageFieldsMapIntoAIUsage() async throws {
        let responseData = """
            {
                "id": "chatcmpl-usage",
                "model": "gpt-4o",
                "choices": [{
                    "index": 0,
                    "message": {"role": "assistant", "content": "Hi"},
                    "finish_reason": "stop"
                }],
                "usage": {
                    "prompt_tokens": 100,
                    "completion_tokens": 50,
                    "prompt_tokens_details": {"cached_tokens": 20},
                    "completion_tokens_details": {"reasoning_tokens": 10}
                }
            }
            """.data(using: .utf8)!

        let provider = makeProvider { _ in
            (responseData, httpResponse())
        }

        let request = AIRequest(model: .gpt(.gpt4o), messages: [.user("Hi")])
        let response = try await provider.complete(request)

        XCTAssertEqual(response.usage.inputTokens, 100)
        XCTAssertEqual(response.usage.outputTokens, 50)
        XCTAssertEqual(response.usage.inputTokenDetails?.cachedTokens, 20)
        XCTAssertEqual(response.usage.outputTokenDetails?.reasoningTokens, 10)
    }
}

// MARK: - Test 17: Custom Headers

final class OpenAICustomHeaderTests: XCTestCase {
    func test_customHeadersFromAIRequestAreForwarded() async throws {
        let capture = RequestCapture()

        let provider = makeProvider { request in
            await capture.set(request)
            return (completionJSON(), httpResponse())
        }

        var request = AIRequest(model: .gpt(.gpt4o), messages: [.user("Hi")])
        request.headers["X-Custom"] = "test-value"
        _ = try await provider.complete(request)

        let headers = await capture.headers
        XCTAssertEqual(headers?["X-Custom"], "test-value")
        XCTAssertTrue(headers?["Authorization"]?.hasPrefix("Bearer ") ?? false)
    }
}

// MARK: - Test 18: Stream Cancellation

final class OpenAIStreamCancellationTests: XCTestCase {
    func test_streamCancellationStopsTransport() async throws {
        let transportCalled = expectation(description: "transport called")

        let provider = makeProvider(
            streamHandler: { _ in
                transportCalled.fulfill()

                let body = AsyncThrowingStream<Data, any Error>(Data.self, bufferingPolicy: .unbounded) {
                    continuation in
                    continuation.yield(
                        Data(
                            "data: {\"id\":\"x\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}\n"
                                .utf8))
                }

                return AIHTTPStreamResponse(response: httpResponse(), body: body)
            }
        )

        let request = AIRequest(model: .gpt(.gpt4o), messages: [.user("Hi")])
        let stream = provider.stream(request)

        let task = Task {
            for try await _ in stream {}
        }

        await fulfillment(of: [transportCalled], timeout: 2)
        task.cancel()

        do {
            try await task.value
        } catch {
            // Cancellation expected
        }
    }
}

// MARK: - Test 19: Embeddings

final class OpenAIEmbeddingTests: XCTestCase {
    func test_embedSendsEmbeddingsEndpointAndDecodesVector() async throws {
        let capture = RequestCapture()

        let responseData = """
            {
                "model": "text-embedding-3-small",
                "data": [{
                    "index": 0,
                    "embedding": [0.1, 0.2, 0.3]
                }],
                "usage": {"total_tokens": 5}
            }
            """.data(using: .utf8)!

        let provider = makeProvider { request in
            await capture.set(request)
            return (responseData, httpResponse())
        }

        let request = AIEmbeddingRequest(
            model: .openAIEmbedding(.textEmbedding3Small),
            inputs: [.text("swift concurrency")]
        )

        let response = try await provider.embed(request)

        let url = await capture.url
        XCTAssertTrue(url?.absoluteString.contains("/v1/embeddings") ?? false)
        XCTAssertEqual(response.model, "text-embedding-3-small")
        XCTAssertEqual(response.embeddings.count, 1)
        XCTAssertEqual(response.embeddings[0].index, 0)
        XCTAssertEqual(response.embeddings[0].vector, [0.1, 0.2, 0.3])
    }
}

// MARK: - Test 20: Batch Embedding Inputs

final class OpenAIBatchEmbeddingTests: XCTestCase {
    func test_batchEmbeddingInputsSerializeAsArray() async throws {
        let capture = RequestCapture()

        let responseData = """
            {
                "model": "text-embedding-3-small",
                "data": [
                    {"index": 0, "embedding": [0.1]},
                    {"index": 1, "embedding": [0.2]}
                ],
                "usage": {"total_tokens": 10}
            }
            """.data(using: .utf8)!

        let provider = makeProvider { request in
            await capture.set(request)
            return (responseData, httpResponse())
        }

        let request = AIEmbeddingRequest(
            model: .openAIEmbedding(.textEmbedding3Small),
            inputs: [.text("hello"), .text("world")]
        )

        let response = try await provider.embed(request)

        let json = try await bodyJSON(capture)
        let input = json["input"] as! [String]
        XCTAssertEqual(input, ["hello", "world"])
        XCTAssertEqual(response.embeddings.count, 2)
    }
}

// MARK: - Test 21: Embedding Dimensions

final class OpenAIEmbeddingDimensionsTests: XCTestCase {
    func test_embeddingDimensionsForwarded() async throws {
        let capture = RequestCapture()

        let responseData = """
            {
                "model": "text-embedding-3-small",
                "data": [{"index": 0, "embedding": [0.1, 0.2]}],
                "usage": {"total_tokens": 5}
            }
            """.data(using: .utf8)!

        let provider = makeProvider { request in
            await capture.set(request)
            return (responseData, httpResponse())
        }

        let request = AIEmbeddingRequest(
            model: .openAIEmbedding(.textEmbedding3Small),
            inputs: [.text("test")],
            dimensions: 256
        )

        _ = try await provider.embed(request)

        let json = try await bodyJSON(capture)
        XCTAssertEqual(json["dimensions"] as? Int, 256)
    }
}

// MARK: - Test 22: Embedding Usage Mapping

final class OpenAIEmbeddingUsageTests: XCTestCase {
    func test_embeddingUsageMapsToAIUsage() async throws {
        let responseData = """
            {
                "model": "text-embedding-3-small",
                "data": [{"index": 0, "embedding": [0.1]}],
                "usage": {"total_tokens": 42}
            }
            """.data(using: .utf8)!

        let provider = makeProvider { _ in
            (responseData, httpResponse())
        }

        let request = AIEmbeddingRequest(
            model: .openAIEmbedding(.textEmbedding3Small),
            inputs: [.text("test")]
        )

        let response = try await provider.embed(request)

        XCTAssertEqual(response.usage?.inputTokens, 42)
        XCTAssertEqual(response.usage?.outputTokens, 0)
    }
}

// MARK: - Test 23: Available Models Include Embedding IDs

final class OpenAIAvailableModelsTests: XCTestCase {
    func test_availableModelsIncludesEmbeddingModelIDs() {
        let provider = OpenAIProvider(apiKey: "test")

        XCTAssertTrue(provider.availableModels.contains(.openAIEmbedding(.textEmbedding3Small)))
        XCTAssertTrue(provider.availableModels.contains(.openAIEmbedding(.textEmbedding3Large)))
        XCTAssertTrue(provider.availableModels.contains(.gpt(.gpt4o)))
        XCTAssertTrue(provider.availableModels.contains(.gpt(.o3)))
    }
}

// MARK: - Additional Coverage

final class OpenAIErrorMappingTests: XCTestCase {
    func test_401MapsToAuthenticationFailed() async throws {
        let provider = makeProvider { _ in
            (Data("{\"error\":{\"message\":\"Invalid API key\"}}".utf8), httpResponse(statusCode: 401))
        }

        let request = AIRequest(model: .gpt(.gpt4o), messages: [.user("Hi")])

        do {
            _ = try await provider.complete(request)
            XCTFail("Expected authenticationFailed")
        } catch let error as AIError {
            XCTAssertEqual(error, .authenticationFailed)
        }
    }

    func test_404MapsToModelNotFound() async throws {
        let provider = makeProvider { _ in
            (Data("{\"error\":{\"message\":\"Model not found\"}}".utf8), httpResponse(statusCode: 404))
        }

        let request = AIRequest(model: .gpt(.gpt4o), messages: [.user("Hi")])

        do {
            _ = try await provider.complete(request)
            XCTFail("Expected modelNotFound")
        } catch let error as AIError {
            if case .modelNotFound(let id) = error {
                XCTAssertEqual(id, "gpt-4o")
            } else {
                XCTFail("Expected modelNotFound, got \(error)")
            }
        }
    }

    func test_500MapsToServerError() async throws {
        let provider = makeProvider { _ in
            (Data("{\"error\":{\"message\":\"Internal error\"}}".utf8), httpResponse(statusCode: 500))
        }

        let request = AIRequest(model: .gpt(.gpt4o), messages: [.user("Hi")], retryPolicy: .none)

        do {
            _ = try await provider.complete(request)
            XCTFail("Expected serverError")
        } catch let error as AIError {
            if case .serverError(let code, _) = error {
                XCTAssertEqual(code, 500)
            } else {
                XCTFail("Expected serverError, got \(error)")
            }
        }
    }
}

final class OpenAIToolChoiceTests: XCTestCase {
    func test_toolChoiceRequiredSerializes() async throws {
        let capture = RequestCapture()

        let provider = makeProvider { request in
            await capture.set(request)
            return (completionJSON(), httpResponse())
        }

        let tool = AITool(
            name: "test",
            description: "test",
            inputSchema: .object(properties: [:], required: [])
        ) { _ in "" }

        let request = AIRequest(
            model: .gpt(.gpt4o),
            messages: [.user("Hi")],
            tools: [tool],
            toolChoice: .required
        )
        _ = try await provider.complete(request)

        let json = try await bodyJSON(capture)
        XCTAssertEqual(json["tool_choice"] as? String, "required")
    }

    func test_parallelToolCallsSerializes() async throws {
        let capture = RequestCapture()

        let provider = makeProvider { request in
            await capture.set(request)
            return (completionJSON(), httpResponse())
        }

        let tool = AITool(
            name: "test",
            description: "test",
            inputSchema: .object(properties: [:], required: [])
        ) { _ in "" }

        let request = AIRequest(
            model: .gpt(.gpt4o),
            messages: [.user("Hi")],
            tools: [tool],
            allowParallelToolCalls: false
        )
        _ = try await provider.complete(request)

        let json = try await bodyJSON(capture)
        XCTAssertEqual(json["parallel_tool_calls"] as? Bool, false)
    }

    func test_toolChoiceFunctionSerializes() async throws {
        let capture = RequestCapture()

        let provider = makeProvider { request in
            await capture.set(request)
            return (completionJSON(), httpResponse())
        }

        let tool = AITool(
            name: "my_tool",
            description: "test",
            inputSchema: .object(properties: [:], required: [])
        ) { _ in "" }

        let request = AIRequest(
            model: .gpt(.gpt4o),
            messages: [.user("Hi")],
            tools: [tool],
            toolChoice: .tool("my_tool")
        )
        _ = try await provider.complete(request)

        let json = try await bodyJSON(capture)
        let toolChoice = json["tool_choice"] as! [String: Any]
        XCTAssertEqual(toolChoice["type"] as? String, "function")
        let function = toolChoice["function"] as! [String: String]
        XCTAssertEqual(function["name"], "my_tool")
    }
}

final class OpenAIOrganizationHeaderTests: XCTestCase {
    func test_organizationHeaderSent() async throws {
        let capture = RequestCapture()

        let provider = makeProvider(organization: "org-abc") { request in
            await capture.set(request)
            return (completionJSON(), httpResponse())
        }

        let request = AIRequest(model: .gpt(.gpt4o), messages: [.user("Hi")])
        _ = try await provider.complete(request)

        let headers = await capture.headers
        XCTAssertEqual(headers?["OpenAI-Organization"], "org-abc")
    }
}

final class OpenAIFinishReasonTests: XCTestCase {
    func test_lengthFinishReasonMapsToMaxTokens() async throws {
        let provider = makeProvider { _ in
            (completionJSON(finishReason: "length"), httpResponse())
        }

        let request = AIRequest(model: .gpt(.gpt4o), messages: [.user("Hi")])
        let response = try await provider.complete(request)

        XCTAssertEqual(response.finishReason, .maxTokens)
    }

    func test_contentFilterFinishReasonMaps() async throws {
        let provider = makeProvider { _ in
            (completionJSON(finishReason: "content_filter"), httpResponse())
        }

        let request = AIRequest(model: .gpt(.gpt4o), messages: [.user("Hi")])
        let response = try await provider.complete(request)

        XCTAssertEqual(response.finishReason, .contentFilter)
    }

    func test_unknownFinishReasonMaps() async throws {
        let provider = makeProvider { _ in
            (completionJSON(finishReason: "something_new"), httpResponse())
        }

        let request = AIRequest(model: .gpt(.gpt4o), messages: [.user("Hi")])
        let response = try await provider.complete(request)

        XCTAssertEqual(response.finishReason, .unknown("something_new"))
    }
}

final class OpenAIStreamUsageTests: XCTestCase {
    func test_streamUsageChunkEmitsUsageEvent() async throws {
        let provider = makeProvider(
            streamHandler: { _ in
                let lines = [
                    "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}\n",
                    "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n",
                    "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-4o\",\"choices\":[],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5,\"prompt_tokens_details\":{\"cached_tokens\":3},\"completion_tokens_details\":{\"reasoning_tokens\":2}}}\n",
                    "data: [DONE]\n",
                ]

                return AIHTTPStreamResponse(
                    response: httpResponse(),
                    body: sseStream(lines)
                )
            }
        )

        let request = AIRequest(model: .gpt(.gpt4o), messages: [.user("Hi")])
        let response = try await provider.stream(request).collect()

        XCTAssertEqual(response.usage.inputTokens, 10)
        XCTAssertEqual(response.usage.outputTokens, 5)
        XCTAssertEqual(response.usage.inputTokenDetails?.cachedTokens, 3)
        XCTAssertEqual(response.usage.outputTokenDetails?.reasoningTokens, 2)
    }
}

final class OpenAIStreamToolUseTests: XCTestCase {
    func test_streamToolCallsDecoded() async throws {
        let provider = makeProvider(
            streamHandler: { _ in
                let lines = [
                    "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"function\":{\"name\":\"get_weather\",\"arguments\":\"\"}}]},\"finish_reason\":null}]}\n",
                    "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"city\\\"\"}}]},\"finish_reason\":null}]}\n",
                    "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\":\\\"London\\\"}\"}}]},\"finish_reason\":null}]}\n",
                    "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n",
                    "data: [DONE]\n",
                ]

                return AIHTTPStreamResponse(
                    response: httpResponse(),
                    body: sseStream(lines)
                )
            }
        )

        let request = AIRequest(model: .gpt(.gpt4o), messages: [.user("Weather?")])
        var events: [AIStreamEvent] = []

        for try await event in provider.stream(request) {
            events.append(event)
        }

        XCTAssertTrue(
            events.contains(where: {
                if case .toolUseStart(let id, let name) = $0 {
                    return id == "call_1" && name == "get_weather"
                }
                return false
            }))

        let toolInputs = events.compactMap { event -> String? in
            if case .delta(.toolInput(_, let json)) = event {
                return json
            }
            return nil
        }

        XCTAssertEqual(toolInputs.joined(), "{\"city\":\"London\"}")
    }
}

final class OpenAIToolTranscriptReplayTests: XCTestCase {
    func test_assistantToolCallAndToolResultSerialize() async throws {
        let capture = RequestCapture()

        let provider = makeProvider { request in
            await capture.set(request)
            return (completionJSON(), httpResponse())
        }

        let toolUse = AIToolUse(id: "call_1", name: "calc", input: Data("{\"x\":1}".utf8))
        let request = AIRequest(
            model: .gpt(.gpt4o),
            messages: [
                .user("Compute"),
                .assistant([.toolUse(toolUse)]),
                .tool(id: "call_1", content: "42"),
            ]
        )
        _ = try await provider.complete(request)

        let json = try await bodyJSON(capture)
        let messages = json["messages"] as! [[String: Any]]

        XCTAssertEqual(messages[1]["role"] as? String, "assistant")
        let toolCalls = messages[1]["tool_calls"] as! [[String: Any]]
        XCTAssertEqual(toolCalls[0]["id"] as? String, "call_1")
        let function = toolCalls[0]["function"] as! [String: String]
        XCTAssertEqual(function["name"], "calc")

        XCTAssertEqual(messages[2]["role"] as? String, "tool")
        XCTAssertEqual(messages[2]["tool_call_id"] as? String, "call_1")
        XCTAssertEqual(messages[2]["content"] as? String, "42")
    }
}

final class OpenAIEmbeddingBaseURLTests: XCTestCase {
    func test_embeddingBaseURLOverride() async throws {
        let capture = RequestCapture()

        let responseData = """
            {
                "model": "text-embedding-3-small",
                "data": [{"index": 0, "embedding": [0.1]}],
                "usage": {"total_tokens": 5}
            }
            """.data(using: .utf8)!

        let provider = makeProvider(baseURL: URL(string: "https://custom.api.com")!) { request in
            await capture.set(request)
            return (responseData, httpResponse())
        }

        let request = AIEmbeddingRequest(
            model: .openAIEmbedding(.textEmbedding3Small),
            inputs: [.text("test")]
        )

        _ = try await provider.embed(request)

        let url = await capture.url
        XCTAssertEqual(url?.absoluteString, "https://custom.api.com/v1/embeddings")
    }
}

final class OpenAIRequestForwardingTests: XCTestCase {
    func test_defaultHeadersMergeWithRequestHeadersUsingRequestPrecedence() async throws {
        let capture = RequestCapture()

        let provider = OpenAIProvider(
            apiKey: "sk-test",
            transport: MockTransport(
                dataHandler: { request in
                    await capture.set(request)
                    return (completionJSON(), httpResponse())
                },
                streamHandler: { _ in
                    fatalError("streamHandler not configured")
                }
            ),
            defaultHeaders: ["X-Provider": "provider", "X-Shared": "provider"]
        )

        let request = AIRequest(
            model: .gpt(.gpt4o),
            messages: [.user("Hi")],
            headers: ["X-Request": "request", "X-Shared": "request"]
        )
        _ = try await provider.complete(request)

        let headers = await capture.headers
        XCTAssertEqual(headers?["X-Provider"], "provider")
        XCTAssertEqual(headers?["X-Request"], "request")
        XCTAssertEqual(headers?["X-Shared"], "request")
    }

    func test_metadataIsForwarded() async throws {
        let capture = RequestCapture()

        let provider = makeProvider { request in
            await capture.set(request)
            return (completionJSON(), httpResponse())
        }

        let request = AIRequest(
            model: .gpt(.gpt4o),
            messages: [.user("Hi")],
            metadata: ["feature": "spec-review", "team": "sdk"]
        )
        _ = try await provider.complete(request)

        let json = try await bodyJSON(capture)
        let metadata = json["metadata"] as? [String: String]
        XCTAssertEqual(metadata?["feature"], "spec-review")
        XCTAssertEqual(metadata?["team"], "sdk")
    }
}

final class OpenAIReasoningWarningTests: XCTestCase {
    func test_reasoningModelsWarnForTemperatureAndTopP() async throws {
        let provider = makeProvider { _ in
            (completionJSON(model: "gpt-5"), httpResponse())
        }

        let request = AIRequest(
            model: .gpt(.gpt5),
            messages: [.user("Hi")],
            temperature: 0.3,
            topP: 0.7
        )
        let response = try await provider.complete(request)

        XCTAssertTrue(response.warnings.contains(where: { $0.code == "unsupported_temperature" }))
        XCTAssertTrue(response.warnings.contains(where: { $0.code == "unsupported_top_p" }))
    }
}

final class OpenAICompatibilityFallbackTests: XCTestCase {
    func test_compatibleBackendFallsBackToLegacyMaxTokensForCompletion() async throws {
        let history = RequestHistoryCapture()

        let provider = makeProvider(baseURL: URL(string: "https://compatible.example.com")!) { request in
            let attempt = await history.appendAndCount(request)

            if attempt == 1 {
                let error = Data("{\"error\":{\"message\":\"Unsupported field: max_completion_tokens\"}}".utf8)
                return (error, httpResponse(statusCode: 400))
            }

            return (completionJSON(), httpResponse())
        }

        let request = AIRequest(
            model: .gpt(.gpt4o),
            messages: [.user("Hi")],
            maxTokens: 128,
            retryPolicy: .none
        )
        let response = try await provider.complete(request)

        let requests = await history.requests
        XCTAssertEqual(requests.count, 2)

        let firstRequest = try XCTUnwrap(requests[0].httpBody)
        let secondRequest = try XCTUnwrap(requests[1].httpBody)
        let firstJSON = try bodyJSON(firstRequest)
        let secondJSON = try bodyJSON(secondRequest)

        XCTAssertEqual(firstJSON["max_completion_tokens"] as? Int, 128)
        XCTAssertNil(firstJSON["max_tokens"])
        XCTAssertNil(secondJSON["max_completion_tokens"])
        XCTAssertEqual(secondJSON["max_tokens"] as? Int, 128)
        XCTAssertTrue(response.warnings.contains(where: { $0.code == "legacy_max_tokens_fallback" }))
    }

    func test_compatibleBackendFallsBackToLegacyMaxTokensForStreaming() async throws {
        let history = RequestHistoryCapture()

        let provider = makeProvider(
            baseURL: URL(string: "https://compatible.example.com")!,
            streamHandler: { request in
                let attempt = await history.appendAndCount(request)

                if attempt == 1 {
                    let errorBody = Data("{\"error\":{\"message\":\"Unsupported field: max_completion_tokens\"}}".utf8)
                    let body = AsyncThrowingStream<Data, any Error>(Data.self, bufferingPolicy: .unbounded) {
                        continuation in
                        continuation.yield(errorBody)
                        continuation.finish()
                    }

                    return AIHTTPStreamResponse(
                        response: httpResponse(statusCode: 400),
                        body: body
                    )
                }

                return AIHTTPStreamResponse(
                    response: httpResponse(),
                    body: sseStream([
                        "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}\n",
                        "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n",
                        "data: [DONE]\n",
                    ])
                )
            }
        )

        let request = AIRequest(
            model: .gpt(.gpt4o),
            messages: [.user("Hi")],
            maxTokens: 64,
            retryPolicy: .none
        )
        let response = try await provider.stream(request).collect()

        let requests = await history.requests
        XCTAssertEqual(requests.count, 2)

        let firstRequest = try XCTUnwrap(requests[0].httpBody)
        let secondRequest = try XCTUnwrap(requests[1].httpBody)
        let firstJSON = try bodyJSON(firstRequest)
        let secondJSON = try bodyJSON(secondRequest)

        XCTAssertEqual(firstJSON["max_completion_tokens"] as? Int, 64)
        XCTAssertNil(secondJSON["max_completion_tokens"])
        XCTAssertEqual(secondJSON["max_tokens"] as? Int, 64)
        XCTAssertEqual(response.text, "Hello")
        XCTAssertTrue(response.warnings.contains(where: { $0.code == "legacy_max_tokens_fallback" }))
    }
}

final class OpenAIRequestModelTests: XCTestCase {
    func test_customChatModelIDIsForwarded() async throws {
        let capture = RequestCapture()

        let provider = makeProvider { request in
            await capture.set(request)
            return (completionJSON(model: "gpt-custom"), httpResponse())
        }

        let request = AIRequest(model: .gpt(.custom("gpt-custom")), messages: [.user("Hi")])
        _ = try await provider.complete(request)

        let json = try await bodyJSON(capture)
        XCTAssertEqual(json["model"] as? String, "gpt-custom")
    }

    func test_customEmbeddingModelIDIsForwarded() async throws {
        let capture = RequestCapture()

        let responseData = """
            {
                "model": "text-embedding-custom",
                "data": [{"index": 0, "embedding": [0.1]}],
                "usage": {"total_tokens": 5}
            }
            """.data(using: .utf8)!

        let provider = makeProvider { request in
            await capture.set(request)
            return (responseData, httpResponse())
        }

        let request = AIEmbeddingRequest(
            model: .openAIEmbedding(.custom("text-embedding-custom")),
            inputs: [.text("swift")]
        )
        _ = try await provider.embed(request)

        let json = try await bodyJSON(capture)
        XCTAssertEqual(json["model"] as? String, "text-embedding-custom")
    }
}

final class OpenAIEmbeddingRequestBuilderTests: XCTestCase {
    func test_singleEmbeddingInputSerializesAsString() async throws {
        let capture = RequestCapture()

        let responseData = """
            {
                "model": "text-embedding-3-small",
                "data": [{"index": 0, "embedding": [0.1]}],
                "usage": {"total_tokens": 5}
            }
            """.data(using: .utf8)!

        let provider = makeProvider { request in
            await capture.set(request)
            return (responseData, httpResponse())
        }

        let request = AIEmbeddingRequest(
            model: .openAIEmbedding(.textEmbedding3Small),
            inputs: [.text("swift concurrency")]
        )
        _ = try await provider.embed(request)

        let json = try await bodyJSON(capture)
        XCTAssertEqual(json["input"] as? String, "swift concurrency")
    }

    func test_dimensionsAreDroppedForUnsupportedEmbeddingModelsWithWarning() async throws {
        let capture = RequestCapture()

        let responseData = """
            {
                "model": "text-embedding-custom",
                "data": [{"index": 0, "embedding": [0.1]}],
                "usage": {"total_tokens": 5}
            }
            """.data(using: .utf8)!

        let provider = makeProvider { request in
            await capture.set(request)
            return (responseData, httpResponse())
        }

        let request = AIEmbeddingRequest(
            model: .openAIEmbedding(.custom("text-embedding-custom")),
            inputs: [.text("swift")],
            dimensions: 128
        )
        let response = try await provider.embed(request)

        let json = try await bodyJSON(capture)
        XCTAssertNil(json["dimensions"])
        XCTAssertTrue(response.warnings.contains(where: { $0.code == "unsupported_embedding_dimensions" }))
    }
}

final class OpenAIAdditionalErrorMappingTests: XCTestCase {
    func test_400MapsToInvalidRequest() async throws {
        let provider = makeProvider { _ in
            (Data("{\"error\":{\"message\":\"Bad request\"}}".utf8), httpResponse(statusCode: 400))
        }

        let request = AIRequest(model: .gpt(.gpt4o), messages: [.user("Hi")], retryPolicy: .none)

        do {
            _ = try await provider.complete(request)
            XCTFail("Expected invalidRequest")
        } catch let error as AIError {
            if case .invalidRequest(let message) = error {
                XCTAssertEqual(message, "Bad request")
            } else {
                XCTFail("Expected invalidRequest, got \(error)")
            }
        }
    }

    func test_transportFailureMapsToNetworkError() async throws {
        struct TransportFailure: Error {}

        let provider = makeProvider { _ in
            throw TransportFailure()
        }

        let request = AIRequest(model: .gpt(.gpt4o), messages: [.user("Hi")], retryPolicy: .none)

        do {
            _ = try await provider.complete(request)
            XCTFail("Expected networkError")
        } catch let error as AIError {
            if case .networkError(let context) = error {
                XCTAssertEqual(context.underlyingType, String(reflecting: TransportFailure.self))
            } else {
                XCTFail("Expected networkError, got \(error)")
            }
        }
    }

    func test_decodingFailureMapsToDecodingError() async throws {
        let provider = makeProvider { _ in
            (Data("{not-json}".utf8), httpResponse())
        }

        let request = AIRequest(model: .gpt(.gpt4o), messages: [.user("Hi")])

        do {
            _ = try await provider.complete(request)
            XCTFail("Expected decodingError")
        } catch let error as AIError {
            if case .decodingError = error {
                // expected
            } else {
                XCTFail("Expected decodingError, got \(error)")
            }
        }
    }
}

final class OpenAIStreamInterruptionTests: XCTestCase {
    func test_streamWithoutFinishSurfacesStreamInterrupted() async throws {
        let provider = makeProvider(
            streamHandler: { _ in
                AIHTTPStreamResponse(
                    response: httpResponse(),
                    body: sseStream([
                        "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}\n"
                    ])
                )
            }
        )

        let request = AIRequest(model: .gpt(.gpt4o), messages: [.user("Hi")])

        do {
            _ = try await provider.stream(request).collect()
            XCTFail("Expected streamInterrupted")
        } catch let error as AIError {
            XCTAssertEqual(error, .streamInterrupted)
        }
    }
}
