import AICore
import AITestSupport
import Foundation
import Testing

/// Spec 11 — Usage & Token Reporting
///
/// Tests 1, 2, 4, 5, 6 are covered by provider-specific test suites:
/// - OpenAI: OpenAISimpleCompletionTests, OpenAIStreamUsageTests, OpenAIEmbeddingUsageTests
/// - Anthropic: AnthropicProviderTransportTests (completion + streaming)
///
/// This file covers the core SDK contract tests (3, 7, 8).
@Suite("Usage & Token Reporting")
struct UsageTests {

    // MARK: - Test 3: collect() propagates .usage event into AIResponse

    @Test("collect() propagates usage from stream event into AIResponse")
    func collectPropagatesUsage() async throws {
        let expectedUsage = AIUsage(inputTokens: 42, outputTokens: 18)

        let stream = AIStream(
            AsyncThrowingStream<AIStreamEvent, any Error>(AIStreamEvent.self, bufferingPolicy: .unbounded) {
                continuation in
                continuation.yield(.start(id: "usage-test", model: "mock"))
                continuation.yield(.delta(.text("hello")))
                continuation.yield(.usage(expectedUsage))
                continuation.yield(.finish(.stop))
                continuation.finish()
            }
        )

        let response = try await stream.collect()

        #expect(response.usage == expectedUsage)
        #expect(response.usage.inputTokens == 42)
        #expect(response.usage.outputTokens == 18)
    }

    // MARK: - Test 7: totalTokens equals inputTokens + outputTokens

    @Test("totalTokens equals inputTokens + outputTokens")
    func totalTokensComputed() {
        let usage = AIUsage(inputTokens: 100, outputTokens: 50)
        #expect(usage.totalTokens == 150)
    }

    @Test("totalTokens is zero when both components are zero")
    func totalTokensZero() {
        let usage = AIUsage(inputTokens: 0, outputTokens: 0)
        #expect(usage.totalTokens == 0)
    }

    @Test("totalTokens reflects large token counts")
    func totalTokensLarge() {
        let usage = AIUsage(inputTokens: 128_000, outputTokens: 4_096)
        #expect(usage.totalTokens == 132_096)
    }

    // MARK: - Test 8: Provider does not return zeroed usage when upstream provides counts

    @Test("MockProvider completion surfaces non-zero usage from handler")
    func completionUsageNotZeroed() async throws {
        let provider = MockProvider(
            completionHandler: { _ in
                AIResponse(
                    id: "resp-1",
                    content: [.text("Hi")],
                    model: "mock",
                    usage: AIUsage(inputTokens: 25, outputTokens: 10)
                )
            }
        )

        let response = try await provider.complete(
            AIRequest(model: AIModel("mock"), messages: [.user("test")])
        )

        #expect(response.usage.inputTokens > 0)
        #expect(response.usage.outputTokens > 0)
        #expect(response.usage.totalTokens == 35)
    }

    @Test("Stream usage event carries non-zero counts through collect()")
    func streamUsageNotZeroed() async throws {
        let provider = MockProvider(
            streamHandler: { _ in
                AIStream(
                    AsyncThrowingStream<AIStreamEvent, any Error>(
                        AIStreamEvent.self,
                        bufferingPolicy: .unbounded
                    ) { continuation in
                        continuation.yield(.start(id: "s1", model: "mock"))
                        continuation.yield(.delta(.text("Hi")))
                        continuation.yield(.usage(AIUsage(inputTokens: 30, outputTokens: 15)))
                        continuation.yield(.finish(.stop))
                        continuation.finish()
                    }
                )
            }
        )

        let response = try await provider.stream(
            AIRequest(model: AIModel("mock"), messages: [.user("test")])
        ).collect()

        #expect(response.usage.inputTokens > 0)
        #expect(response.usage.outputTokens > 0)
        #expect(response.usage.totalTokens == 45)
    }

    // MARK: - Supplementary: collect() uses last .usage event

    @Test("collect() uses the last usage event when multiple are emitted")
    func collectUsesLastUsageEvent() async throws {
        let stream = AIStream(
            AsyncThrowingStream<AIStreamEvent, any Error>(AIStreamEvent.self, bufferingPolicy: .unbounded) {
                continuation in
                continuation.yield(.start(id: "multi-usage", model: "mock"))
                continuation.yield(.usage(AIUsage(inputTokens: 10, outputTokens: 5)))
                continuation.yield(.delta(.text("hello")))
                continuation.yield(.usage(AIUsage(inputTokens: 20, outputTokens: 10)))
                continuation.yield(.finish(.stop))
                continuation.finish()
            }
        )

        let response = try await stream.collect()

        #expect(response.usage.inputTokens == 20)
        #expect(response.usage.outputTokens == 10)
    }

    // MARK: - Supplementary: Tool loop aggregates usage

    @Test("Tool loop aggregates usage across multiple steps")
    func toolLoopAggregatesUsage() async throws {
        let callCount = Counter()

        let tool = AITool(
            name: "echo",
            description: "Echoes",
            inputSchema: .object(properties: ["text": .string()], required: ["text"])
        ) { data in
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json?["text"] as? String ?? ""
        }

        let provider = MockProvider(
            completionHandler: { _ in
                let count = await callCount.incrementAndGet()
                if count <= 2 {
                    var content: [AIContent] = []
                    let input = try! JSONSerialization.data(withJSONObject: ["text": "step-\(count)"])
                    content.append(.toolUse(AIToolUse(id: "tc-\(count)", name: "echo", input: input)))
                    return AIResponse(
                        id: "resp-\(count)",
                        content: content,
                        model: "mock",
                        usage: AIUsage(inputTokens: 10, outputTokens: 5),
                        finishReason: .toolUse
                    )
                }
                return AIResponse(
                    id: "resp-final",
                    content: [.text("Done")],
                    model: "mock",
                    usage: AIUsage(inputTokens: 8, outputTokens: 3),
                    finishReason: .stop
                )
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [tool]
        )

        let result = try await provider.completeWithTools(request)

        #expect(result.steps.count == 2)
        #expect(result.totalUsage.inputTokens == 28)
        #expect(result.totalUsage.outputTokens == 13)
        #expect(result.totalUsage.totalTokens == 41)
    }

    // MARK: - Supplementary: Usage detail fields pass through

    @Test("InputTokenDetails and OutputTokenDetails pass through correctly")
    func usageDetailFields() {
        let usage = AIUsage(
            inputTokens: 100,
            outputTokens: 50,
            inputTokenDetails: AIUsage.InputTokenDetails(cachedTokens: 30, cacheWriteTokens: 20),
            outputTokenDetails: AIUsage.OutputTokenDetails(reasoningTokens: 15)
        )

        #expect(usage.inputTokenDetails?.cachedTokens == 30)
        #expect(usage.inputTokenDetails?.cacheWriteTokens == 20)
        #expect(usage.outputTokenDetails?.reasoningTokens == 15)
        #expect(usage.totalTokens == 150)
    }
}

// MARK: - Helpers

private actor Counter {
    private(set) var value: Int = 0

    @discardableResult
    func incrementAndGet() -> Int {
        value += 1
        return value
    }
}
