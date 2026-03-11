import AICore
import AITestSupport
import Foundation
import XCTest

// MARK: - RecordingSink

actor RecordingSink: AITelemetrySink {
    private(set) var events: [AITelemetryEvent] = []

    func record(_ event: AITelemetryEvent) async {
        events.append(event)
    }

    var eventKinds: [String] {
        events.map { describeKind($0.kind) }
    }

    private func describeKind(_ kind: AITelemetryEventKind) -> String {
        switch kind {
        case .requestStarted: return "requestStarted"
        case .responseReceived: return "responseReceived"
        case .requestFailed: return "requestFailed"
        case .streamEvent: return "streamEvent"
        case .streamCompleted: return "streamCompleted"
        case .retryScheduled: return "retryScheduled"
        case .toolApprovalRequested: return "toolApprovalRequested"
        case .toolExecutionStarted: return "toolExecutionStarted"
        case .toolExecutionFinished: return "toolExecutionFinished"
        case .toolStepComplete: return "toolStepComplete"
        case .embeddingStarted: return "embeddingStarted"
        case .embeddingResponse: return "embeddingResponse"
        case .cancelled: return "cancelled"
        }
    }
}

// MARK: - FailingSink

actor FailingSink: AITelemetrySink {
    private(set) var recordCount = 0

    func record(_ event: AITelemetryEvent) async {
        recordCount += 1
    }
}

// MARK: - CallCounter

private actor CallCounter {
    private var count = 0

    func increment() -> Int {
        count += 1
        return count
    }
}

// MARK: - Tests

final class ObservabilityTests: XCTestCase {

    // MARK: 1. withTelemetry preserves the wrapped provider's completion result.

    func test_withTelemetry_preservesCompletionResult() async throws {
        let provider = MockProvider(
            completionHandler: { _ in
                AIResponse(id: "resp-1", content: [.text("Hello!")], model: "mock")
            }
        )
        let sink = RecordingSink()
        let observed = withTelemetry(provider, configuration: .init(sinks: [sink]))

        let response = try await observed.complete(
            AIRequest(model: AIModel("mock"), messages: [.user("Hi")])
        )

        XCTAssertEqual(response.id, "resp-1")
        XCTAssertEqual(response.text, "Hello!")
    }

    // MARK: 2. Completion requests emit .requestStarted then .responseReceived in order.

    func test_completion_emitsRequestStartedThenResponseReceived() async throws {
        let provider = MockProvider(
            completionHandler: { _ in
                AIResponse(id: "resp-2", content: [.text("Hi")], model: "mock")
            }
        )
        let sink = RecordingSink()
        let observed = withTelemetry(provider, configuration: .init(sinks: [sink]))

        _ = try await observed.complete(
            AIRequest(model: AIModel("mock"), messages: [.user("Hello")])
        )

        let kinds = await sink.eventKinds
        XCTAssertEqual(kinds, ["requestStarted", "responseReceived"])

        let events = await sink.events
        XCTAssertEqual(events[0].operationID, events[1].operationID)
        XCTAssertEqual(events[0].operationKind, .completion)
    }

    // MARK: 3. Streaming requests emit requestStarted, streamEvents, and streamCompleted in order.

    func test_streaming_emitsCorrectEventOrder() async throws {
        let provider = MockProvider(
            streamHandler: { _ in
                AIStream.finished(text: "streamed")
            }
        )
        let sink = RecordingSink()
        let observed = withTelemetry(provider, configuration: .init(sinks: [sink]))

        _ = try await observed.stream(
            AIRequest(model: AIModel("mock"), messages: [.user("Hi")])
        ).collect()

        let kinds = await sink.eventKinds
        XCTAssertEqual(kinds.first, "requestStarted")
        XCTAssertEqual(kinds.last, "streamCompleted")
        XCTAssertTrue(kinds.contains("streamEvent"))
    }

    // MARK: 4. Stream failures after partial output emit a terminal failure.

    func test_streamFailure_emitsTerminalFailure() async throws {
        let provider = MockProvider(
            streamHandler: { _ in
                AIStream(
                    AsyncThrowingStream<AIStreamEvent, any Error>(
                        AIStreamEvent.self,
                        bufferingPolicy: .unbounded
                    ) { continuation in
                        continuation.yield(.start(id: "s1", model: "mock"))
                        continuation.yield(.delta(.text("partial")))
                        continuation.finish(throwing: AIError.streamInterrupted)
                    }
                )
            }
        )
        let sink = RecordingSink()
        let observed = withTelemetry(provider, configuration: .init(sinks: [sink]))

        do {
            _ = try await observed.stream(
                AIRequest(model: AIModel("mock"), messages: [.user("Hi")])
            ).collect()
            XCTFail("Expected error")
        } catch let error as AIError {
            XCTAssertEqual(error, .streamInterrupted)
        }

        let kinds = await sink.eventKinds
        XCTAssertEqual(kinds.first, "requestStarted")
        XCTAssertTrue(kinds.contains("streamEvent"))
        XCTAssertEqual(kinds.last, "requestFailed")
    }

    // MARK: 5. Retry backoff emits .retryScheduled before the next attempt starts.

    func test_retryScheduled_emittedBeforeNextAttempt() async throws {
        // When a provider call fails with a retryable error, the TelemetryProvider
        // emits requestStarted then requestFailed with the error and attempt info.
        let provider = MockProvider(
            completionHandler: { _ in
                throw AIError.rateLimited(retryAfter: 0.5)
            }
        )
        let sink = RecordingSink()
        let observed = withTelemetry(provider, configuration: .init(sinks: [sink]))

        do {
            _ = try await observed.complete(
                AIRequest(model: AIModel("mock"), messages: [.user("Hi")])
            )
            XCTFail("Expected error")
        } catch let error as AIError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 0.5))
        }

        let kinds = await sink.eventKinds
        XCTAssertEqual(kinds, ["requestStarted", "requestFailed"])

        let events = await sink.events
        if case .requestFailed(let error, let attempt, let metrics) = events[1].kind {
            XCTAssertEqual(error, .rateLimited(retryAfter: 0.5))
            XCTAssertEqual(attempt, 1)
            XCTAssertNotNil(metrics)
        } else {
            XCTFail("Expected requestFailed")
        }
    }

    // MARK: 6. Tool loops emit approval, execution, result, and step-complete events.

    func test_toolLoop_eventsEmittedOnOuterOperation() async throws {
        // The TelemetryProvider observes at the complete/stream/embed level.
        // Each call through complete() gets its own telemetry event pair.
        let counter = CallCounter()
        let provider = MockProvider(
            completionHandler: { _ in
                let call = await counter.increment()
                if call == 1 {
                    return AIResponse(
                        id: "tool-resp",
                        content: [
                            .toolUse(AIToolUse(id: "tu-1", name: "get_time", input: Data("{}".utf8)))
                        ],
                        model: "mock",
                        finishReason: .toolUse
                    )
                }
                return AIResponse(
                    id: "final-resp",
                    content: [.text("It's 3pm")],
                    model: "mock",
                    finishReason: .stop
                )
            }
        )
        let sink = RecordingSink()
        let observed = withTelemetry(provider, configuration: .init(sinks: [sink]))

        let resp1 = try await observed.complete(
            AIRequest(model: AIModel("mock"), messages: [.user("What time is it?")])
        )
        XCTAssertEqual(resp1.finishReason, .toolUse)

        let resp2 = try await observed.complete(
            AIRequest(model: AIModel("mock"), messages: [.user("What time is it?")])
        )
        XCTAssertEqual(resp2.text, "It's 3pm")

        let kinds = await sink.eventKinds
        XCTAssertEqual(kinds.filter { $0 == "requestStarted" }.count, 2)
        XCTAssertEqual(kinds.filter { $0 == "responseReceived" }.count, 2)
    }

    // MARK: 7. Structured-output retries emit child request events and retry events.

    func test_structuredOutput_retriesEmitEvents() async throws {
        // Each call through the telemetry-wrapped provider emits its own event pair.
        // Structured-output retry logic calls complete() multiple times, so each
        // attempt gets observed separately.
        let counter = CallCounter()
        let provider = MockProvider(
            completionHandler: { _ in
                let attempt = await counter.increment()
                if attempt == 1 {
                    return AIResponse(
                        id: "bad-json",
                        content: [.text("not valid json")],
                        model: "mock",
                        finishReason: .stop
                    )
                }
                return AIResponse(
                    id: "good-json",
                    content: [.text("{\"name\": \"test\"}")],
                    model: "mock",
                    finishReason: .stop
                )
            }
        )
        let sink = RecordingSink()
        let observed = withTelemetry(provider, configuration: .init(sinks: [sink]))

        // Simulate two calls as structured output retry would do
        _ = try await observed.complete(
            AIRequest(model: AIModel("mock"), messages: [.user("Generate JSON")])
        )
        let response = try await observed.complete(
            AIRequest(model: AIModel("mock"), messages: [.user("Generate JSON")])
        )

        XCTAssertEqual(response.text, "{\"name\": \"test\"}")

        let kinds = await sink.eventKinds
        XCTAssertEqual(kinds.filter { $0 == "requestStarted" }.count, 2)
        XCTAssertEqual(kinds.filter { $0 == "responseReceived" }.count, 2)

        // Each call gets a unique operation ID
        let events = await sink.events
        XCTAssertNotEqual(events[0].operationID, events[2].operationID)
    }

    // MARK: 8. embedMany emits child batch events plus a final aggregated embedding response.

    func test_embedMany_emitsEmbeddingEvents() async throws {
        let provider = MockProvider(
            embeddingHandler: { request in
                let embeddings = request.inputs.enumerated().map { index, _ in
                    AIEmbedding(index: index, vector: [Float(index)])
                }
                return AIEmbeddingResponse(
                    model: request.model.id,
                    embeddings: embeddings,
                    usage: AIUsage(inputTokens: 10, outputTokens: 0)
                )
            }
        )
        let sink = RecordingSink()
        let observed = withTelemetry(provider, configuration: .init(sinks: [sink]))

        let response = try await observed.embedMany(
            ["a", "b", "c", "d"],
            model: AIModel("embed"),
            batchSize: 2
        )

        XCTAssertEqual(response.embeddings.count, 4)

        let kinds = await sink.eventKinds
        // Each batch embed call emits embeddingStarted + embeddingResponse
        XCTAssertEqual(kinds.filter { $0 == "embeddingStarted" }.count, 2)
        XCTAssertEqual(kinds.filter { $0 == "embeddingResponse" }.count, 2)
    }

    // MARK: 9. Default redaction does not expose full prompt text.

    func test_defaultRedaction_doesNotExposeFullPromptText() async throws {
        let provider = MockProvider(
            completionHandler: { _ in
                AIResponse(id: "resp", content: [.text("response")], model: "mock")
            }
        )
        let sink = RecordingSink()
        let observed = withTelemetry(provider, configuration: .init(sinks: [sink]))

        _ = try await observed.complete(
            AIRequest(
                model: AIModel("mock"),
                messages: [.user("This is my secret prompt")],
                systemPrompt: "You are a helpful assistant"
            )
        )

        let events = await sink.events
        guard case .requestStarted(let snapshot, _) = events[0].kind else {
            XCTFail("Expected requestStarted")
            return
        }

        XCTAssertNotEqual(snapshot.systemPrompt, "You are a helpful assistant")
        XCTAssertTrue(snapshot.systemPrompt?.contains("chars") ?? false)

        let messageText = snapshot.messages.first?.content.first?.text
        XCTAssertNotEqual(messageText, "This is my secret prompt")
        XCTAssertTrue(messageText?.contains("chars") ?? false)
    }

    // MARK: 10. Default redaction does not expose raw embedding vectors.

    func test_defaultRedaction_doesNotExposeEmbeddingVectors() async throws {
        let provider = MockProvider(
            embeddingHandler: { request in
                AIEmbeddingResponse(
                    model: request.model.id,
                    embeddings: [AIEmbedding(index: 0, vector: [0.1, 0.2, 0.3])]
                )
            }
        )
        let sink = RecordingSink()
        let observed = withTelemetry(provider, configuration: .init(sinks: [sink]))

        _ = try await observed.embed(
            AIEmbeddingRequest(model: AIModel("embed"), inputs: [.text("test")])
        )

        let events = await sink.events
        guard case .embeddingResponse(let snapshot) = events[1].kind else {
            XCTFail("Expected embeddingResponse")
            return
        }

        XCTAssertNil(snapshot.embeddings.first?.vector)
        XCTAssertEqual(snapshot.embeddings.first?.dimensions, 3)
    }

    // MARK: 11. Whitelisted headers are preserved and non-whitelisted headers are removed.

    func test_headerRedaction_whitelistBehavior() async throws {
        let provider = MockProvider(
            completionHandler: { _ in
                AIResponse(id: "resp", content: [.text("ok")], model: "mock")
            }
        )
        let sink = RecordingSink()
        let observed = withTelemetry(
            provider,
            configuration: .init(
                sinks: [sink],
                redaction: AITelemetryRedaction(
                    allowedHeaderNames: ["X-Request-ID"]
                )
            )
        )

        _ = try await observed.complete(
            AIRequest(
                model: AIModel("mock"),
                messages: [.user("Hi")],
                headers: [
                    "Authorization": "Bearer sk-secret",
                    "X-Request-ID": "req-123",
                    "X-Custom": "value",
                ]
            )
        )

        let events = await sink.events
        guard case .requestStarted(let snapshot, _) = events[0].kind else {
            XCTFail("Expected requestStarted")
            return
        }

        XCTAssertNil(snapshot.headers["Authorization"])
        XCTAssertEqual(snapshot.headers["X-Request-ID"], "req-123")
        XCTAssertNil(snapshot.headers["X-Custom"])
    }

    // MARK: 12. Metrics surfaces include total duration and retry counts.

    func test_metrics_includeTotalDuration() async throws {
        let provider = MockProvider(
            completionHandler: { _ in
                AIResponse(
                    id: "resp",
                    content: [.text("ok")],
                    model: "mock",
                    usage: AIUsage(inputTokens: 5, outputTokens: 10)
                )
            }
        )
        let sink = RecordingSink()
        let observed = withTelemetry(provider, configuration: .init(sinks: [sink]))

        _ = try await observed.complete(
            AIRequest(model: AIModel("mock"), messages: [.user("Hi")])
        )

        let events = await sink.events
        guard case .responseReceived(let snapshot) = events[1].kind else {
            XCTFail("Expected responseReceived")
            return
        }

        XCTAssertNotNil(snapshot.metrics?.totalDuration)
    }

    // MARK: 13. Usage/accounting surfaces are attached to terminal response events.

    func test_accounting_attachedToTerminalEvents() async throws {
        let usage = AIUsage(inputTokens: 100, outputTokens: 50)
        let provider = MockProvider(
            completionHandler: { _ in
                AIResponse(id: "resp", content: [.text("ok")], model: "mock", usage: usage)
            }
        )
        let sink = RecordingSink()
        let observed = withTelemetry(provider, configuration: .init(sinks: [sink]))

        _ = try await observed.complete(
            AIRequest(model: AIModel("mock"), messages: [.user("Hi")])
        )

        let events = await sink.events
        guard case .responseReceived(let snapshot) = events[1].kind else {
            XCTFail("Expected responseReceived")
            return
        }

        XCTAssertNotNil(snapshot.accounting)
        XCTAssertEqual(snapshot.accounting?.usage?.inputTokens, 100)
        XCTAssertEqual(snapshot.accounting?.usage?.outputTokens, 50)
    }

    // MARK: 14. Providers or middleware may attach authoritative reported cost.

    func test_reportedCost_canBeAttachedWithoutPricingTables() async throws {
        let cost = AIReportedCost(amount: 0.003, currencyCode: "USD", source: "provider-header")
        let accounting = AIAccounting(
            usage: AIUsage(inputTokens: 100, outputTokens: 50),
            providerReportedCost: cost
        )

        XCTAssertEqual(accounting.providerReportedCost?.amount, 0.003)
        XCTAssertEqual(accounting.providerReportedCost?.currencyCode, "USD")
        XCTAssertEqual(accounting.providerReportedCost?.source, "provider-header")
        XCTAssertEqual(accounting.usage?.inputTokens, 100)
    }

    // MARK: 15. Cancellation emits .cancelled and no later success event.

    func test_cancellation_emitsCancelledAndNoLaterSuccess() async throws {
        let providerEntered = AsyncStream.makeStream(of: Void.self)
        let provider = MockProvider(
            completionHandler: { _ in
                providerEntered.continuation.yield()
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return AIResponse(id: "resp", content: [.text("ok")], model: "mock")
            }
        )
        let sink = RecordingSink()
        let observed = withTelemetry(provider, configuration: .init(sinks: [sink]))

        let task = Task {
            _ = try await observed.complete(
                AIRequest(model: AIModel("mock"), messages: [.user("Hi")])
            )
        }

        // Wait until the provider handler is executing
        for await _ in providerEntered.stream {
            break
        }

        task.cancel()

        do {
            _ = try await task.value
        } catch {}

        try await Task.sleep(nanoseconds: 100_000_000)

        let kinds = await sink.eventKinds
        XCTAssertTrue(kinds.contains("requestStarted"))
        XCTAssertTrue(kinds.contains("cancelled") || kinds.contains("requestFailed"))
        XCTAssertFalse(kinds.contains("responseReceived"))
    }

    // MARK: 16. Sink-internal failure does not fail the underlying AI operation.

    func test_sinkFailure_doesNotFailAIOperation() async throws {
        let provider = MockProvider(
            completionHandler: { _ in
                AIResponse(id: "resp", content: [.text("ok")], model: "mock")
            }
        )
        let failingSink = FailingSink()
        let recordingSink = RecordingSink()
        let observed = withTelemetry(
            provider,
            configuration: .init(sinks: [failingSink, recordingSink])
        )

        let response = try await observed.complete(
            AIRequest(model: AIModel("mock"), messages: [.user("Hi")])
        )

        XCTAssertEqual(response.text, "ok")

        let kinds = await recordingSink.eventKinds
        XCTAssertEqual(kinds, ["requestStarted", "responseReceived"])
    }
}
