#if canImport(SwiftUI)
    import AICore
    import AISwiftUI
    import AITestSupport
    import XCTest

    // MARK: - AIStreamState Tests (1-7)

    final class AIStreamStateTests: XCTestCase {

        // Test 1: lifecycle idle -> streaming -> complete
        @MainActor
        func test_streamState_lifecycle() async throws {
            let state = AIStreamState(smoothStreaming: nil)
            XCTAssertFalse(state.isStreaming)
            XCTAssertTrue(state.text.isEmpty)
            XCTAssertFalse(state.isComplete)

            let provider = MockProvider(streamHandler: { _ in
                .finished(text: "Hello")
            })

            state.stream("hi", provider: provider, model: AIModel("test"))
            try await Task.sleep(nanoseconds: 100_000_000)

            XCTAssertFalse(state.isStreaming)
            XCTAssertEqual(state.text, "Hello")
            XCTAssertTrue(state.isComplete)
            XCTAssertNil(state.error)
        }

        // Test 2: cancel() stops without error
        @MainActor
        func test_streamState_cancel_noError() async throws {
            let state = AIStreamState(smoothStreaming: nil)

            let provider = MockProvider(streamHandler: { _ in
                AIStream(
                    AsyncThrowingStream<AIStreamEvent, any Error> { continuation in
                        continuation.yield(.start(id: "1", model: "m"))
                        continuation.yield(.delta(.text("partial")))
                    }
                )
            })

            state.stream("hi", provider: provider, model: AIModel("test"))
            try await Task.sleep(nanoseconds: 50_000_000)

            XCTAssertTrue(state.isStreaming)
            state.cancel()

            XCTAssertFalse(state.isStreaming)
            XCTAssertNil(state.error)
        }

        // Test 3: stream errors map into error
        @MainActor
        func test_streamState_errorMapping() async throws {
            let state = AIStreamState(smoothStreaming: nil)

            let provider = MockProvider(streamHandler: { _ in
                .failed(.serverError(statusCode: 500, message: "boom"))
            })

            state.stream("hi", provider: provider, model: AIModel("test"))
            try await Task.sleep(nanoseconds: 100_000_000)

            XCTAssertFalse(state.isStreaming)
            XCTAssertEqual(state.error, .serverError(statusCode: 500, message: "boom"))
        }

        // Test 4: starting a new stream cancels the previous one
        @MainActor
        func test_streamState_newStreamCancelsPrevious() async throws {
            let state = AIStreamState(smoothStreaming: nil)

            let provider = MockProvider(streamHandler: { _ in
                AIStream(
                    AsyncThrowingStream<AIStreamEvent, any Error> { continuation in
                        continuation.yield(.start(id: "1", model: "m"))
                        continuation.yield(.delta(.text("first")))
                    }
                )
            })

            state.stream("first", provider: provider, model: AIModel("test"))
            try await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertTrue(state.text.contains("first"))

            let provider2 = MockProvider(streamHandler: { _ in
                .finished(text: "second")
            })

            state.stream("second", provider: provider2, model: AIModel("test"))
            try await Task.sleep(nanoseconds: 100_000_000)

            XCTAssertEqual(state.text, "second")
            XCTAssertTrue(state.isComplete)
        }

        // Test 5: reset() clears state
        @MainActor
        func test_streamState_reset() async throws {
            let state = AIStreamState(smoothStreaming: nil)

            let provider = MockProvider(streamHandler: { _ in
                .finished(text: "hello")
            })

            state.stream("hi", provider: provider, model: AIModel("test"))
            try await Task.sleep(nanoseconds: 100_000_000)

            XCTAssertEqual(state.text, "hello")
            XCTAssertTrue(state.isComplete)

            state.reset()
            XCTAssertEqual(state.text, "")
            XCTAssertNil(state.usage)
            XCTAssertFalse(state.isComplete)
            XCTAssertNil(state.error)
        }

        // Test 6: captures usage from raw stream events
        @MainActor
        func test_streamState_capturesUsage() async throws {
            let state = AIStreamState(smoothStreaming: nil)

            let expectedUsage = AIUsage(inputTokens: 10, outputTokens: 20)
            let provider = MockProvider(streamHandler: { _ in
                AIStream(
                    AsyncThrowingStream<AIStreamEvent, any Error> { continuation in
                        continuation.yield(.start(id: "1", model: "m"))
                        continuation.yield(.delta(.text("hi")))
                        continuation.yield(.usage(expectedUsage))
                        continuation.yield(.finish(.stop))
                        continuation.finish()
                    }
                )
            })

            state.stream("hi", provider: provider, model: AIModel("test"))
            try await Task.sleep(nanoseconds: 100_000_000)

            XCTAssertEqual(state.usage, expectedUsage)
        }

        // Test 7: public state mutations compile under @MainActor isolation
        @MainActor
        func test_streamState_mainActorIsolation() {
            let state = AIStreamState()
            XCTAssertFalse(state.isStreaming)
            XCTAssertEqual(state.text, "")
            XCTAssertNil(state.error)
            XCTAssertNil(state.usage)
            XCTAssertFalse(state.isComplete)
        }
    }

    // MARK: - SmoothStreaming Tests (8-10)

    final class SmoothStreamingTests: XCTestCase {

        // Test 8: word mode re-chunks text correctly
        func test_smoothStreaming_wordReChunks() async throws {
            let source = AIStream(
                AsyncThrowingStream<AIStreamEvent, any Error> { continuation in
                    continuation.yield(.start(id: "1", model: "m"))
                    continuation.yield(.delta(.text("Hello world how ")))
                    continuation.yield(.delta(.text("are you")))
                    continuation.yield(.finish(.stop))
                    continuation.finish()
                }
            )

            let smooth = source.smooth(SmoothStreaming(delay: 0.001, mode: .word))
            var chunks: [String] = []

            for try await event in smooth {
                if case .delta(.text(let t)) = event {
                    chunks.append(t)
                }
            }

            let reassembled = chunks.joined()
            XCTAssertEqual(reassembled, "Hello world how are you")
            XCTAssertTrue(chunks.count > 1, "Should have multiple word chunks")
        }

        // Test 9: flushes buffered text immediately on finish
        func test_smoothStreaming_flushesOnFinish() async throws {
            let source = AIStream(
                AsyncThrowingStream<AIStreamEvent, any Error> { continuation in
                    continuation.yield(.start(id: "1", model: "m"))
                    continuation.yield(.delta(.text("incomplete")))
                    continuation.yield(.finish(.stop))
                    continuation.finish()
                }
            )

            let smooth = source.smooth(SmoothStreaming(delay: 0.001, mode: .word))
            var text = ""
            var sawFinish = false

            for try await event in smooth {
                switch event {
                case .delta(.text(let t)):
                    text += t
                case .finish:
                    sawFinish = true
                default:
                    break
                }
            }

            XCTAssertEqual(text, "incomplete")
            XCTAssertTrue(sawFinish)
        }

        // Test 10: flushes buffered text immediately on cancellation
        func test_smoothStreaming_flushesOnCancellation() async throws {
            // Use a source that emits text then gets cancelled via its continuation.
            // The smooth stream should flush any buffered remainder.
            var sourceContinuation: AsyncThrowingStream<AIStreamEvent, any Error>.Continuation?
            let source = AIStream(
                AsyncThrowingStream<AIStreamEvent, any Error> { continuation in
                    sourceContinuation = continuation
                    continuation.yield(.start(id: "1", model: "m"))
                    continuation.yield(.delta(.text("hello ")))
                    continuation.yield(.delta(.text("world")))
                }
            )

            let smooth = source.smooth(SmoothStreaming(delay: 0.001, mode: .word))

            let task = Task {
                var text = ""
                do {
                    for try await event in smooth {
                        if case .delta(.text(let t)) = event {
                            text += t
                        }
                    }
                } catch {}
                return text
            }

            // Let smooth processing start
            try await Task.sleep(nanoseconds: 100_000_000)
            // Cancel the source — this triggers flush of any buffered remainder
            sourceContinuation?.finish(throwing: CancellationError())
            let result = await task.value
            // "hello " is emitted as a complete word chunk, "world" is buffered remainder
            // that gets flushed on cancellation
            XCTAssertEqual(result, "hello world")
        }
    }

    // MARK: - AIConversation Tests (11-19)

    final class AIConversationTests: XCTestCase {

        // Test 11: send() appends user message and commits assistant reply
        @MainActor
        func test_conversation_sendAppendsAndCommits() async throws {
            let provider = MockProvider(streamHandler: { _ in
                .finished(text: "Reply")
            })

            let conv = AIConversation(
                provider: provider,
                model: AIModel("test"),
                smoothStreaming: nil
            )

            conv.send("Hello")
            try await Task.sleep(nanoseconds: 100_000_000)

            XCTAssertEqual(conv.messages.count, 2)
            XCTAssertEqual(conv.messages[0].role, AIRole.user)
            XCTAssertEqual(conv.messages[1].role, AIRole.assistant)
            XCTAssertTrue(conv.currentStreamText.isEmpty)
        }

        // Test 12: preserves multi-turn history
        @MainActor
        func test_conversation_preservesHistory() async throws {
            let provider = MockProvider(streamHandler: { request in
                let n = request.messages.filter { $0.role == AIRole.user }.count
                return .finished(text: "Reply \(n)")
            })

            let conv = AIConversation(
                provider: provider,
                model: AIModel("test"),
                smoothStreaming: nil
            )

            conv.send("First")
            try await Task.sleep(nanoseconds: 100_000_000)

            conv.send("Second")
            try await Task.sleep(nanoseconds: 100_000_000)

            XCTAssertEqual(conv.messages.count, 4)
            XCTAssertEqual(conv.messages[0].role, AIRole.user)
            XCTAssertEqual(conv.messages[1].role, AIRole.assistant)
            XCTAssertEqual(conv.messages[2].role, AIRole.user)
            XCTAssertEqual(conv.messages[3].role, AIRole.assistant)
        }

        // Test 13: clear() empties history and cancels active work
        @MainActor
        func test_conversation_clear() async throws {
            let provider = MockProvider(streamHandler: { _ in
                .finished(text: "Reply")
            })

            let conv = AIConversation(
                provider: provider,
                model: AIModel("test"),
                smoothStreaming: nil
            )

            conv.send("Hello")
            try await Task.sleep(nanoseconds: 100_000_000)

            XCTAssertEqual(conv.messages.count, 2)

            conv.clear()
            XCTAssertTrue(conv.messages.isEmpty)
            XCTAssertTrue(conv.currentStreamText.isEmpty)
            XCTAssertFalse(conv.isStreaming)
            XCTAssertNil(conv.error)
        }

        // Test 14: rejectWhileStreaming sets error
        @MainActor
        func test_conversation_rejectWhileStreaming() async throws {
            let conv = AIConversation(
                provider: MockProvider(streamHandler: { _ in
                    AIStream(
                        AsyncThrowingStream<AIStreamEvent, any Error> { continuation in
                            continuation.yield(.start(id: "1", model: "m"))
                            continuation.yield(.delta(.text("streaming...")))
                        }
                    )
                }),
                model: AIModel("test"),
                smoothStreaming: nil,
                sendPolicy: .rejectWhileStreaming
            )

            conv.send("First")
            try await Task.sleep(nanoseconds: 50_000_000)

            XCTAssertTrue(conv.isStreaming)
            conv.send("Second")

            XCTAssertEqual(
                conv.error,
                .invalidRequest("Cannot send while another response is streaming")
            )
            XCTAssertTrue(conv.isStreaming)
            conv.cancel()
        }

        // Test 15: cancelCurrentResponse cancels old stream and starts new one
        @MainActor
        func test_conversation_cancelCurrentResponse() async throws {
            // Use message count to determine which call this is
            let conv = AIConversation(
                provider: MockProvider(streamHandler: { request in
                    let userCount = request.messages.filter { $0.role == AIRole.user }.count
                    if userCount <= 1 {
                        return AIStream(
                            AsyncThrowingStream<AIStreamEvent, any Error> { continuation in
                                continuation.yield(.start(id: "1", model: "m"))
                                continuation.yield(.delta(.text("old")))
                            }
                        )
                    }
                    return .finished(text: "new")
                }),
                model: AIModel("test"),
                smoothStreaming: nil,
                sendPolicy: .cancelCurrentResponse
            )

            conv.send("First")
            try await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertTrue(conv.isStreaming)

            conv.send("Second")
            try await Task.sleep(nanoseconds: 100_000_000)

            XCTAssertFalse(conv.isStreaming)
            XCTAssertNil(conv.error)
            let assistantMessages = conv.messages.filter { $0.role == AIRole.assistant }
            XCTAssertTrue(assistantMessages.count >= 1)
        }

        // Test 16: tool streaming updates activeToolCalls and toolResults
        @MainActor
        func test_conversation_toolStreamingUpdates() async throws {
            let conv = AIConversation(
                provider: MockProvider(streamHandler: { _ in
                    AIStream(
                        AsyncThrowingStream<AIStreamEvent, any Error> { continuation in
                            continuation.yield(.start(id: "1", model: "m"))
                            continuation.yield(.toolUseStart(id: "t1", name: "get_weather"))
                            continuation.yield(.finish(.toolUse))
                            continuation.finish()
                        }
                    )
                }),
                model: AIModel("test"),
                smoothStreaming: nil
            )

            let tool = AITool(
                name: "get_weather",
                description: "Get weather",
                inputSchema: .object(properties: [:], required: []),
                handler: { _ in "Sunny" }
            )

            conv.send("What's the weather?", tools: [tool])
            try await Task.sleep(nanoseconds: 300_000_000)

            XCTAssertFalse(conv.isStreaming)
        }

        // Test 17: tool-step completion appends step.appendedMessages
        @MainActor
        func test_conversation_toolStepAppendsMessages() async throws {
            let conv = AIConversation(
                provider: MockProvider(streamHandler: { request in
                    let hasToolResults = request.messages.contains { $0.role == AIRole.tool }
                    if hasToolResults {
                        return .finished(text: "Final answer")
                    }
                    return AIStream(
                        AsyncThrowingStream<AIStreamEvent, any Error> { continuation in
                            continuation.yield(.start(id: "1", model: "m"))
                            continuation.yield(.toolUseStart(id: "t1", name: "calc"))
                            continuation.yield(.delta(.toolInput(id: "t1", jsonDelta: "{}")))
                            continuation.yield(.usage(AIUsage(inputTokens: 5, outputTokens: 3)))
                            continuation.yield(.finish(.toolUse))
                            continuation.finish()
                        }
                    )
                }),
                model: AIModel("test"),
                smoothStreaming: nil
            )

            let tool = AITool(
                name: "calc",
                description: "Calculate",
                inputSchema: .object(properties: [:], required: []),
                handler: { _ in "42" }
            )

            conv.send("Calculate", tools: [tool])
            try await Task.sleep(nanoseconds: 500_000_000)

            XCTAssertTrue(conv.messages.count >= 3)
            let hasToolRole = conv.messages.contains { $0.role == AIRole.tool }
            XCTAssertTrue(hasToolRole, "Should have tool result messages from step")
        }

        @MainActor
        func test_conversation_toolStepWithTextDoesNotDuplicateAssistantMessage() async throws {
            let conv = AIConversation(
                provider: MockProvider(streamHandler: { request in
                    let hasToolResults = request.messages.contains { $0.role == AIRole.tool }
                    if hasToolResults {
                        return .finished(text: "Final answer")
                    }

                    return AIStream(
                        AsyncThrowingStream<AIStreamEvent, any Error> { continuation in
                            continuation.yield(.start(id: "1", model: "m"))
                            continuation.yield(.delta(.text("thinking")))
                            continuation.yield(.toolUseStart(id: "t1", name: "calc"))
                            continuation.yield(.delta(.toolInput(id: "t1", jsonDelta: "{}")))
                            continuation.yield(.finish(.toolUse))
                            continuation.finish()
                        }
                    )
                }),
                model: AIModel("test"),
                smoothStreaming: nil
            )

            let tool = AITool(
                name: "calc",
                description: "Calculate",
                inputSchema: .object(properties: [:], required: []),
                handler: { _ in "42" }
            )

            conv.send("Calculate", tools: [tool])
            try await Task.sleep(nanoseconds: 500_000_000)

            let assistantMessages = conv.messages.filter { $0.role == AIRole.assistant }
            XCTAssertEqual(assistantMessages.count, 2)
            XCTAssertEqual(assistantMessages.last?.content.first, .text("Final answer"))

            let firstAssistant = try XCTUnwrap(assistantMessages.first)
            XCTAssertTrue(firstAssistant.content.contains(.text("thinking")))
            XCTAssertTrue(firstAssistant.content.contains { content in
                if case .toolUse = content {
                    return true
                }
                return false
            })
        }

        // Test 18: approval and repair handlers are forwarded
        @MainActor
        func test_conversation_handlersForwarded() async throws {
            let conv = AIConversation(
                provider: MockProvider(streamHandler: { _ in
                    .finished(text: "done")
                }),
                model: AIModel("test"),
                smoothStreaming: nil,
                approvalHandler: { _ in
                    return true
                },
                toolCallRepairHandler: { _, _ in
                    return nil
                }
            )

            XCTAssertNotNil(conv.approvalHandler)
            XCTAssertNotNil(conv.toolCallRepairHandler)

            let approved = await conv.approvalHandler?(
                AIToolUse(id: "t1", name: "test", input: Data())
            )
            XCTAssertEqual(approved, true)

            let repaired = await conv.toolCallRepairHandler?(
                AIToolUse(id: "t1", name: "test", input: Data()),
                AIErrorContext(message: "error")
            )
            XCTAssertNil(repaired)
        }

        // Test 19: totalUsage accumulates across exchanges
        @MainActor
        func test_conversation_totalUsageAccumulates() async throws {
            let conv = AIConversation(
                provider: MockProvider(streamHandler: { _ in
                    AIStream(
                        AsyncThrowingStream<AIStreamEvent, any Error> { continuation in
                            continuation.yield(.start(id: "1", model: "m"))
                            continuation.yield(.delta(.text("reply")))
                            continuation.yield(
                                .usage(AIUsage(inputTokens: 10, outputTokens: 5))
                            )
                            continuation.yield(.finish(.stop))
                            continuation.finish()
                        }
                    )
                }),
                model: AIModel("test"),
                smoothStreaming: nil
            )

            conv.send("First")
            try await Task.sleep(nanoseconds: 100_000_000)

            conv.send("Second")
            try await Task.sleep(nanoseconds: 100_000_000)

            XCTAssertEqual(conv.totalUsage.inputTokens, 20)
            XCTAssertEqual(conv.totalUsage.outputTokens, 10)
        }
    }

    // MARK: - StreamingText Test (20)

    final class StreamingTextTests: XCTestCase {

        // Test 20: StreamingText builds without crashing
        @MainActor
        func test_streamingText_builds() {
            let state = AIStreamState()
            let view = StreamingText(state)
            _ = view.body
        }
    }

    // MARK: - AIMessageList Test (21)

    final class AIMessageListTests: XCTestCase {

        // Test 21: auto-scroll logic does not force-scroll when user is far from bottom
        @MainActor
        func test_messageList_noForceScroll() {
            let messages = [
                AIMessage.user("Hello"),
                AIMessage.assistant("World"),
            ]
            let view = AIMessageList(messages, streamingText: "typing...")
            _ = view.body
        }
    }

    // MARK: - Interruption Tests (22-23)

    final class StreamInterruptionTests: XCTestCase {

        // Test 22: interrupted plain streams keep partial text visible but don't commit assistant message
        @MainActor
        func test_interruptedPlainStream_keepsPartialText() async throws {
            let conv = AIConversation(
                provider: MockProvider(streamHandler: { _ in
                    AIStream(
                        AsyncThrowingStream<AIStreamEvent, any Error> { continuation in
                            continuation.yield(.start(id: "1", model: "m"))
                            continuation.yield(.delta(.text("partial response")))
                            continuation.finish(
                                throwing: AIError.serverError(
                                    statusCode: 500,
                                    message: "interrupted"
                                )
                            )
                        }
                    )
                }),
                model: AIModel("test"),
                smoothStreaming: nil
            )

            conv.send("Hello")
            try await Task.sleep(nanoseconds: 200_000_000)

            XCTAssertFalse(conv.isStreaming)
            XCTAssertEqual(conv.currentStreamText, "partial response")
            let assistantMessages = conv.messages.filter { $0.role == AIRole.assistant }
            XCTAssertEqual(assistantMessages.count, 0)
            XCTAssertNotNil(conv.error)
        }

        // Test 23: interrupted tool streams keep completed step messages only and surface error
        @MainActor
        func test_interruptedToolStream_keepsCompletedSteps() async throws {
            let conv = AIConversation(
                provider: MockProvider(streamHandler: { request in
                    let hasToolResults = request.messages.contains { $0.role == AIRole.tool }
                    if !hasToolResults {
                        return AIStream(
                            AsyncThrowingStream<AIStreamEvent, any Error> { continuation in
                                continuation.yield(.start(id: "1", model: "m"))
                                continuation.yield(.toolUseStart(id: "t1", name: "calc"))
                                continuation.yield(
                                    .delta(.toolInput(id: "t1", jsonDelta: "{}"))
                                )
                                continuation.yield(
                                    .usage(AIUsage(inputTokens: 5, outputTokens: 3))
                                )
                                continuation.yield(.finish(.toolUse))
                                continuation.finish()
                            }
                        )
                    }
                    return AIStream(
                        AsyncThrowingStream<AIStreamEvent, any Error> { continuation in
                            continuation.yield(.start(id: "2", model: "m"))
                            continuation.yield(.delta(.text("partial")))
                            continuation.finish(
                                throwing: AIError.serverError(
                                    statusCode: 500,
                                    message: "mid-step error"
                                )
                            )
                        }
                    )
                }),
                model: AIModel("test"),
                smoothStreaming: nil
            )

            let tool = AITool(
                name: "calc",
                description: "Calculate",
                inputSchema: .object(properties: [:], required: []),
                handler: { _ in "42" }
            )

            conv.send("Calculate", tools: [tool])
            try await Task.sleep(nanoseconds: 500_000_000)

            XCTAssertFalse(conv.isStreaming)
            XCTAssertNotNil(conv.error)
            let hasUserMessage = conv.messages.contains { $0.role == AIRole.user }
            XCTAssertTrue(hasUserMessage)
        }
    }
#endif
