import AICore
import AIProviderAnthropic
import AITestSupport
import Foundation
import XCTest

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class AnthropicProviderTransportTests: XCTestCase {
    func test_complete_buildsMessagesRequestAndParsesResponse() async throws {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { request in
                    XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
                    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Key"), "test-key")
                    XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
                    XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")

                    let body = try XCTUnwrap(request.httpBody)
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                    let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
                    let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])

                    XCTAssertEqual(json["model"] as? String, "claude-sonnet-4-5")
                    XCTAssertEqual(json["system"] as? String, "Be brief")
                    XCTAssertEqual(json["max_tokens"] as? Int, 4_096)
                    XCTAssertEqual(json["stream"] as? Bool, false)
                    XCTAssertEqual(messages.first?["role"] as? String, "user")
                    XCTAssertEqual(content.first?["type"] as? String, "text")
                    XCTAssertEqual(content.first?["text"] as? String, "Hello")

                    return (
                        Data(
                            """
                            {
                              "id": "msg_1",
                              "model": "claude-sonnet-4-5",
                              "content": [{"type": "text", "text": "Hello back"}],
                              "stop_reason": "end_turn",
                              "stop_sequence": null,
                              "usage": {
                                "input_tokens": 3,
                                "output_tokens": 2
                              }
                            }
                            """.utf8
                        ),
                        makeHTTPResponse(statusCode: 200)
                    )
                },
                streamHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                }
            )
        )

        let response = try await provider.complete(
            AIRequest(
                model: .claude(.sonnet45),
                messages: [.user("Hello")],
                systemPrompt: "Be brief"
            )
        )

        XCTAssertEqual(response.id, "msg_1")
        XCTAssertEqual(response.model, "claude-sonnet-4-5")
        XCTAssertEqual(response.text, "Hello back")
        XCTAssertEqual(response.finishReason, .stop)
        XCTAssertEqual(response.usage, AIUsage(inputTokens: 3, outputTokens: 2))
    }

    func test_complete_retriesRateLimitedResponseBeforeSuccess() async throws {
        let attemptRecorder = AttemptRecorder()
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    let attempt = await attemptRecorder.increment()

                    if attempt == 1 {
                        return (
                            Data("{\"error\": {\"message\": \"slow down\"}}".utf8),
                            makeHTTPResponse(statusCode: 429, headers: ["retry-after-ms": "0"])
                        )
                    }

                    return (
                        Data(
                            """
                            {
                              "id": "msg_2",
                              "model": "claude-sonnet-4-5",
                              "content": [{"type": "text", "text": "Retried"}],
                              "stop_reason": "end_turn",
                              "stop_sequence": null,
                              "usage": {
                                "input_tokens": 4,
                                "output_tokens": 1
                              }
                            }
                            """.utf8
                        ),
                        makeHTTPResponse(statusCode: 200)
                    )
                },
                streamHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                }
            )
        )

        let response = try await provider.complete(
            AIRequest(
                model: .claude(.sonnet45),
                messages: [.user("Hello")],
                retryPolicy: RetryPolicy(maxRetries: 1, initialDelay: 0, backoffMultiplier: 1, maxDelay: 0)
            )
        )
        let attempts = await attemptRecorder.value

        XCTAssertEqual(response.text, "Retried")
        XCTAssertEqual(attempts, 2)
    }

    func test_complete_mapsAuthenticationFailure() async {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    (
                        Data("{\"error\": {\"message\": \"bad key\"}}".utf8),
                        makeHTTPResponse(statusCode: 401)
                    )
                },
                streamHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                }
            )
        )

        do {
            _ = try await provider.complete(
                AIRequest(model: .claude(.sonnet45), messages: [.user("Hello")])
            )
            XCTFail("Expected authentication failure")
        } catch let error as AIError {
            XCTAssertEqual(error, .authenticationFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_complete_encodesImageAndDocumentContentBlocks() async throws {
        let imageData = Data([0x01, 0x02, 0x03])
        let documentData = Data("Document body".utf8)
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { request in
                    let json = try requestJSONObject(from: request)
                    let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
                    let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
                    let imageSource = try XCTUnwrap(content[0]["source"] as? [String: Any])
                    let documentSource = try XCTUnwrap(content[1]["source"] as? [String: Any])

                    XCTAssertEqual(content[0]["type"] as? String, "image")
                    XCTAssertEqual(imageSource["type"] as? String, "base64")
                    XCTAssertEqual(imageSource["media_type"] as? String, AIImage.AIMediaType.png.rawValue)
                    XCTAssertEqual(imageSource["data"] as? String, imageData.base64EncodedString())

                    XCTAssertEqual(content[1]["type"] as? String, "document")
                    XCTAssertEqual(documentSource["type"] as? String, "base64")
                    XCTAssertEqual(documentSource["media_type"] as? String, AIDocument.AIMediaType.pdf.rawValue)
                    XCTAssertEqual(documentSource["data"] as? String, documentData.base64EncodedString())
                    XCTAssertEqual(content[2]["type"] as? String, "text")
                    XCTAssertEqual(content[2]["text"] as? String, "Describe these inputs")

                    return (makeTextResponseData(id: "msg_media", text: "done"), makeHTTPResponse(statusCode: 200))
                },
                streamHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                }
            )
        )

        let response = try await provider.complete(
            AIRequest(
                model: .claude(.sonnet45),
                messages: [
                    .user([
                        .image(AIImage(data: imageData, mediaType: .png)),
                        .document(AIDocument(data: documentData, mediaType: .pdf)),
                        .text("Describe these inputs"),
                    ])
                ]
            )
        )

        XCTAssertEqual(response.text, "done")
    }

    func test_complete_usesCustomBaseURLAndSerializesStandardMultiturnConversation() async throws {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            baseURL: URL(string: "https://example-proxy.invalid/custom")!,
            transport: MockTransport(
                dataHandler: { request in
                    XCTAssertEqual(request.url?.absoluteString, "https://example-proxy.invalid/custom/v1/messages")

                    let json = try requestJSONObject(from: request)
                    let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
                    let firstContent = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
                    let secondContent = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
                    let thirdContent = try XCTUnwrap(messages[2]["content"] as? [[String: Any]])

                    XCTAssertEqual(messages.map { $0["role"] as? String }, ["user", "assistant", "user"])
                    XCTAssertEqual(firstContent[0]["text"] as? String, "Hello")
                    XCTAssertEqual(secondContent[0]["text"] as? String, "Hi there")
                    XCTAssertEqual(thirdContent[0]["text"] as? String, "Tell me more")

                    return (
                        makeTextResponseData(id: "msg_multiturn", text: "done"),
                        makeHTTPResponse(statusCode: 200, url: request.url)
                    )
                },
                streamHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                }
            )
        )

        let response = try await provider.complete(
            AIRequest(
                model: .claude(.sonnet45),
                messages: [
                    .user("Hello"),
                    .assistant("Hi there"),
                    .user("Tell me more"),
                ]
            )
        )

        XCTAssertEqual(response.text, "done")
    }

    func test_complete_serializesToolsToolChoiceStructuredOutputAndCustomHeaders() async throws {
        let tool = AITool(
            name: "get_weather",
            description: "Get weather for a city",
            inputSchema: .object(
                properties: ["city": .string(description: "City name")],
                required: ["city"]
            )
        ) { _ in
            "sunny"
        }
        let schema = AIJSONSchema.object(
            properties: ["answer": .string()],
            required: ["answer"]
        )
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { request in
                    XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "structured-output")

                    let json = try requestJSONObject(from: request)
                    let tools = try XCTUnwrap(json["tools"] as? [[String: Any]])
                    let toolChoice = try XCTUnwrap(json["tool_choice"] as? [String: Any])
                    let outputConfig = try XCTUnwrap(json["output_config"] as? [String: Any])
                    let format = try XCTUnwrap(outputConfig["format"] as? [String: Any])
                    let inputSchema = try XCTUnwrap(tools.first?["input_schema"] as? [String: Any])
                    let outputSchema = try XCTUnwrap(format["schema"] as? [String: Any])

                    XCTAssertEqual(tools.count, 1)
                    XCTAssertEqual(tools.first?["name"] as? String, "get_weather")
                    XCTAssertEqual(tools.first?["description"] as? String, "Get weather for a city")
                    XCTAssertEqual(inputSchema["type"] as? String, "object")
                    XCTAssertEqual(toolChoice["type"] as? String, "any")
                    XCTAssertEqual(toolChoice["disable_parallel_tool_use"] as? Bool, true)
                    XCTAssertEqual(format["type"] as? String, "json_schema")
                    XCTAssertEqual(outputSchema["type"] as? String, "object")

                    return (makeTextResponseData(id: "msg_tools", text: "{}"), makeHTTPResponse(statusCode: 200))
                },
                streamHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                }
            )
        )

        let response = try await provider.complete(
            AIRequest(
                model: .claude(.sonnet45),
                messages: [.user("Use the tool")],
                tools: [tool],
                toolChoice: .required,
                allowParallelToolCalls: false,
                responseFormat: .jsonSchema(schema),
                headers: ["anthropic-beta": "structured-output"]
            )
        )

        XCTAssertEqual(response.text, "{}")
    }

    func test_complete_mergesProviderAndRequestHeadersWithRequestPrecedenceForCustomValues() async throws {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { request in
                    XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "request-beta")
                    XCTAssertEqual(request.value(forHTTPHeaderField: "x-trace-id"), "request-trace")
                    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Key"), "test-key")
                    XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
                    XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")

                    return (
                        makeTextResponseData(id: "msg_headers_merge", text: "done"),
                        makeHTTPResponse(statusCode: 200)
                    )
                },
                streamHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                }
            ),
            defaultHeaders: [
                "anthropic-beta": "provider-beta",
                "x-trace-id": "provider-trace",
                "X-Api-Key": "provider-key",
                "content-type": "text/plain",
            ]
        )

        let response = try await provider.complete(
            AIRequest(
                model: .claude(.sonnet45),
                messages: [.user("Hello")],
                headers: [
                    "anthropic-beta": "request-beta",
                    "x-trace-id": "request-trace",
                    "anthropic-version": "request-version",
                ]
            )
        )

        XCTAssertEqual(response.text, "done")
    }

    func test_complete_normalizesJSONResponseFormatToSchemaMode() async throws {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { request in
                    let json = try requestJSONObject(from: request)
                    let outputConfig = try XCTUnwrap(json["output_config"] as? [String: Any])
                    let format = try XCTUnwrap(outputConfig["format"] as? [String: Any])
                    let schema = try XCTUnwrap(format["schema"] as? [String: Any])

                    XCTAssertEqual(format["type"] as? String, "json_schema")
                    XCTAssertNotNil(schema["oneOf"])

                    return (makeTextResponseData(id: "msg_json", text: "{}"), makeHTTPResponse(statusCode: 200))
                },
                streamHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                }
            )
        )

        let response = try await provider.complete(
            AIRequest(
                model: .claude(.sonnet45),
                messages: [.user("Return JSON")],
                responseFormat: .json
            )
        )

        XCTAssertEqual(response.text, "{}")
    }

    func test_complete_adaptsToolTranscriptAndParsesToolUseResponseWithCacheUsage() async throws {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { request in
                    let json = try requestJSONObject(from: request)
                    let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
                    let assistantContent = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
                    let toolResultContent = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])

                    XCTAssertEqual(messages[0]["role"] as? String, "assistant")
                    XCTAssertEqual(assistantContent[0]["type"] as? String, "tool_use")
                    XCTAssertEqual(assistantContent[0]["id"] as? String, "tool_1")
                    XCTAssertEqual(assistantContent[0]["name"] as? String, "get_weather")
                    XCTAssertEqual(messages[1]["role"] as? String, "user")
                    XCTAssertEqual(toolResultContent[0]["type"] as? String, "tool_result")
                    XCTAssertEqual(toolResultContent[0]["tool_use_id"] as? String, "tool_1")
                    XCTAssertEqual(toolResultContent[0]["content"] as? String, "15 C")
                    XCTAssertEqual(toolResultContent[0]["is_error"] as? Bool, false)

                    return (
                        Data(
                            """
                            {
                              "id": "msg_tool_response",
                              "model": "claude-sonnet-4-5",
                              "content": [{
                                "type": "tool_use",
                                "id": "tool_2",
                                "name": "lookup_weather",
                                "input": {"city": "Rome"}
                              }],
                              "stop_reason": "tool_use",
                              "stop_sequence": null,
                              "usage": {
                                "input_tokens": 10,
                                "output_tokens": 2,
                                "cache_creation_input_tokens": 7,
                                "cache_read_input_tokens": 3
                              }
                            }
                            """.utf8
                        ),
                        makeHTTPResponse(statusCode: 200)
                    )
                },
                streamHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                }
            )
        )

        let response = try await provider.complete(
            AIRequest(
                model: .claude(.sonnet45),
                messages: [
                    .assistant([
                        .toolUse(
                            AIToolUse(
                                id: "tool_1",
                                name: "get_weather",
                                input: Data("{\"city\":\"Paris\"}".utf8)
                            )
                        )
                    ]),
                    .tool(id: "tool_1", content: "15 C"),
                ]
            )
        )

        XCTAssertEqual(response.finishReason, .toolUse)
        XCTAssertEqual(
            response.usage,
            AIUsage(
                inputTokens: 10,
                outputTokens: 2,
                inputTokenDetails: AIUsage.InputTokenDetails(cachedTokens: 3, cacheWriteTokens: 7)
            )
        )

        guard case .toolUse(let toolUse) = try XCTUnwrap(response.content.first) else {
            XCTFail("Expected tool use content")
            return
        }

        XCTAssertEqual(toolUse.id, "tool_2")
        XCTAssertEqual(toolUse.name, "lookup_weather")
        XCTAssertEqual(String(decoding: toolUse.input, as: UTF8.self), "{\"city\":\"Rome\"}")
    }

    func test_complete_prefersRetryAfterMillisecondsOverRetryAfterHeader() async {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    (
                        Data("{\"error\": {\"message\": \"slow down\"}}".utf8),
                        makeHTTPResponse(
                            statusCode: 429,
                            headers: [
                                "retry-after": "7",
                                "retry-after-ms": "500",
                            ]
                        )
                    )
                },
                streamHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                }
            )
        )

        do {
            _ = try await provider.complete(
                AIRequest(
                    model: .claude(.sonnet45),
                    messages: [.user("Hello")],
                    retryPolicy: .none
                )
            )
            XCTFail("Expected rate limit error")
        } catch let error as AIError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 0.5))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_complete_parsesHTTPDateRetryAfterHeader() async {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    (
                        Data("{\"error\": {\"message\": \"slow down\"}}".utf8),
                        makeHTTPResponse(
                            statusCode: 429,
                            headers: [
                                "retry-after": makeHTTPDateString(secondsFromNow: 120)
                            ]
                        )
                    )
                },
                streamHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                }
            )
        )

        do {
            _ = try await provider.complete(
                AIRequest(
                    model: .claude(.sonnet45),
                    messages: [.user("Hello")],
                    retryPolicy: .none
                )
            )
            XCTFail("Expected rate limit error")
        } catch let error as AIError {
            guard case .rateLimited(let retryAfter?) = error else {
                XCTFail("Expected rate limit error with retry-after, got \(error)")
                return
            }

            XCTAssertGreaterThan(retryAfter, 110)
            XCTAssertLessThan(retryAfter, 121)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_complete_mapsRemainingHTTPErrorVariants() async {
        struct Case: Sendable {
            let statusCode: Int
            let body: Data
            let expectedError: AIError
        }

        let cases = [
            Case(
                statusCode: 400,
                body: Data("{\"error\": {\"message\": \"bad request\"}}".utf8),
                expectedError: .invalidRequest("bad request")
            ),
            Case(
                statusCode: 404,
                body: Data("{\"error\": {\"message\": \"missing\"}}".utf8),
                expectedError: .modelNotFound("claude-sonnet-4-5")
            ),
            Case(
                statusCode: 409,
                body: Data("{\"error\": {\"message\": \"conflict\"}}".utf8),
                expectedError: .serverError(statusCode: 409, message: "conflict")
            ),
            Case(
                statusCode: 500,
                body: Data("{\"error\": {\"message\": \"boom\"}}".utf8),
                expectedError: .serverError(statusCode: 500, message: "boom")
            ),
        ]

        for testCase in cases {
            let provider = AnthropicProvider(
                apiKey: "test-key",
                transport: MockTransport(
                    dataHandler: { _ in
                        (testCase.body, makeHTTPResponse(statusCode: testCase.statusCode))
                    },
                    streamHandler: { _ in
                        throw AIError.unsupportedFeature("unused")
                    }
                )
            )

            do {
                _ = try await provider.complete(
                    AIRequest(model: .claude(.sonnet45), messages: [.user("Hello")], retryPolicy: .none)
                )
                XCTFail("Expected HTTP error mapping for status \(testCase.statusCode)")
            } catch let error as AIError {
                XCTAssertEqual(error, testCase.expectedError)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func test_complete_mapsTransportAndDecodingFailures() async {
        let transportProvider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    throw TransportBoom()
                },
                streamHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                }
            )
        )

        do {
            _ = try await transportProvider.complete(
                AIRequest(model: .claude(.sonnet45), messages: [.user("Hello")])
            )
            XCTFail("Expected network error")
        } catch let error as AIError {
            guard case .networkError(let context) = error else {
                XCTFail("Expected network error, got \(error)")
                return
            }

            XCTAssertEqual(context.message, "transport boom")
            XCTAssertTrue(context.underlyingType?.contains("TransportBoom") == true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let decodingProvider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    (Data("{\"id\":true}".utf8), makeHTTPResponse(statusCode: 200))
                },
                streamHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                }
            )
        )

        do {
            _ = try await decodingProvider.complete(
                AIRequest(model: .claude(.sonnet45), messages: [.user("Hello")])
            )
            XCTFail("Expected decoding error")
        } catch let error as AIError {
            guard case .decodingError = error else {
                XCTFail("Expected decoding error, got \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_complete_rejectsMalformedResponseContentBlocks() async {
        struct Case: Sendable {
            let body: Data
            let expectedMessage: String
        }

        let cases = [
            Case(
                body: Data(
                    """
                    {
                      "id": "msg_bad_text",
                      "model": "claude-sonnet-4-5",
                      "content": [{"type": "text"}],
                      "stop_reason": "end_turn",
                      "stop_sequence": null,
                      "usage": {"input_tokens": 1, "output_tokens": 1}
                    }
                    """.utf8
                ),
                expectedMessage: "Anthropic text blocks must include text"
            ),
            Case(
                body: Data(
                    """
                    {
                      "id": "msg_bad_tool_use",
                      "model": "claude-sonnet-4-5",
                      "content": [{"type": "tool_use", "id": "tool_1", "name": "lookup_weather"}],
                      "stop_reason": "tool_use",
                      "stop_sequence": null,
                      "usage": {"input_tokens": 1, "output_tokens": 1}
                    }
                    """.utf8
                ),
                expectedMessage: "Anthropic tool_use blocks must include an id, name, and input"
            ),
        ]

        for testCase in cases {
            let provider = AnthropicProvider(
                apiKey: "test-key",
                transport: MockTransport(
                    dataHandler: { _ in
                        (testCase.body, makeHTTPResponse(statusCode: 200))
                    },
                    streamHandler: { _ in
                        throw AIError.unsupportedFeature("unused")
                    }
                )
            )

            do {
                _ = try await provider.complete(
                    AIRequest(model: .claude(.sonnet45), messages: [.user("Hello")])
                )
                XCTFail("Expected decoding error")
            } catch let error as AIError {
                guard case .decodingError(let context) = error else {
                    XCTFail("Expected decoding error, got \(error)")
                    continue
                }

                XCTAssertEqual(context.message, testCase.expectedMessage)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func test_stream_parsesServerSentEvents() async throws {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                },
                streamHandler: { request in
                    let body = try XCTUnwrap(request.httpBody)
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                    XCTAssertEqual(json["stream"] as? Bool, true)

                    let sse = Data(
                        """
                        event: message_start
                        data: {"message":{"id":"msg_stream_1","model":"claude-sonnet-4-5","usage":{"input_tokens":3,"output_tokens":0}}}

                        event: content_block_start
                        data: {"index":0,"content_block":{"type":"text","text":""}}

                        event: content_block_delta
                        data: {"index":0,"delta":{"type":"text_delta","text":"Hel"}}

                        event: content_block_delta
                        data: {"index":0,"delta":{"type":"text_delta","text":"lo"}}

                        event: message_delta
                        data: {"delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":2}}

                        event: message_stop
                        data: {}

                        """.utf8
                    )
                    let splitIndex = sse.index(sse.startIndex, offsetBy: sse.count / 2)

                    return AIHTTPStreamResponse(
                        response: makeHTTPResponse(
                            statusCode: 200,
                            headers: ["content-type": "text/event-stream"]
                        ),
                        body: AsyncThrowingStream<Data, any Error>(Data.self, bufferingPolicy: .unbounded) {
                            continuation in
                            continuation.yield(Data(sse[..<splitIndex]))
                            continuation.yield(Data(sse[splitIndex...]))
                            continuation.finish()
                        }
                    )
                }
            )
        )

        let response = try await provider.stream(
            AIRequest(model: .claude(.sonnet45), messages: [.user("Hello")])
        ).collect()

        XCTAssertEqual(response.id, "msg_stream_1")
        XCTAssertEqual(response.model, "claude-sonnet-4-5")
        XCTAssertEqual(response.text, "Hello")
        XCTAssertEqual(response.finishReason, .stop)
        XCTAssertEqual(response.usage, AIUsage(inputTokens: 3, outputTokens: 2))
    }

    func test_stream_mapsHTTPTransportAndDecodingFailures() async {
        let httpErrorProvider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                },
                streamHandler: { _ in
                    AIHTTPStreamResponse(
                        response: makeHTTPResponse(statusCode: 404),
                        body: AsyncThrowingStream<Data, any Error>(Data.self, bufferingPolicy: .unbounded) {
                            continuation in
                            continuation.yield(Data("{\"error\": {\"message\": \"missing\"}}".utf8))
                            continuation.finish()
                        }
                    )
                }
            )
        )

        do {
            _ = try await httpErrorProvider.stream(
                AIRequest(model: .claude(.sonnet45), messages: [.user("Hello")], retryPolicy: .none)
            ).collect()
            XCTFail("Expected model-not-found error")
        } catch let error as AIError {
            XCTAssertEqual(error, .modelNotFound("claude-sonnet-4-5"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let transportProvider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                },
                streamHandler: { _ in
                    throw TransportBoom()
                }
            )
        )

        do {
            _ = try await transportProvider.stream(
                AIRequest(model: .claude(.sonnet45), messages: [.user("Hello")], retryPolicy: .none)
            ).collect()
            XCTFail("Expected network error")
        } catch let error as AIError {
            guard case .networkError(let context) = error else {
                XCTFail("Expected network error, got \(error)")
                return
            }

            XCTAssertEqual(context.message, "transport boom")
            XCTAssertTrue(context.underlyingType?.contains("TransportBoom") == true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let decodingProvider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                },
                streamHandler: { _ in
                    AIHTTPStreamResponse(
                        response: makeHTTPResponse(statusCode: 200),
                        body: AsyncThrowingStream<Data, any Error>(Data.self, bufferingPolicy: .unbounded) {
                            continuation in
                            continuation.yield(Data("event: message_start\ndata: {\"message\":true}\n\n".utf8))
                            continuation.finish()
                        }
                    )
                }
            )
        )

        do {
            _ = try await decodingProvider.stream(
                AIRequest(model: .claude(.sonnet45), messages: [.user("Hello")], retryPolicy: .none)
            ).collect()
            XCTFail("Expected decoding error")
        } catch let error as AIError {
            guard case .decodingError = error else {
                XCTFail("Expected decoding error, got \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_stream_mapsErrorEventsAfterStreamStart() async {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                },
                streamHandler: { _ in
                    AIHTTPStreamResponse(
                        response: makeHTTPResponse(statusCode: 200),
                        body: AsyncThrowingStream<Data, any Error>(Data.self, bufferingPolicy: .unbounded) {
                            continuation in
                            continuation.yield(
                                Data(
                                    """
                                    event: message_start
                                    data: {"message":{"id":"msg_stream_error","model":"claude-sonnet-4-5"}}

                                    event: error
                                    data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}

                                    """.utf8
                                )
                            )
                            continuation.finish()
                        }
                    )
                }
            )
        )

        do {
            _ = try await provider.stream(
                AIRequest(model: .claude(.sonnet45), messages: [.user("Hello")], retryPolicy: .none)
            ).collect()
            XCTFail("Expected stream error")
        } catch let error as AIError {
            XCTAssertEqual(error, .serverError(statusCode: 529, message: "Overloaded"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_stream_rejectsMalformedTextDeltaPayload() async {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                },
                streamHandler: { _ in
                    AIHTTPStreamResponse(
                        response: makeHTTPResponse(statusCode: 200),
                        body: AsyncThrowingStream<Data, any Error>(Data.self, bufferingPolicy: .unbounded) {
                            continuation in
                            continuation.yield(
                                Data(
                                    """
                                    event: message_start
                                    data: {"message":{"id":"msg_bad_delta","model":"claude-sonnet-4-5"}}

                                    event: content_block_delta
                                    data: {"index":0,"delta":{"type":"text_delta"}}

                                    """.utf8
                                )
                            )
                            continuation.finish()
                        }
                    )
                }
            )
        )

        do {
            _ = try await provider.stream(
                AIRequest(model: .claude(.sonnet45), messages: [.user("Hello")], retryPolicy: .none)
            ).collect()
            XCTFail("Expected decoding error")
        } catch let error as AIError {
            guard case .decodingError(let context) = error else {
                XCTFail("Expected decoding error, got \(error)")
                return
            }

            XCTAssertEqual(context.message, "Anthropic text deltas must include text")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_stream_parsesToolUseEventsIntoCollectedResponse() async throws {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                },
                streamHandler: { _ in
                    AIHTTPStreamResponse(
                        response: makeHTTPResponse(statusCode: 200),
                        body: AsyncThrowingStream<Data, any Error>(Data.self, bufferingPolicy: .unbounded) {
                            continuation in
                            continuation.yield(
                                Data(
                                    #"""
                                    event: message_start
                                    data: {"message":{"id":"msg_stream_tool","model":"claude-sonnet-4-5","usage":{"input_tokens":5}}}

                                    event: content_block_start
                                    data: {"index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"lookup_weather"}}

                                    event: content_block_delta
                                    data: {"index":0,"delta":{"type":"input_json_delta","partial_json":"{\"city\":\"Par"}}

                                    event: content_block_delta
                                    data: {"index":0,"delta":{"type":"input_json_delta","partial_json":"is\"}"}}

                                    event: message_delta
                                    data: {"delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":1}}

                                    event: message_stop
                                    data: {}

                                    """#.utf8
                                )
                            )
                            continuation.finish()
                        }
                    )
                }
            )
        )

        let response = try await provider.stream(
            AIRequest(model: .claude(.sonnet45), messages: [.user("Use a tool")])
        ).collect()

        XCTAssertEqual(response.id, "msg_stream_tool")
        XCTAssertEqual(response.finishReason, .toolUse)
        XCTAssertEqual(response.usage, AIUsage(inputTokens: 5, outputTokens: 1))

        guard case .toolUse(let toolUse) = try XCTUnwrap(response.content.first) else {
            XCTFail("Expected tool use content")
            return
        }

        XCTAssertEqual(toolUse.id, "toolu_1")
        XCTAssertEqual(toolUse.name, "lookup_weather")
        XCTAssertEqual(String(decoding: toolUse.input, as: UTF8.self), "{\"city\":\"Paris\"}")
    }

    func test_complete_stepTimeoutAbortsSlowTransport() async {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    try await Task.sleep(nanoseconds: 200_000_000)
                    return (
                        Data("{}".utf8),
                        makeHTTPResponse(statusCode: 200)
                    )
                },
                streamHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                }
            )
        )

        do {
            _ = try await provider.complete(
                AIRequest(
                    model: .claude(.sonnet45),
                    messages: [.user("Hello")],
                    timeout: AITimeout(step: 0.05)
                )
            )
            XCTFail("Expected step timeout")
        } catch let error as AIError {
            XCTAssertEqual(error, .timeout(.step))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_stream_chunkTimeoutAbortsStalledSSE() async {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                },
                streamHandler: { _ in
                    AIHTTPStreamResponse(
                        response: makeHTTPResponse(statusCode: 200),
                        body: AsyncThrowingStream<Data, any Error>(Data.self, bufferingPolicy: .unbounded) {
                            continuation in
                            let task = Task {
                                continuation.yield(
                                    Data(
                                        """
                                        event: message_start
                                        data: {"message":{"id":"msg_stream_2","model":"claude-sonnet-4-5"}}

                                        """.utf8
                                    )
                                )

                                do {
                                    try await Task.sleep(nanoseconds: 200_000_000)
                                    continuation.yield(Data("event: message_stop\ndata: {}\n\n".utf8))
                                    continuation.finish()
                                } catch is CancellationError {
                                    continuation.finish(throwing: AIError.cancelled)
                                } catch {
                                    continuation.finish(throwing: error)
                                }
                            }

                            continuation.onTermination = { _ in
                                task.cancel()
                            }
                        }
                    )
                }
            )
        )

        do {
            _ = try await provider.stream(
                AIRequest(
                    model: .claude(.sonnet45),
                    messages: [.user("Hello")],
                    timeout: AITimeout(chunk: 0.05)
                )
            ).collect()
            XCTFail("Expected chunk timeout")
        } catch let error as AIError {
            XCTAssertEqual(error, .timeout(.chunk))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_stream_withoutMessageStop_surfacesStreamInterrupted() async {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                },
                streamHandler: { _ in
                    AIHTTPStreamResponse(
                        response: makeHTTPResponse(statusCode: 200),
                        body: AsyncThrowingStream<Data, any Error>(Data.self, bufferingPolicy: .unbounded) {
                            continuation in
                            continuation.yield(
                                Data(
                                    """
                                    event: message_start
                                    data: {"message":{"id":"msg_stream_3","model":"claude-sonnet-4-5"}}

                                    event: content_block_delta
                                    data: {"index":0,"delta":{"type":"text_delta","text":"partial"}}

                                    """.utf8
                                )
                            )
                            continuation.finish()
                        }
                    )
                }
            )
        )

        do {
            _ = try await provider.stream(
                AIRequest(model: .claude(.sonnet45), messages: [.user("Hello")])
            ).collect()
            XCTFail("Expected stream interruption")
        } catch let error as AIError {
            XCTAssertEqual(error, .streamInterrupted)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_complete_surfacesStructuredOutputWarningForUnsupportedOfficialModel() async throws {
        let schema = AIJSONSchema.object(
            properties: ["answer": .string()],
            required: ["answer"]
        )
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { request in
                    let json = try requestJSONObject(from: request)
                    XCTAssertEqual(json["model"] as? String, "claude-3-haiku-20240307")
                    XCTAssertNotNil(json["output_config"])

                    return (makeTextResponseData(id: "msg_warning", text: "{}"), makeHTTPResponse(statusCode: 200))
                },
                streamHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                }
            )
        )

        let response = try await provider.complete(
            AIRequest(
                model: .claude(.custom("claude-3-haiku-20240307")),
                messages: [.user("Return JSON")],
                responseFormat: .jsonSchema(schema)
            )
        )

        let warning = try XCTUnwrap(response.warnings.first)
        XCTAssertEqual(response.warnings.count, 1)
        XCTAssertEqual(warning.code, "unsupported_model_structured_output")
        XCTAssertEqual(warning.parameter, "responseFormat")
        XCTAssertTrue(warning.message.contains("output_config.format"))
    }

    func test_stream_collect_surfacesRequestWarnings() async throws {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                },
                streamHandler: { request in
                    let json = try requestJSONObject(from: request)
                    XCTAssertEqual(json["model"] as? String, "claude-3-haiku-20240307")
                    XCTAssertNotNil(json["output_config"])

                    return AIHTTPStreamResponse(
                        response: makeHTTPResponse(statusCode: 200),
                        body: AsyncThrowingStream<Data, any Error>(Data.self, bufferingPolicy: .unbounded) {
                            continuation in
                            continuation.yield(
                                Data(
                                    """
                                    event: message_start
                                    data: {"message":{"id":"msg_stream_warning","model":"claude-3-haiku-20240307","usage":{"input_tokens":2}}}

                                    event: content_block_delta
                                    data: {"index":0,"delta":{"type":"text_delta","text":"{}"}}

                                    event: message_delta
                                    data: {"delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":1}}

                                    event: message_stop
                                    data: {}

                                    """.utf8
                                )
                            )
                            continuation.finish()
                        }
                    )
                }
            )
        )

        let response = try await provider.stream(
            AIRequest(
                model: .claude(.custom("claude-3-haiku-20240307")),
                messages: [.user("Return JSON")],
                responseFormat: .json
            )
        ).collect()

        XCTAssertEqual(response.text, "{}")
        XCTAssertEqual(response.warnings.count, 1)
        XCTAssertEqual(response.warnings.first?.code, "unsupported_model_structured_output")
    }

    func test_complete_warnsForCustomDeploymentStructuredOutputCompatibility() async throws {
        let schema = AIJSONSchema.object(
            properties: ["answer": .string()],
            required: ["answer"]
        )
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { request in
                    let json = try requestJSONObject(from: request)
                    XCTAssertEqual(json["model"] as? String, "bedrock/anthropic-sonnet")
                    XCTAssertNotNil(json["output_config"])

                    return (
                        makeTextResponseData(id: "msg_custom_model_warning", text: "{}"),
                        makeHTTPResponse(statusCode: 200)
                    )
                },
                streamHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                }
            )
        )

        let response = try await provider.complete(
            AIRequest(
                model: .claude(.custom("bedrock/anthropic-sonnet")),
                messages: [.user("Return JSON")],
                responseFormat: .jsonSchema(schema)
            )
        )

        XCTAssertEqual(response.warnings.count, 1)
        XCTAssertEqual(response.warnings.first?.code, "custom_model_structured_output_unverified")
        XCTAssertEqual(response.warnings.first?.parameter, "responseFormat")
    }

    func test_stream_collect_surfacesCustomDeploymentWarnings() async throws {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                },
                streamHandler: { request in
                    let json = try requestJSONObject(from: request)
                    XCTAssertEqual(json["model"] as? String, "bedrock/anthropic-sonnet")
                    XCTAssertNotNil(json["output_config"])

                    return AIHTTPStreamResponse(
                        response: makeHTTPResponse(statusCode: 200),
                        body: AsyncThrowingStream<Data, any Error>(Data.self, bufferingPolicy: .unbounded) {
                            continuation in
                            continuation.yield(
                                Data(
                                    """
                                    event: message_start
                                    data: {"message":{"id":"msg_stream_custom_warning","model":"bedrock/anthropic-sonnet","usage":{"input_tokens":2}}}

                                    event: content_block_delta
                                    data: {"index":0,"delta":{"type":"text_delta","text":"{}"}}

                                    event: message_delta
                                    data: {"delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":1}}

                                    event: message_stop
                                    data: {}

                                    """.utf8
                                )
                            )
                            continuation.finish()
                        }
                    )
                }
            )
        )

        let response = try await provider.stream(
            AIRequest(
                model: .claude(.custom("bedrock/anthropic-sonnet")),
                messages: [.user("Return JSON")],
                responseFormat: .json
            )
        ).collect()

        XCTAssertEqual(response.text, "{}")
        XCTAssertEqual(response.warnings.count, 1)
        XCTAssertEqual(response.warnings.first?.code, "custom_model_structured_output_unverified")
    }

    func test_complete_rejectsToolSettingsWithoutTools() async {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    XCTFail("Transport should not be called")
                    return (Data(), makeHTTPResponse(statusCode: 200))
                },
                streamHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                }
            )
        )

        do {
            _ = try await provider.complete(
                AIRequest(
                    model: .claude(.sonnet45),
                    messages: [.user("Hello")],
                    toolChoice: .required
                )
            )
            XCTFail("Expected invalid request")
        } catch let error as AIError {
            XCTAssertEqual(error, .invalidRequest("Anthropic tool choice requires at least one tool definition"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_complete_warnsWhenParallelToolSettingIsIgnoredByToolChoiceNone() async throws {
        let tool = AITool(
            name: "get_weather",
            description: "Get weather for a city",
            inputSchema: .object(
                properties: ["city": .string()],
                required: ["city"]
            )
        ) { _ in
            "sunny"
        }
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { request in
                    let json = try requestJSONObject(from: request)
                    let toolChoice = try XCTUnwrap(json["tool_choice"] as? [String: Any])

                    XCTAssertEqual(toolChoice["type"] as? String, "none")
                    XCTAssertNil(toolChoice["disable_parallel_tool_use"])

                    return (
                        makeTextResponseData(id: "msg_parallel_warning", text: "done"),
                        makeHTTPResponse(statusCode: 200)
                    )
                },
                streamHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                }
            )
        )

        let response = try await provider.complete(
            AIRequest(
                model: .claude(.sonnet45),
                messages: [.user("Ignore tools")],
                tools: [tool],
                toolChoice: AIToolChoice.none,
                allowParallelToolCalls: false
            )
        )

        XCTAssertEqual(response.text, "done")
        XCTAssertEqual(response.warnings.count, 1)
        XCTAssertEqual(response.warnings.first?.code, "ignored_parallel_tool_setting")
        XCTAssertEqual(response.warnings.first?.parameter, "allowParallelToolCalls")
    }

    func test_complete_mapsPauseTurnFinishReason() async throws {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    (
                        Data(
                            """
                            {
                              "id": "msg_pause_turn",
                              "model": "claude-sonnet-4-5",
                              "content": [{"type": "text", "text": "Need another turn"}],
                              "stop_reason": "pause_turn",
                              "stop_sequence": null,
                              "usage": {
                                "input_tokens": 5,
                                "output_tokens": 2
                              }
                            }
                            """.utf8
                        ),
                        makeHTTPResponse(statusCode: 200)
                    )
                },
                streamHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                }
            )
        )

        let response = try await provider.complete(
            AIRequest(model: .claude(.sonnet45), messages: [.user("Continue")])
        )

        XCTAssertEqual(response.finishReason, .pauseTurn)
    }

    func test_stream_mapsRefusalFinishReason() async throws {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                },
                streamHandler: { _ in
                    AIHTTPStreamResponse(
                        response: makeHTTPResponse(statusCode: 200),
                        body: AsyncThrowingStream<Data, any Error>(Data.self, bufferingPolicy: .unbounded) {
                            continuation in
                            continuation.yield(
                                Data(
                                    """
                                    event: message_start
                                    data: {"message":{"id":"msg_refusal","model":"claude-sonnet-4-5","usage":{"input_tokens":1}}}

                                    event: message_delta
                                    data: {"delta":{"stop_reason":"refusal","stop_sequence":null},"usage":{"output_tokens":0}}

                                    event: message_stop
                                    data: {}

                                    """.utf8
                                )
                            )
                            continuation.finish()
                        }
                    )
                }
            )
        )

        let response = try await provider.stream(
            AIRequest(model: .claude(.sonnet45), messages: [.user("Refuse")])
        ).collect()

        XCTAssertEqual(response.finishReason, .refusal)
    }

    func test_stream_mapsCacheUsageIntoInputTokenDetails() async throws {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                },
                streamHandler: { _ in
                    AIHTTPStreamResponse(
                        response: makeHTTPResponse(statusCode: 200),
                        body: AsyncThrowingStream<Data, any Error>(Data.self, bufferingPolicy: .unbounded) {
                            continuation in
                            continuation.yield(
                                Data(
                                    """
                                    event: message_start
                                    data: {"message":{"id":"msg_stream_cache","model":"claude-sonnet-4-5","usage":{"input_tokens":9,"cache_creation_input_tokens":6,"cache_read_input_tokens":3}}}

                                    event: message_delta
                                    data: {"delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":2}}

                                    event: message_stop
                                    data: {}

                                    """.utf8
                                )
                            )
                            continuation.finish()
                        }
                    )
                }
            )
        )

        let response = try await provider.stream(
            AIRequest(model: .claude(.sonnet45), messages: [.user("Hello")])
        ).collect()

        XCTAssertEqual(
            response.usage,
            AIUsage(
                inputTokens: 9,
                outputTokens: 2,
                inputTokenDetails: AIUsage.InputTokenDetails(cachedTokens: 3, cacheWriteTokens: 6)
            )
        )
    }

    func test_stream_cancellationStopsTransportWithoutExtraEvents() async {
        let firstEventExpectation = expectation(description: "First event received")
        let producerCancelledExpectation = expectation(description: "Producer cancelled")
        let terminationExpectation = expectation(description: "Transport terminated")
        let observation = StreamObservation()

        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                },
                streamHandler: { _ in
                    AIHTTPStreamResponse(
                        response: makeHTTPResponse(statusCode: 200),
                        body: AsyncThrowingStream<Data, any Error>(Data.self, bufferingPolicy: .unbounded) {
                            continuation in
                            let task = Task {
                                continuation.yield(
                                    Data(
                                        "event: message_start\ndata: {\"message\":{\"id\":\"msg_cancel\",\"model\":\"claude-sonnet-4-5\"}}\n\n"
                                            .utf8
                                    )
                                )

                                do {
                                    try await Task.sleep(nanoseconds: 200_000_000)
                                    continuation.yield(
                                        Data(
                                            ("event: content_block_delta\ndata: {\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"too late\"}}\n\n"
                                                + "event: message_delta\ndata: {\"delta\":{\"stop_reason\":\"end_turn\",\"stop_sequence\":null},\"usage\":{\"output_tokens\":1}}\n\n"
                                                + "event: message_stop\ndata: {}\n\n").utf8
                                        )
                                    )
                                    continuation.finish()
                                } catch is CancellationError {
                                    producerCancelledExpectation.fulfill()
                                    continuation.finish(throwing: AIError.cancelled)
                                } catch {
                                    continuation.finish(throwing: error)
                                }
                            }

                            continuation.onTermination = { _ in
                                task.cancel()
                                terminationExpectation.fulfill()
                            }
                        }
                    )
                }
            )
        )

        let stream = provider.stream(
            AIRequest(model: .claude(.sonnet45), messages: [.user("Hello")])
        )
        let consumerTask = Task {
            do {
                for try await event in stream {
                    await observation.record(event)
                    firstEventExpectation.fulfill()
                }
            } catch let error as AIError {
                await observation.record(error: error)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        await fulfillment(of: [firstEventExpectation], timeout: 1.0)
        consumerTask.cancel()
        _ = await consumerTask.result
        await fulfillment(of: [producerCancelledExpectation, terminationExpectation], timeout: 1.0)

        let recordedEvents = await observation.events

        XCTAssertEqual(recordedEvents, [.start(id: "msg_cancel", model: "claude-sonnet-4-5")])
    }

    func test_embed_usesDefaultUnsupportedFeaturePathWithoutTransportCalls() async {
        let recorder = TransportCallRecorder()
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    await recorder.recordDataCall()
                    return (Data(), makeHTTPResponse(statusCode: 200))
                },
                streamHandler: { _ in
                    await recorder.recordStreamCall()
                    return AIHTTPStreamResponse(
                        response: makeHTTPResponse(statusCode: 200),
                        body: AsyncThrowingStream<Data, any Error>(Data.self, bufferingPolicy: .unbounded) {
                            continuation in
                            continuation.finish()
                        }
                    )
                }
            )
        )

        do {
            _ = try await provider.embed(
                AIEmbeddingRequest(model: .claude(.sonnet45), inputs: [.text("hello")])
            )
            XCTFail("Expected unsupported embeddings error")
        } catch let error as AIError {
            XCTAssertEqual(error, .unsupportedFeature("Embeddings are not supported by this provider"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let dataCalls = await recorder.dataCalls
        let streamCalls = await recorder.streamCalls

        XCTAssertEqual(dataCalls, 0)
        XCTAssertEqual(streamCalls, 0)
    }

    func test_providerPublishesCapabilitiesAndAvailableModels() {
        let provider = AnthropicProvider(
            apiKey: "test-key",
            transport: MockTransport(
                dataHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                },
                streamHandler: { _ in
                    throw AIError.unsupportedFeature("unused")
                }
            )
        )

        XCTAssertEqual(
            provider.availableModels,
            [
                .claude(.haiku45),
                .claude(.sonnet45),
                .claude(.sonnet46),
                .claude(.opus46),
            ]
        )
        XCTAssertEqual(
            provider.capabilities,
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
        )
    }
}

private actor AttemptRecorder {
    private(set) var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}

private actor StreamObservation {
    private(set) var events: [AIStreamEvent] = []
    private(set) var error: AIError?

    func record(_ event: AIStreamEvent) {
        events.append(event)
    }

    func record(error: AIError) {
        self.error = error
    }
}

private actor TransportCallRecorder {
    private(set) var dataCalls = 0
    private(set) var streamCalls = 0

    func recordDataCall() {
        dataCalls += 1
    }

    func recordStreamCall() {
        streamCalls += 1
    }
}

private struct TransportBoom: Error, Sendable, CustomStringConvertible {
    var description: String { "transport boom" }
}

private func makeHTTPResponse(
    statusCode: Int,
    headers: [String: String] = [:],
    url: URL? = nil
) -> HTTPURLResponse {
    HTTPURLResponse(
        url: url ?? URL(string: "https://api.anthropic.com/v1/messages")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: headers
    )!
}

private func makeTextResponseData(id: String, text: String) -> Data {
    Data(
        """
        {
          "id": "\(id)",
          "model": "claude-sonnet-4-5",
          "content": [{"type": "text", "text": "\(text)"}],
          "stop_reason": "end_turn",
          "stop_sequence": null,
          "usage": {
            "input_tokens": 1,
            "output_tokens": 1
          }
        }
        """.utf8
    )
}

private func makeHTTPDateString(secondsFromNow: TimeInterval) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'"
    return formatter.string(from: Date(timeIntervalSinceNow: secondsFromNow))
}

private func requestJSONObject(from request: URLRequest) throws -> [String: Any] {
    let body = try XCTUnwrap(request.httpBody)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
}
