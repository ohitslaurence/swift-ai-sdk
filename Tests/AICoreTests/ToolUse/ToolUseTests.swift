import AITestSupport
import Foundation
import Testing
@testable import AICore

@Suite("Tool Use & Agentic Loops")
struct ToolUseTests {

    // MARK: - Helpers

    private func makeToolUseResponse(
        id: String = "resp-1",
        toolCalls: [(id: String, name: String, input: Data)] = [],
        model: String = "mock-model"
    ) -> AIResponse {
        var content: [AIContent] = []
        for tc in toolCalls {
            content.append(.toolUse(AIToolUse(id: tc.id, name: tc.name, input: tc.input)))
        }
        return AIResponse(
            id: id,
            content: content,
            model: model,
            usage: AIUsage(inputTokens: 10, outputTokens: 5),
            finishReason: .toolUse
        )
    }

    private func makeFinalResponse(
        id: String = "resp-final",
        text: String = "Done",
        model: String = "mock-model"
    ) -> AIResponse {
        AIResponse(
            id: id,
            content: [.text(text)],
            model: model,
            usage: AIUsage(inputTokens: 8, outputTokens: 3),
            finishReason: .stop
        )
    }

    private func makeEchoTool(name: String = "echo") -> AITool {
        AITool(
            name: name,
            description: "Echoes input",
            inputSchema: .object(properties: ["text": .string()], required: ["text"])
        ) { data in
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json?["text"] as? String ?? "no-text"
        }
    }

    private func makeInput(_ dict: [String: Any]) -> Data {
        // swiftlint:disable:next force_try
        (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
    }

    // MARK: - 1. Single tool call executes and returns a final model response

    @Test("Single tool call executes and returns final response")
    func singleToolCall() async throws {
        let callCount = Counter()

        let provider = MockProvider(
            completionHandler: { request in
                let count = await callCount.incrementAndGet()
                if count == 1 {
                    return self.makeToolUseResponse(
                        toolCalls: [("tc-1", "echo", self.makeInput(["text": "hello"]))]
                    )
                }
                return self.makeFinalResponse()
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [makeEchoTool()]
        )

        let result = try await provider.completeWithTools(request)

        #expect(result.stopReason == .modelStopped)
        #expect(result.steps.count == 1)
        #expect(result.steps[0].toolResults[0].content == "hello")
        #expect(result.response.text == "Done")
    }

    // MARK: - 2. Multiple tool calls in one step execute concurrently

    @Test("Multiple tool calls in one step execute concurrently")
    func multipleToolCallsConcurrent() async throws {
        let callCount = Counter()
        let sleepDuration: UInt64 = 500_000_000

        let provider = MockProvider(
            completionHandler: { request in
                let count = await callCount.incrementAndGet()
                if count == 1 {
                    return self.makeToolUseResponse(
                        toolCalls: [
                            ("tc-1", "echo", self.makeInput(["text": "a"])),
                            ("tc-2", "echo", self.makeInput(["text": "b"])),
                        ]
                    )
                }
                return self.makeFinalResponse()
            }
        )

        let concurrentTool = AITool(
            name: "echo",
            description: "Echoes input",
            inputSchema: .object(properties: ["text": .string()], required: ["text"])
        ) { data in
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            try await Task.sleep(nanoseconds: sleepDuration)
            return json?["text"] as? String ?? "no-text"
        }

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [concurrentTool]
        )

        let clock = ContinuousClock()
        let start = clock.now
        let result = try await provider.completeWithTools(request)
        let elapsed = clock.now - start

        #expect(result.steps.count == 1)
        #expect(result.steps[0].toolResults.count == 2)

        let resultContents = Set(result.steps[0].toolResults.map(\.content))
        #expect(resultContents == Set(["a", "b"]))
        #expect(elapsed < .milliseconds(750))
    }

    // MARK: - 3. Multi-step loop calls tools across multiple turns

    @Test("Multi-step loop across multiple turns")
    func multiStepLoop() async throws {
        let callCount = Counter()

        let provider = MockProvider(
            completionHandler: { request in
                let count = await callCount.incrementAndGet()
                if count <= 2 {
                    return self.makeToolUseResponse(
                        id: "resp-\(count)",
                        toolCalls: [("tc-\(count)", "echo", self.makeInput(["text": "step-\(count)"]))]
                    )
                }
                return self.makeFinalResponse()
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [makeEchoTool()]
        )

        let result = try await provider.completeWithTools(request)

        #expect(result.steps.count == 2)
        #expect(result.stopReason == .modelStopped)
    }

    // MARK: - 4. maxSteps returns conditionMet, not an error

    @Test("maxSteps returns conditionMet, not an error")
    func maxStepsConditionMet() async throws {
        let provider = MockProvider(
            completionHandler: { _ in
                self.makeToolUseResponse(
                    toolCalls: [("tc-1", "echo", self.makeInput(["text": "loop"]))]
                )
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [makeEchoTool()]
        )

        let result = try await provider.completeWithTools(request, stopWhen: [.maxSteps(2)])

        #expect(result.steps.count == 2)
        if case .conditionMet(let desc) = result.stopReason {
            #expect(desc.contains("2"))
        } else {
            Issue.record("Expected conditionMet, got \(result.stopReason)")
        }
    }

    // MARK: - 5. toolCalled stop condition stops the loop

    @Test("toolCalled stop condition stops the loop")
    func toolCalledStopCondition() async throws {
        let callCount = Counter()

        let provider = MockProvider(
            completionHandler: { _ in
                let count = await callCount.incrementAndGet()
                let toolName = count == 1 ? "echo" : "special"
                return self.makeToolUseResponse(
                    toolCalls: [("tc-\(count)", toolName, self.makeInput(["text": "x"]))]
                )
            }
        )

        let specialTool = AITool(
            name: "special",
            description: "Special",
            inputSchema: .object(properties: [:], required: [])
        ) { _ in "special-result" }

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [makeEchoTool(), specialTool]
        )

        let result = try await provider.completeWithTools(
            request,
            stopWhen: [.toolCalled("special"), .maxSteps(10)]
        )

        #expect(result.steps.count == 2)
        if case .conditionMet(let desc) = result.stopReason {
            #expect(desc.contains("special"))
        } else {
            Issue.record("Expected conditionMet")
        }
    }

    // MARK: - 6. Custom stop condition stops the loop

    @Test("Custom stop condition stops the loop")
    func customStopCondition() async throws {
        let callCount = Counter()

        let provider = MockProvider(
            completionHandler: { _ in
                let count = await callCount.incrementAndGet()
                return self.makeToolUseResponse(
                    toolCalls: [("tc-\(count)", "echo", self.makeInput(["text": "x"]))]
                )
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [makeEchoTool()]
        )

        let result = try await provider.completeWithTools(
            request,
            stopWhen: [.custom(description: "three steps") { $0.count >= 3 }]
        )

        #expect(result.steps.count == 3)
        if case .conditionMet(let desc) = result.stopReason {
            #expect(desc == "three steps")
        } else {
            Issue.record("Expected conditionMet")
        }
    }

    // MARK: - 7. Multiple stop conditions use OR logic

    @Test("Multiple stop conditions use OR logic")
    func multipleStopConditionsOR() async throws {
        let callCount = Counter()

        let provider = MockProvider(
            completionHandler: { _ in
                let count = await callCount.incrementAndGet()
                return self.makeToolUseResponse(
                    toolCalls: [("tc-\(count)", "echo", self.makeInput(["text": "x"]))]
                )
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [makeEchoTool()]
        )

        let result = try await provider.completeWithTools(
            request,
            stopWhen: [
                .maxSteps(2),
                .toolCalled("nonexistent"),
            ]
        )

        #expect(result.steps.count == 2)
        if case .conditionMet(let desc) = result.stopReason {
            #expect(desc.contains("2"))
        } else {
            Issue.record("Expected conditionMet from maxSteps")
        }
    }

    // MARK: - 8. Tool handler failures are returned as error results

    @Test("Tool handler failures become error results")
    func toolHandlerFailures() async throws {
        let callCount = Counter()

        let failingTool = AITool(
            name: "fail",
            description: "Always fails",
            inputSchema: .object(properties: [:], required: [])
        ) { _ in
            throw TestToolError.intentional
        }

        let provider = MockProvider(
            completionHandler: { _ in
                let count = await callCount.incrementAndGet()
                if count == 1 {
                    return self.makeToolUseResponse(
                        toolCalls: [("tc-1", "fail", Data("{}".utf8))]
                    )
                }
                return self.makeFinalResponse()
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [failingTool]
        )

        let result = try await provider.completeWithTools(request)

        #expect(result.steps[0].toolResults[0].isError == true)
        #expect(result.stopReason == .modelStopped)
    }

    @Test("Tool handler failures do not trigger tool call repair")
    func toolHandlerFailuresDoNotTriggerRepair() async throws {
        let callCount = Counter()
        let repairCallCount = Counter()

        let failingTool = try AITool.define(
            name: "fail",
            description: "Always fails"
        ) { (_: SimpleInput) async throws -> String in
            throw TestToolError.intentional
        }

        let provider = MockProvider(
            completionHandler: { _ in
                let count = await callCount.incrementAndGet()
                if count == 1 {
                    return self.makeToolUseResponse(
                        toolCalls: [("tc-1", "fail", self.makeInput(["value": "x"]))]
                    )
                }
                return self.makeFinalResponse()
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [failingTool]
        )

        let result = try await provider.completeWithTools(
            request,
            toolCallRepairHandler: { _, _ in
                await repairCallCount.incrementAndGet()
                return self.makeInput(["value": "repaired"])
            }
        )

        #expect(result.steps[0].toolResults[0].isError == true)
        #expect(await repairCallCount.value == 0)
    }

    // MARK: - 9. Approval-gated tools execute when approved

    @Test("Approval-gated tools execute when approved")
    func approvalGranted() async throws {
        let callCount = Counter()

        let approvalTool = AITool(
            name: "sensitive",
            description: "Needs approval",
            inputSchema: .object(properties: ["text": .string()], required: ["text"]),
            needsApproval: true
        ) { data in
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json?["text"] as? String ?? ""
        }

        let provider = MockProvider(
            completionHandler: { _ in
                let count = await callCount.incrementAndGet()
                if count == 1 {
                    return self.makeToolUseResponse(
                        toolCalls: [("tc-1", "sensitive", self.makeInput(["text": "approved"]))]
                    )
                }
                return self.makeFinalResponse()
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [approvalTool]
        )

        let result = try await provider.completeWithTools(
            request,
            approvalHandler: { _ in true }
        )

        #expect(result.steps[0].toolResults[0].content == "approved")
        #expect(result.steps[0].toolResults[0].isError == false)
    }

    // MARK: - 10. Approval-gated tools denied when no approval handler

    @Test("Approval-gated tools denied when no handler exists")
    func approvalNoHandler() async throws {
        let callCount = Counter()

        let approvalTool = AITool(
            name: "sensitive",
            description: "Needs approval",
            inputSchema: .object(properties: [:], required: []),
            needsApproval: true
        ) { _ in "should not execute" }

        let provider = MockProvider(
            completionHandler: { _ in
                let count = await callCount.incrementAndGet()
                if count == 1 {
                    return self.makeToolUseResponse(
                        toolCalls: [("tc-1", "sensitive", Data("{}".utf8))]
                    )
                }
                return self.makeFinalResponse()
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [approvalTool]
        )

        let result = try await provider.completeWithTools(request)

        #expect(result.steps[0].toolResults[0].isError == true)
        #expect(result.steps[0].toolResults[0].content.contains("denied"))
    }

    // MARK: - 11. Approval-gated tools return denial results when rejected

    @Test("Approval-gated tools denied when rejected")
    func approvalRejected() async throws {
        let callCount = Counter()

        let approvalTool = AITool(
            name: "sensitive",
            description: "Needs approval",
            inputSchema: .object(properties: [:], required: []),
            needsApproval: true
        ) { _ in "should not execute" }

        let provider = MockProvider(
            completionHandler: { _ in
                let count = await callCount.incrementAndGet()
                if count == 1 {
                    return self.makeToolUseResponse(
                        toolCalls: [("tc-1", "sensitive", Data("{}".utf8))]
                    )
                }
                return self.makeFinalResponse()
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [approvalTool]
        )

        let result = try await provider.completeWithTools(
            request,
            approvalHandler: { _ in false }
        )

        #expect(result.steps[0].toolResults[0].isError == true)
        #expect(result.steps[0].toolResults[0].content.contains("denied"))
    }

    // MARK: - 12. Tool call repair succeeds with repaired JSON input

    @Test("Tool call repair succeeds with repaired input")
    func toolCallRepairSuccess() async throws {
        let callCount = Counter()

        let typedTool = try AITool.define(
            name: "typed",
            description: "Needs valid JSON"
        ) { (input: IntInput) async throws -> String in
            let value = input.value
            return "got \(value)"
        }

        let provider = MockProvider(
            completionHandler: { _ in
                let count = await callCount.incrementAndGet()
                if count == 1 {
                    return self.makeToolUseResponse(
                        toolCalls: [("tc-1", "typed", Data("{bad json".utf8))]
                    )
                }
                return self.makeFinalResponse()
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [typedTool]
        )

        let result = try await provider.completeWithTools(
            request,
            toolCallRepairHandler: { _, _ in
                self.makeInput(["value": 42])
            }
        )

        #expect(result.steps[0].toolResults[0].content == "got 42")
        #expect(result.steps[0].toolResults[0].isError == false)
        #expect(await callCount.value == 2)
    }

    // MARK: - 13. Tool call repair falls back to error result when repair fails

    @Test("Tool call repair falls back to error when repair fails")
    func toolCallRepairFallback() async throws {
        let callCount = Counter()

        let typedTool = try AITool.define(
            name: "typed",
            description: "Needs valid JSON"
        ) { (_: IntInput) async throws -> String in
            return "success"
        }

        let provider = MockProvider(
            completionHandler: { _ in
                let count = await callCount.incrementAndGet()
                if count == 1 {
                    return self.makeToolUseResponse(
                        toolCalls: [("tc-1", "typed", Data("{bad".utf8))]
                    )
                }
                return self.makeFinalResponse()
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [typedTool]
        )

        let result = try await provider.completeWithTools(
            request,
            toolCallRepairHandler: { _, _ in
                Data("{still bad".utf8)
            }
        )

        #expect(result.steps[0].toolResults[0].isError == true)
    }

    // MARK: - 14. AITool.define derives schema from Input.jsonSchema

    @Test("AITool.define derives schema from Input.jsonSchema")
    func defineDerivesSchema() throws {
        let tool = try AITool.define(
            name: "weather",
            description: "Gets weather"
        ) { (input: WeatherInput) async throws -> String in
            "Sunny in \(input.city)"
        }

        #expect(tool.name == "weather")
        #expect(tool.inputSchema != .object(properties: [:], required: []))

        if case .object(let props, let required, _, _) = tool.inputSchema {
            #expect(props.keys.contains("city"))
            #expect(required.contains("city"))
        } else {
            Issue.record("Expected object schema")
        }
    }

    // MARK: - 15. AITool.define JSON-encodes non-string outputs

    @Test("AITool.define JSON-encodes non-string outputs")
    func defineJSONEncodesOutput() async throws {
        let tool = try AITool.define(
            name: "compute",
            description: "Computes"
        ) { (_: SimpleInput) async throws -> ComputeOutput in
            ComputeOutput(result: 42, label: "answer")
        }

        let input = makeInput(["value": "test"])
        let output = try await tool.handler(input)

        #expect(output.contains("42"))
        #expect(output.contains("answer"))

        let stringTool = try AITool.define(
            name: "echo",
            description: "Echoes"
        ) { (input: SimpleInput) async throws -> String in
            "raw: \(input.value)"
        }

        let stringOutput = try await stringTool.handler(input)
        #expect(stringOutput == "raw: test")
    }

    // MARK: - 16. Agent.run() works end to end

    @Test("Agent.run() works end to end")
    func agentRun() async throws {
        let callCount = Counter()

        let provider = MockProvider(
            completionHandler: { _ in
                let count = await callCount.incrementAndGet()
                if count == 1 {
                    return self.makeToolUseResponse(
                        toolCalls: [("tc-1", "echo", self.makeInput(["text": "hello"]))]
                    )
                }
                return self.makeFinalResponse(text: "Agent done")
            }
        )

        let agent = Agent(
            provider: provider,
            model: AIModel("mock"),
            systemPrompt: "You are helpful.",
            tools: [makeEchoTool()]
        )

        let result = try await agent.run("Do something")

        #expect(result.response.text == "Agent done")
        #expect(result.steps.count == 1)
    }

    // MARK: - 17. Agent.run(messages:) preserves conversation history

    @Test("Agent.run(messages:) preserves conversation history")
    func agentRunWithMessages() async throws {
        let recorder = MockProviderRecorder()

        let provider = MockProvider(
            completionHandler: { _ in
                self.makeFinalResponse()
            },
            recorder: recorder
        )

        let agent = Agent(
            provider: provider,
            model: AIModel("mock"),
            tools: [makeEchoTool()]
        )

        let messages: [AIMessage] = [
            .user("First message"),
            .assistant("First reply"),
            .user("Second message"),
        ]

        let result = try await agent.run(messages: messages)

        let recorded = await recorder.completeCalls
        #expect(recorded.count == 1)
        #expect(recorded[0].messages.count == 3)
        #expect(result.stopReason == .modelStopped)
    }

    // MARK: - 18. streamWithTools emits a seamless stitched stream across steps

    @Test("streamWithTools emits stitched stream across steps")
    func streamWithToolsStitched() async throws {
        let streamSequencer = StreamSequencer(streams: [
            AIStream(
                AsyncThrowingStream { continuation in
                    continuation.yield(.start(id: "s1", model: "mock"))
                    continuation.yield(.delta(.text("thinking...")))
                    continuation.yield(.toolUseStart(id: "tc-1", name: "echo"))
                    continuation.yield(.delta(.toolInput(id: "tc-1", jsonDelta: "{\"text\":\"hi\"}")))
                    continuation.yield(.usage(AIUsage(inputTokens: 5, outputTokens: 3)))
                    continuation.yield(.finish(.toolUse))
                    continuation.finish()
                }
            ),
            AIStream(
                AsyncThrowingStream { continuation in
                    continuation.yield(.start(id: "s2", model: "mock"))
                    continuation.yield(.delta(.text("final answer")))
                    continuation.yield(.usage(AIUsage(inputTokens: 3, outputTokens: 2)))
                    continuation.yield(.finish(.stop))
                    continuation.finish()
                }
            ),
        ])

        let provider = MockProvider(
            streamHandler: { _ in
                streamSequencer.next()
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [makeEchoTool()]
        )

        let toolStream = provider.streamWithTools(request)

        var streamEvents = 0
        var stepCompletes = 0
        var toolResults = 0
        var toolExecuting = 0

        for try await event in toolStream {
            switch event {
            case .streamEvent: streamEvents += 1
            case .stepComplete: stepCompletes += 1
            case .toolResult: toolResults += 1
            case .toolExecuting: toolExecuting += 1
            case .toolApprovalRequired: break
            }
        }

        #expect(streamEvents > 0)
        #expect(stepCompletes == 1)
        #expect(toolResults == 1)
        #expect(toolExecuting == 1)
    }

    // MARK: - 19. streamWithTools emits toolApprovalRequired before approval-gated execution

    @Test("streamWithTools emits toolApprovalRequired")
    func streamApprovalRequired() async throws {
        let approvalTool = AITool(
            name: "sensitive",
            description: "Needs approval",
            inputSchema: .object(properties: [:], required: []),
            needsApproval: true
        ) { _ in "executed" }

        let streamSequencer = StreamSequencer(streams: [
            AIStream(
                AsyncThrowingStream { continuation in
                    continuation.yield(.start(id: "s1", model: "mock"))
                    continuation.yield(.toolUseStart(id: "tc-1", name: "sensitive"))
                    continuation.yield(.delta(.toolInput(id: "tc-1", jsonDelta: "{}")))
                    continuation.yield(.usage(AIUsage(inputTokens: 5, outputTokens: 3)))
                    continuation.yield(.finish(.toolUse))
                    continuation.finish()
                }
            ),
            AIStream(
                AsyncThrowingStream { continuation in
                    continuation.yield(.start(id: "s2", model: "mock"))
                    continuation.yield(.delta(.text("done")))
                    continuation.yield(.finish(.stop))
                    continuation.finish()
                }
            ),
        ])

        let provider = MockProvider(
            streamHandler: { _ in
                streamSequencer.next()
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [approvalTool]
        )

        let toolStream = provider.streamWithTools(
            request,
            approvalHandler: { _ in true }
        )

        var sawApprovalRequired = false

        for try await event in toolStream {
            if case .toolApprovalRequired = event {
                sawApprovalRequired = true
            }
        }

        #expect(sawApprovalRequired)
    }

    @Test("streamWithTools preserves step warnings")
    func streamPreservesStepWarnings() async throws {
        let warning = AIProviderWarning(
            code: "tool-warning",
            message: "warning message",
            parameter: "tools"
        )

        let streamSequencer = StreamSequencer(streams: [
            AIStream(
                AsyncThrowingStream { continuation in
                    continuation.yield(.start(id: "s1", model: "mock"))
                    continuation.yield(.toolUseStart(id: "tc-1", name: "echo"))
                    continuation.yield(.delta(.toolInput(id: "tc-1", jsonDelta: "{\"text\":\"hi\"}")))
                    continuation.yield(.finish(.toolUse))
                    continuation.finish()
                },
                warnings: [warning]
            ),
            AIStream(
                AsyncThrowingStream { continuation in
                    continuation.yield(.start(id: "s2", model: "mock"))
                    continuation.yield(.finish(.stop))
                    continuation.finish()
                }
            ),
        ])

        let provider = MockProvider(
            streamHandler: { _ in
                streamSequencer.next()
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [makeEchoTool()]
        )

        var completedStep: AIToolStep?

        for try await event in provider.streamWithTools(request) {
            if case .stepComplete(let step) = event {
                completedStep = step
            }
        }

        #expect(completedStep?.response.warnings == [warning])
    }

    @Test("streamWithTools preserves specific AIError after partial output")
    func interruptedStreamPreservesSpecificError() async throws {
        let expectedError = AIError.serverError(statusCode: 503, message: "temporary failure")
        let streamSequencer = StreamSequencer(streams: [
            AIStream(
                AsyncThrowingStream { continuation in
                    continuation.yield(.start(id: "s1", model: "mock"))
                    continuation.yield(.toolUseStart(id: "tc-1", name: "echo"))
                    continuation.yield(.delta(.toolInput(id: "tc-1", jsonDelta: "{\"text\":\"a\"}")))
                    continuation.yield(.finish(.toolUse))
                    continuation.finish()
                }
            ),
            AIStream(
                AsyncThrowingStream { continuation in
                    continuation.yield(.start(id: "s2", model: "mock"))
                    continuation.yield(.delta(.text("partial")))
                    continuation.finish(throwing: expectedError)
                }
            ),
        ])

        let provider = MockProvider(
            streamHandler: { _ in
                streamSequencer.next()
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [makeEchoTool()]
        )

        var completedSteps = 0
        var caughtError: (any Error)?

        do {
            for try await event in provider.streamWithTools(request) {
                if case .stepComplete = event {
                    completedSteps += 1
                }
            }
        } catch {
            caughtError = error
        }

        #expect(completedSteps == 1)
        #expect(caughtError as? AIError == expectedError)
    }

    @Test("streamWithTools does not drop events for slow consumers")
    func streamDoesNotDropEventsForSlowConsumers() async throws {
        let eventCount = 96
        let streamSequencer = StreamSequencer(streams: [
            AIStream(
                AsyncThrowingStream { continuation in
                    continuation.yield(.start(id: "s1", model: "mock"))
                    for index in 0..<eventCount {
                        continuation.yield(.delta(.text("chunk-\(index)")))
                    }
                    continuation.yield(.toolUseStart(id: "tc-1", name: "echo"))
                    continuation.yield(.delta(.toolInput(id: "tc-1", jsonDelta: "{\"text\":\"hi\"}")))
                    continuation.yield(.finish(.toolUse))
                    continuation.finish()
                }
            ),
            AIStream(
                AsyncThrowingStream { continuation in
                    continuation.yield(.start(id: "s2", model: "mock"))
                    continuation.yield(.finish(.stop))
                    continuation.finish()
                }
            ),
        ])

        let provider = MockProvider(
            streamHandler: { _ in
                streamSequencer.next()
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [makeEchoTool()]
        )

        var streamEventCount = 0
        for try await event in provider.streamWithTools(request) {
            if case .streamEvent = event {
                streamEventCount += 1
                try await Task.sleep(nanoseconds: 1_000_000)
            }
        }

        #expect(streamEventCount == eventCount + 6)
    }

    // MARK: - 20. Cancellation stops active provider request and in-flight tools

    @Test("Cancellation stops active request")
    func cancellationStopsRequest() async throws {
        let toolStarted = ConditionFlag()

        let slowTool = AITool(
            name: "slow",
            description: "Takes a long time",
            inputSchema: .object(properties: [:], required: [])
        ) { _ in
            await toolStarted.set()
            try await Task.sleep(nanoseconds: 10_000_000_000)
            return "should not reach"
        }

        let provider = MockProvider(
            completionHandler: { _ in
                self.makeToolUseResponse(
                    toolCalls: [("tc-1", "slow", Data("{}".utf8))]
                )
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [slowTool]
        )

        let task = Task {
            try await provider.completeWithTools(request, stopWhen: [.maxSteps(5)])
        }

        await toolStarted.wait()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation error, but task completed normally")
        } catch is CancellationError {
            // Expected
        } catch {
            // Other errors acceptable — cancellation may surface as AIError.cancelled etc.
        }
    }

    @Test("Cancellation during approval does not commit a completed step")
    func cancellationDuringApprovalDoesNotCommitStep() async throws {
        let approvalCalled = ConditionFlag()
        let stepCounter = Counter()
        let recorder = MockProviderRecorder()

        let approvalTool = AITool(
            name: "sensitive",
            description: "Needs approval",
            inputSchema: .object(properties: [:], required: []),
            needsApproval: true
        ) { _ in "should not execute" }

        let provider = MockProvider(
            completionHandler: { _ in
                self.makeToolUseResponse(
                    toolCalls: [("tc-1", "sensitive", Data("{}".utf8))]
                )
            },
            recorder: recorder
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [approvalTool]
        )

        let task = Task {
            try await provider.completeWithTools(
                request,
                approvalHandler: { _ in
                    await approvalCalled.set()
                    while !Task.isCancelled {
                        await Task.yield()
                    }
                    return true
                },
                onStepComplete: { _ in
                    await stepCounter.incrementAndGet()
                }
            )
        }

        await approvalCalled.wait()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation error, but task completed normally")
        } catch {
            #expect((error as? AIError) == .cancelled || error is CancellationError)
        }

        #expect(await stepCounter.value == 0)
        #expect(await recorder.completeCalls.count == 1)
    }

    @Test("Cancellation during tool execution does not commit a completed step")
    func cancellationDuringToolExecutionDoesNotCommitStep() async throws {
        let toolStarted = ConditionFlag()
        let stepCounter = Counter()
        let recorder = MockProviderRecorder()

        let slowTool = AITool(
            name: "slow",
            description: "Takes a long time",
            inputSchema: .object(properties: [:], required: [])
        ) { _ in
            await toolStarted.set()
            try await Task.sleep(nanoseconds: 10_000_000_000)
            return "should not reach"
        }

        let provider = MockProvider(
            completionHandler: { _ in
                self.makeToolUseResponse(
                    toolCalls: [("tc-1", "slow", Data("{}".utf8))]
                )
            },
            recorder: recorder
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [slowTool]
        )

        let task = Task {
            try await provider.completeWithTools(
                request,
                onStepComplete: { _ in
                    await stepCounter.incrementAndGet()
                }
            )
        }

        await toolStarted.wait()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation error, but task completed normally")
        } catch {
            #expect((error as? AIError) == .cancelled || error is CancellationError)
        }

        #expect(await stepCounter.value == 0)
        #expect(await recorder.completeCalls.count == 1)
    }

    // MARK: - 21. No automatic retry after tool side effect

    @Test("No automatic retry after tool executed")
    func noRetryAfterToolExecution() async throws {
        let callCount = Counter()

        let provider = MockProvider(
            completionHandler: { request in
                let count = await callCount.incrementAndGet()
                if count == 1 {
                    return self.makeToolUseResponse(
                        toolCalls: [("tc-1", "echo", self.makeInput(["text": "x"]))]
                    )
                }
                throw AIError.serverError(statusCode: 500, message: "server error")
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [makeEchoTool()],
            retryPolicy: RetryPolicy(maxRetries: 3, initialDelay: 0.01, backoffMultiplier: 1.0, maxDelay: 0.1)
        )

        do {
            _ = try await provider.completeWithTools(request)
            Issue.record("Expected error")
        } catch {
            let totalCalls = await callCount.value
            #expect(totalCalls == 2)
        }
    }

    // MARK: - 22. onStepComplete fires once per completed step

    @Test("onStepComplete fires per step")
    func onStepCompleteFires() async throws {
        let callCount = Counter()
        let stepCounter = Counter()

        let provider = MockProvider(
            completionHandler: { _ in
                let count = await callCount.incrementAndGet()
                if count <= 2 {
                    return self.makeToolUseResponse(
                        toolCalls: [("tc-\(count)", "echo", self.makeInput(["text": "x"]))]
                    )
                }
                return self.makeFinalResponse()
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [makeEchoTool()]
        )

        let result = try await provider.completeWithTools(
            request,
            onStepComplete: { _ in
                await stepCounter.incrementAndGet()
            }
        )

        #expect(result.steps.count == 2)
        let stepCount = await stepCounter.value
        #expect(stepCount == 2)
    }

    @Test("AIToolResponse totalUsage preserves token detail accounting")
    func totalUsagePreservesTokenDetails() async throws {
        let callCount = Counter()

        let provider = MockProvider(
            completionHandler: { _ in
                let count = await callCount.incrementAndGet()
                switch count {
                case 1:
                    return AIResponse(
                        id: "resp-1",
                        content: [.toolUse(AIToolUse(id: "tc-1", name: "echo", input: self.makeInput(["text": "a"])))],
                        model: "mock-model",
                        usage: AIUsage(
                            inputTokens: 10,
                            outputTokens: 5,
                            inputTokenDetails: .init(cachedTokens: 2, cacheWriteTokens: 1),
                            outputTokenDetails: .init(reasoningTokens: 3)
                        ),
                        finishReason: .toolUse
                    )
                default:
                    return AIResponse(
                        id: "resp-2",
                        content: [.text("done")],
                        model: "mock-model",
                        usage: AIUsage(
                            inputTokens: 7,
                            outputTokens: 4,
                            inputTokenDetails: .init(cachedTokens: 1, cacheWriteTokens: 2),
                            outputTokenDetails: .init(reasoningTokens: 5)
                        ),
                        finishReason: .stop
                    )
                }
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [makeEchoTool()]
        )

        let result = try await provider.completeWithTools(request)

        #expect(result.totalUsage.inputTokens == 17)
        #expect(result.totalUsage.outputTokens == 9)
        #expect(result.totalUsage.inputTokenDetails?.cachedTokens == 3)
        #expect(result.totalUsage.inputTokenDetails?.cacheWriteTokens == 3)
        #expect(result.totalUsage.outputTokenDetails?.reasoningTokens == 8)
    }

    // MARK: - 23. AIToolStep.appendedMessages matches transcript replay order

    @Test("appendedMessages matches transcript replay order")
    func transcriptReplayOrder() async throws {
        let callCount = Counter()

        let provider = MockProvider(
            completionHandler: { _ in
                let count = await callCount.incrementAndGet()
                if count == 1 {
                    return self.makeToolUseResponse(
                        toolCalls: [
                            ("tc-1", "echo", self.makeInput(["text": "a"])),
                            ("tc-2", "echo", self.makeInput(["text": "b"])),
                        ]
                    )
                }
                return self.makeFinalResponse()
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [makeEchoTool()]
        )

        let result = try await provider.completeWithTools(request)
        let step = result.steps[0]

        #expect(step.appendedMessages.count == 3)

        let firstMsg = step.appendedMessages[0]
        #expect(firstMsg.role == .assistant)

        let toolUses = firstMsg.content.compactMap { content -> AIToolUse? in
            if case .toolUse(let tu) = content { return tu }
            return nil
        }
        #expect(toolUses.count == 2)

        #expect(step.appendedMessages[1].role == .tool)
        #expect(step.appendedMessages[2].role == .tool)

        if case .toolResult(let r1) = step.appendedMessages[1].content.first {
            #expect(r1.toolUseId == "tc-1")
        }
        if case .toolResult(let r2) = step.appendedMessages[2].content.first {
            #expect(r2.toolUseId == "tc-2")
        }
    }

    // MARK: - 24. Interrupted stitched streams surface streamInterrupted

    @Test("Interrupted stream surfaces streamInterrupted")
    func interruptedStream() async throws {
        let streamSequencer = StreamSequencer(streams: [
            AIStream(
                AsyncThrowingStream { continuation in
                    continuation.yield(.start(id: "s1", model: "mock"))
                    continuation.yield(.toolUseStart(id: "tc-1", name: "echo"))
                    continuation.yield(.delta(.toolInput(id: "tc-1", jsonDelta: "{\"text\":\"a\"}")))
                    continuation.yield(.usage(AIUsage(inputTokens: 5, outputTokens: 3)))
                    continuation.yield(.finish(.toolUse))
                    continuation.finish()
                }
            ),
            AIStream(
                AsyncThrowingStream { continuation in
                    continuation.yield(.start(id: "s2", model: "mock"))
                    continuation.yield(.delta(.text("partial...")))
                    continuation.finish()
                }
            ),
        ])

        let provider = MockProvider(
            streamHandler: { _ in
                streamSequencer.next()
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [makeEchoTool()]
        )

        let toolStream = provider.streamWithTools(request)

        var completedSteps = 0
        var caughtError: (any Error)?

        do {
            for try await event in toolStream {
                if case .stepComplete = event {
                    completedSteps += 1
                }
            }
        } catch {
            caughtError = error
        }

        #expect(completedSteps == 1)
        #expect(caughtError is AIError)
        if let aiError = caughtError as? AIError {
            #expect(aiError == .streamInterrupted)
        }
    }

    // MARK: - 25. Cancellation while waiting for approval stops without synthesizing denial

    @Test("Cancellation during approval stops without denial synthesis")
    func cancellationDuringApproval() async throws {
        let approvalCalled = ConditionFlag()

        let approvalTool = AITool(
            name: "sensitive",
            description: "Needs approval",
            inputSchema: .object(properties: [:], required: []),
            needsApproval: true
        ) { _ in "should not execute" }

        let provider = MockProvider(
            completionHandler: { _ in
                self.makeToolUseResponse(
                    toolCalls: [("tc-1", "sensitive", Data("{}".utf8))]
                )
            }
        )

        let request = AIRequest(
            model: AIModel("mock"),
            messages: [.user("test")],
            tools: [approvalTool]
        )

        let task = Task {
            try await provider.completeWithTools(
                request,
                approvalHandler: { _ in
                    await approvalCalled.set()
                    // Block until cancelled
                    while !Task.isCancelled {
                        await Task.yield()
                    }
                    return false
                }
            )
        }

        await approvalCalled.wait()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation error, but task completed normally")
        } catch is CancellationError {
            // Expected — cancellation during approval
        } catch {
            // Other errors acceptable — cancellation may surface as AIError.cancelled etc.
        }
    }
}

// MARK: - Test Helpers

private enum TestToolError: Error {
    case intentional
    case invalidInput
}

private struct WeatherInput: AIStructured {
    let city: String
}

private struct SimpleInput: AIStructured {
    let value: String
}

private struct IntInput: AIStructured {
    let value: Int
}

private struct ComputeOutput: Encodable, Sendable {
    let result: Int
    let label: String
}

/// Synchronous stream dispenser backed by an atomic index.
///
/// `streamHandler` in `MockProvider` is synchronous, so we cannot `await` inside it.
/// This class hands out pre-built streams in order using `OSAtomicIncrement32`.
private final class StreamSequencer: @unchecked Sendable {
    private let streams: [AIStream]
    private let lock = NSLock()
    private var index = 0

    init(streams: [AIStream]) {
        self.streams = streams
    }

    func next() -> AIStream {
        lock.lock()
        let current = index
        index += 1
        lock.unlock()
        guard current < streams.count else {
            return .finished(text: "fallback")
        }
        return streams[current]
    }
}

/// Thread-safe counter using an actor.
private actor Counter {
    private(set) var value: Int = 0

    @discardableResult
    func incrementAndGet() -> Int {
        value += 1
        return value
    }
}

/// A flag that can be set and waited on.
private actor ConditionFlag {
    private var isSet = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func set() {
        isSet = true
        for continuation in continuations {
            continuation.resume()
        }
        continuations.removeAll()
    }

    func wait() async {
        if isSet { return }
        await withCheckedContinuation { continuation in
            if isSet {
                continuation.resume()
            } else {
                continuations.append(continuation)
            }
        }
    }
}
