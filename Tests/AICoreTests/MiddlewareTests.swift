import AICore
import AITestSupport
import Foundation
import XCTest

final class MiddlewareTests: XCTestCase {
    func test_withMiddleware_appliesTransformsAndWrapsGenerateInArrayOrder() async throws {
        let recorder = EventRecorder()
        let provider = MockProvider(
            completionHandler: { request in
                recorder.record("provider-complete")
                return AIResponse(
                    id: "resp", content: [.text(request.metadata["second"] ?? "")], model: request.model.id,
                    finishReason: .stop)
            }
        )
        let wrapped = withMiddleware(
            provider,
            middleware: [
                RecordingMiddleware(name: "first", recorder: recorder),
                RecordingMiddleware(name: "second", recorder: recorder),
            ]
        )

        let response = try await wrapped.complete(AIRequest(model: AIModel("mock"), messages: [.user("Hi")]))
        let calls = await provider.recorder.completeCalls

        XCTAssertEqual(response.text, "applied")
        XCTAssertEqual(
            recorder.snapshot,
            [
                "transform-request-first",
                "transform-request-second",
                "wrap-generate-start-first",
                "wrap-generate-start-second",
                "provider-complete",
                "wrap-generate-end-second",
                "wrap-generate-end-first",
            ])
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].metadata["first"], "applied")
        XCTAssertEqual(calls[0].metadata["second"], "applied")
    }

    func test_withMiddleware_appliesStreamAndEmbedWrappersInArrayOrder() async throws {
        let recorder = EventRecorder()
        let provider = MockProvider(
            streamHandler: { _ in
                recorder.record("provider-stream")
                return AIStream.finished(text: "stream")
            },
            embeddingHandler: { request in
                recorder.record("provider-embed")
                return AIEmbeddingResponse(model: request.model.id, embeddings: [AIEmbedding(index: 0, vector: [1])])
            }
        )
        let wrapped = withMiddleware(
            provider,
            middleware: [
                RecordingMiddleware(name: "first", recorder: recorder),
                RecordingMiddleware(name: "second", recorder: recorder),
            ]
        )

        _ = try await wrapped.stream(AIRequest(model: AIModel("mock"), messages: [.user("Hi")])).collect()
        XCTAssertEqual(
            recorder.snapshot,
            [
                "transform-request-first",
                "transform-request-second",
                "wrap-stream-first",
                "wrap-stream-second",
                "provider-stream",
            ])

        recorder.clear()
        _ = try await wrapped.embed(AIEmbeddingRequest(model: AIModel("embed"), inputs: [.text("swift")]))
        XCTAssertEqual(
            recorder.snapshot,
            [
                "transform-embed-first",
                "transform-embed-second",
                "wrap-embed-start-first",
                "wrap-embed-start-second",
                "provider-embed",
                "wrap-embed-end-second",
                "wrap-embed-end-first",
            ])
    }

    func test_withMiddleware_allowsShortCircuiting() async throws {
        let recorder = EventRecorder()
        let provider = MockProvider()
        let wrapped = withMiddleware(
            provider,
            middleware: [
                RecordingMiddleware(
                    name: "cache",
                    recorder: recorder,
                    shortCircuitResponse: AIResponse(
                        id: "cached",
                        content: [.text("cached")],
                        model: "mock",
                        finishReason: .stop
                    )
                )
            ]
        )

        let response = try await wrapped.complete(AIRequest(model: AIModel("mock"), messages: [.user("Hi")]))
        let calls = await provider.recorder.completeCalls

        XCTAssertEqual(response.id, "cached")
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(
            recorder.snapshot,
            [
                "transform-request-cache",
                "wrap-generate-start-cache",
                "wrap-generate-short-cache",
            ])
    }

    func test_loggingMiddleware_doesNotMutateRequestsOrResponses() async throws {
        let logs = EventRecorder()
        let provider = MockProvider(
            completionHandler: { request in
                AIResponse(
                    id: "resp",
                    content: request.messages.first?.content ?? [],
                    model: request.model.id,
                    finishReason: .stop
                )
            }
        )
        let wrapped = withMiddleware(provider, middleware: [LoggingMiddleware(logger: { logs.record($0) })])
        let response = try await wrapped.complete(
            AIRequest(
                model: AIModel("mock"),
                messages: [.user("Hello")],
                systemPrompt: "Be concise",
                headers: ["X-Test": "1"]
            )
        )
        let calls = await provider.recorder.completeCalls

        XCTAssertEqual(response.text, "Hello")
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].systemPrompt, "Be concise")
        XCTAssertEqual(calls[0].headers, ["X-Test": "1"])
        XCTAssertFalse(logs.snapshot.isEmpty)
    }

    func test_defaultSettingsMiddleware_fillsOnlyMissingGenerationFields() async throws {
        let provider = MockProvider(
            embeddingHandler: { request in
                AIEmbeddingResponse(model: request.model.id, embeddings: [AIEmbedding(index: 0, vector: [1])])
            }
        )
        let wrapped = withMiddleware(
            provider,
            middleware: [
                DefaultSettingsMiddleware(
                    maxTokens: 256,
                    temperature: 0.4,
                    topP: 0.8,
                    toolChoice: .required,
                    allowParallelToolCalls: false,
                    responseFormat: .json
                )
            ]
        )

        _ = try await wrapped.complete(AIRequest(model: AIModel("mock"), messages: [.user("Hi")]))
        _ = try await wrapped.complete(
            AIRequest(
                model: AIModel("mock"),
                messages: [.user("Hi")],
                responseFormat: .jsonSchema(.object(properties: [:], required: [])),
                maxTokens: 12,
                temperature: 0.9,
                topP: 0.6
            )
        )
        _ = try await wrapped.embed(
            AIEmbeddingRequest(
                model: AIModel("embed"),
                inputs: [.text("swift")],
                headers: ["X-Embed": "1"]
            )
        )

        let completeCalls = await provider.recorder.completeCalls
        let embedCalls = await provider.recorder.embedCalls

        XCTAssertEqual(completeCalls.count, 2)
        XCTAssertEqual(completeCalls[0].maxTokens, 256)
        XCTAssertEqual(completeCalls[0].temperature, 0.4)
        XCTAssertEqual(completeCalls[0].topP, 0.8)
        XCTAssertEqual(completeCalls[0].toolChoice, .required)
        XCTAssertEqual(completeCalls[0].allowParallelToolCalls, false)
        XCTAssertEqual(completeCalls[0].responseFormat, .json)

        XCTAssertEqual(completeCalls[1].maxTokens, 12)
        XCTAssertEqual(completeCalls[1].temperature, 0.9)
        XCTAssertEqual(completeCalls[1].topP, 0.6)
        XCTAssertEqual(completeCalls[1].responseFormat, .jsonSchema(.object(properties: [:], required: [])))

        XCTAssertEqual(embedCalls.count, 1)
        XCTAssertEqual(embedCalls[0].headers, ["X-Embed": "1"])
    }
}

private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func record(_ event: String) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }

    var snapshot: [String] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        events.removeAll()
    }
}

private struct RecordingMiddleware: AIMiddleware {
    let name: String
    let recorder: EventRecorder
    var shortCircuitResponse: AIResponse?

    func transformRequest(_ request: AIRequest) async throws -> AIRequest {
        recorder.record("transform-request-\(name)")
        var request = request
        request.metadata[name] = "applied"
        return request
    }

    func transformEmbeddingRequest(_ request: AIEmbeddingRequest) async throws -> AIEmbeddingRequest {
        recorder.record("transform-embed-\(name)")
        return request
    }

    func wrapGenerate(
        request: AIRequest,
        next: @Sendable (AIRequest) async throws -> AIResponse
    ) async throws -> AIResponse {
        recorder.record("wrap-generate-start-\(name)")

        if let shortCircuitResponse {
            recorder.record("wrap-generate-short-\(name)")
            return shortCircuitResponse
        }

        let response = try await next(request)
        recorder.record("wrap-generate-end-\(name)")
        return response
    }

    func wrapStream(
        request: AIRequest,
        next: @Sendable (AIRequest) -> AIStream
    ) -> AIStream {
        recorder.record("wrap-stream-\(name)")
        return next(request)
    }

    func wrapEmbed(
        request: AIEmbeddingRequest,
        next: @Sendable (AIEmbeddingRequest) async throws -> AIEmbeddingResponse
    ) async throws -> AIEmbeddingResponse {
        recorder.record("wrap-embed-start-\(name)")
        let response = try await next(request)
        recorder.record("wrap-embed-end-\(name)")
        return response
    }
}
