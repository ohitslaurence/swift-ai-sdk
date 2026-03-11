import Foundation
import Testing

@testable import AICore
@testable import AITestSupport

// MARK: - Test Helpers

private func jsonSchemaCapabilities() -> AIProviderCapabilities {
    AIProviderCapabilities(
        instructions: .default,
        structuredOutput: AIStructuredOutputCapabilities(
            supportsJSONMode: false,
            supportsJSONSchema: true,
            defaultStrategy: .providerNative
        ),
        inputs: .default,
        tools: .default,
        streaming: .default,
        embeddings: .default
    )
}

private func jsonModeCapabilities() -> AIProviderCapabilities {
    AIProviderCapabilities(
        instructions: .default,
        structuredOutput: AIStructuredOutputCapabilities(
            supportsJSONMode: true,
            supportsJSONSchema: false,
            defaultStrategy: .providerNative
        ),
        inputs: .default,
        tools: .default,
        streaming: .default,
        embeddings: .default
    )
}

private actor CallCounter {
    var count = 0

    func increment() -> Int {
        count += 1
        return count
    }
}

private actor TaskStartSignal {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        started = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }

    func wait() async {
        if started { return }
        await withCheckedContinuation { continuation in
            if started {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }
}

private actor ContextCapture {
    var value: AIErrorContext?

    func set(_ ctx: AIErrorContext) {
        value = ctx
    }
}

// MARK: - Test Types

private struct FlatStruct: AIStructured, Equatable {
    let name: String
    let age: Int
    let score: Double
    let active: Bool
}

private struct NestedStruct: AIStructured, Equatable {
    let title: String
    let inner: Inner

    struct Inner: Codable, Sendable, Equatable {
        let value: Int
    }
}

private enum Color: String, Codable, CaseIterable, Sendable {
    case red
    case green
    case blue
}

private struct WithEnum: AIStructured, Equatable {
    let name: String
    let color: Color
}

private struct WithOptionals: AIStructured, Equatable {
    let required: String
    let optional: String?
}

private struct WithArray: AIStructured, Equatable {
    let items: [String]
    let count: Int
}

private struct WithCodingKeys: AIStructured, Equatable {
    let firstName: String
    let lastName: String

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

private struct WithDate: AIStructured, Equatable {
    let name: String
    let createdAt: Date
}

private struct ManualSchema: AIStructured, Equatable {
    let value: String

    static var jsonSchema: AIJSONSchema {
        .object(
            properties: ["value": .string(description: "A custom value")],
            required: ["value"]
        )
    }
}

private struct NamedSchemaStruct: AIStructured, Equatable {
    let required: String

    static var schemaName: String { "named_schema_v1" }
}

private struct ContainsDrivenDecoding: AIStructured, Equatable {
    let value: String

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.value) {
            value = try container.decode(String.self, forKey: .value)
        } else {
            value = "fallback"
        }
    }
}

private struct DecodeNilDrivenDecoding: AIStructured, Equatable {
    let value: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if try container.decodeNil(forKey: .value) {
            value = nil
        } else {
            value = "fallback"
        }
    }
}

private final class RequiredRecursiveNode: Codable {
    let child: RequiredRecursiveNode

    init(child: RequiredRecursiveNode) {
        self.child = child
    }
}

// MARK: - Schema Generation Tests

@Suite("Structured Output - Schema Generation")
struct SchemaGenerationTests {

    @Test("1. Simple flat struct schema generation")
    func flatStructSchema() throws {
        let schema = try FlatStruct.jsonSchema

        guard case .object(let properties, let required, _, _) = schema else {
            Issue.record("Expected object schema")
            return
        }

        #expect(properties.count == 4)
        #expect(properties["name"] == .string())
        #expect(properties["age"] == .integer())
        #expect(properties["score"] == .number())
        #expect(properties["active"] == .boolean())
        #expect(required.sorted() == ["active", "age", "name", "score"])
    }

    @Test("2. Nested struct schema generation")
    func nestedStructSchema() throws {
        let schema = try NestedStruct.jsonSchema

        guard case .object(let properties, let required, _, _) = schema else {
            Issue.record("Expected object schema")
            return
        }

        #expect(properties["title"] == .string())
        #expect(required.contains("title"))
        #expect(required.contains("inner"))

        guard case .object(let innerProps, let innerRequired, _, _) = properties["inner"] else {
            Issue.record("Expected nested object schema")
            return
        }

        #expect(innerProps["value"] == .integer())
        #expect(innerRequired == ["value"])
    }

    @Test("3. String-backed enum schema generation")
    func stringEnumSchema() throws {
        let schema = try WithEnum.jsonSchema

        guard case .object(let properties, _, _, _) = schema else {
            Issue.record("Expected object schema")
            return
        }

        guard case .string(_, let enumValues, _) = properties["color"] else {
            Issue.record("Expected string schema with enum values")
            return
        }

        #expect(enumValues?.sorted() == ["blue", "green", "red"])
    }

    @Test("4. Optional properties excluded from required")
    func optionalNotRequired() throws {
        let schema = try WithOptionals.jsonSchema

        guard case .object(_, let required, _, _) = schema else {
            Issue.record("Expected object schema")
            return
        }

        #expect(required.contains("required"))
        #expect(!required.contains("optional"))
    }

    @Test("5. Array properties generate array schemas")
    func arraySchema() throws {
        let schema = try WithArray.jsonSchema

        guard case .object(let properties, _, _, _) = schema else {
            Issue.record("Expected object schema")
            return
        }

        guard case .array(let items, _) = properties["items"] else {
            Issue.record("Expected array schema")
            return
        }

        #expect(items == .string())
    }

    @Test("6. CodingKeys are respected")
    func codingKeysRespected() throws {
        let schema = try WithCodingKeys.jsonSchema

        guard case .object(let properties, let required, _, _) = schema else {
            Issue.record("Expected object schema")
            return
        }

        #expect(properties["first_name"] == .string())
        #expect(properties["last_name"] == .string())
        #expect(properties["firstName"] == nil)
        #expect(properties["lastName"] == nil)
        #expect(required.sorted() == ["first_name", "last_name"])
    }

    @Test("7. Date fields generate string/date-time schemas")
    func dateSchema() throws {
        let schema = try WithDate.jsonSchema

        guard case .object(let properties, _, _, _) = schema else {
            Issue.record("Expected object schema")
            return
        }

        #expect(properties["createdAt"] == .string(format: "date-time"))
    }

    @Test("8. Unsupported reflected shapes throw .unsupportedFeature")
    func unsupportedShapeThrows() throws {
        enum AssociatedEnum: Codable, Sendable {
            case a(Int)
            case b(String)
        }

        #expect(throws: AIError.self) {
            try AIJSONSchemaGenerator.generateSchema(for: AssociatedEnum.self)
        }
    }

    @Test("9. Manual schema overrides replace auto-generation")
    func manualSchemaOverride() {
        let schema = ManualSchema.jsonSchema

        guard case .object(let properties, _, _, _) = schema else {
            Issue.record("Expected object schema")
            return
        }

        guard case .string(let description, _, _) = properties["value"] else {
            Issue.record("Expected string with description")
            return
        }

        #expect(description == "A custom value")
    }
}

@Suite("Structured Output - Unsupported Schema Shapes")
struct UnsupportedSchemaShapeTests {
    @Test("custom decoders using contains still infer matching keyed shapes")
    func containsDrivenDecodingSchema() throws {
        let schema = try ContainsDrivenDecoding.jsonSchema

        guard case .object(let properties, let required, _, _) = schema else {
            Issue.record("Expected object schema")
            return
        }

        #expect(properties["value"] == .string())
        #expect(required == ["value"])
    }

    @Test("custom decoders using decodeNil are rejected")
    func decodeNilDrivenDecodingThrows() {
        #expect(throws: AIError.self) {
            try DecodeNilDrivenDecoding.jsonSchema
        }
    }

    @Test("required recursive types are rejected")
    func requiredRecursiveTypeThrows() {
        #expect(throws: AIError.self) {
            try AIJSONSchemaGenerator.generateSchema(for: RequiredRecursiveNode.self)
        }
    }
}

// MARK: - Strategy Selection Tests

@Suite("Structured Output - Strategy Selection")
struct StrategySelectionTests {

    @Test("10. OpenAI-capable providers choose native JSON Schema strategy")
    func openAIStrategy() {
        let capabilities = AIStructuredOutputCapabilities(
            supportsJSONMode: true,
            supportsJSONSchema: true,
            defaultStrategy: .providerNative
        )

        let strategy = StructuredOutputGenerator.selectStrategy(capabilities: capabilities)
        #expect(strategy == .nativeJSONSchema)
    }

    @Test("11. Anthropic-capable providers choose native JSON Schema strategy")
    func anthropicStrategy() {
        let capabilities = AIStructuredOutputCapabilities(
            supportsJSONMode: false,
            supportsJSONSchema: true,
            defaultStrategy: .providerNative
        )

        let strategy = StructuredOutputGenerator.selectStrategy(capabilities: capabilities)
        #expect(strategy == .nativeJSONSchema)
    }

    @Test("12. Synthetic tool fallback selected when provider capabilities require it")
    func toolCallFallbackStrategy() {
        let capabilities = AIStructuredOutputCapabilities(
            supportsJSONMode: false,
            supportsJSONSchema: false,
            defaultStrategy: .toolCallFallback
        )

        let strategy = StructuredOutputGenerator.selectStrategy(capabilities: capabilities)
        #expect(strategy == .toolCallFallback)
    }

    @Test("13. Prompt-injection fallback selected when provider capabilities require it")
    func promptInjectionStrategy() {
        let capabilities = AIStructuredOutputCapabilities(
            supportsJSONMode: false,
            supportsJSONSchema: false,
            defaultStrategy: .promptInjection
        )

        let strategy = StructuredOutputGenerator.selectStrategy(capabilities: capabilities)
        #expect(strategy == .promptInjection)
    }

    @Test("14. Native JSON mode requires an explicit .json request")
    func nativeJSONModeRequiresExplicitRequest() {
        let capabilities = AIStructuredOutputCapabilities(
            supportsJSONMode: true,
            supportsJSONSchema: false,
            defaultStrategy: .providerNative
        )

        let implicitStrategy = StructuredOutputGenerator.selectStrategy(capabilities: capabilities)
        let explicitStrategy = StructuredOutputGenerator.selectStrategy(
            requestedResponseFormat: .json,
            capabilities: capabilities
        )

        #expect(implicitStrategy == .promptInjection)
        #expect(explicitStrategy == .nativeJSONMode)
    }
}

// MARK: - Repair Tests

@Suite("Structured Output - Repair")
struct RepairTests {

    @Test("15. Built-in repair strips Markdown fences")
    func stripMarkdownFences() {
        let input = """
            ```json
            {"name": "test", "age": 25}
            ```
            """
        let result = StructuredOutputRepair.stripMarkdownFences(input)
        #expect(result != nil)

        if let repaired = result, let data = repaired.data(using: .utf8) {
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(obj?["name"] as? String == "test")
        }
    }

    @Test("16. Built-in repair extracts JSON from surrounding prose")
    func extractJSONFromProse() {
        let input = """
            Here is the result:
            {"name": "test", "age": 25}
            I hope this helps!
            """
        let result = StructuredOutputRepair.attemptBuiltInRepair(input)
        #expect(result != nil)

        if let repaired = result, let data = repaired.data(using: .utf8) {
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(obj?["name"] as? String == "test")
        }
    }

    @Test("17. Custom repair receives AIErrorContext and can return repaired text")
    func customRepairHandler() async throws {
        let json = #"{"required": "hello"}"#
        let contextCapture = ContextCapture()

        let provider = MockProvider(
            completionHandler: { _ in
                AIResponse(
                    id: "test",
                    content: [.text("not json at all")],
                    model: "test-model"
                )
            },
            capabilities: jsonSchemaCapabilities()
        )

        let repair: AIRepairHandler = { _, errorContext in
            await contextCapture.set(errorContext)
            return json
        }

        let response = try await provider.generate(
            AIRequest(model: AIModel("test"), messages: [.user("test")]),
            schema: WithOptionals.self,
            maxRetries: 0,
            repair: repair
        )

        #expect(response.value.required == "hello")
        let captured = await contextCapture.value
        #expect(captured != nil)
    }
}

// MARK: - Retry Tests

@Suite("Structured Output - Retry")
struct RetryTests {

    @Test("18. Retry on invalid JSON succeeds on a later attempt")
    func retrySucceeds() async throws {
        let counter = CallCounter()
        let provider = MockProvider(
            completionHandler: { _ in
                let count = await counter.increment()
                if count == 1 {
                    return AIResponse(
                        id: "test-\(count)",
                        content: [.text("not json")],
                        model: "test-model"
                    )
                }
                return AIResponse(
                    id: "test-\(count)",
                    content: [
                        .text(#"{"name": "test", "age": 30, "score": 9.5, "active": true}"#)
                    ],
                    model: "test-model"
                )
            },
            capabilities: jsonSchemaCapabilities()
        )

        let response = try await provider.generate(
            "test",
            schema: FlatStruct.self,
            model: AIModel("test"),
            maxRetries: 2
        )

        #expect(response.value.name == "test")
        #expect(response.attempts == 2)
    }

    @Test("19. Exhausted retries throw .decodingError")
    func exhaustedRetriesThrow() async throws {
        let provider = MockProvider(
            completionHandler: { _ in
                AIResponse(
                    id: "test",
                    content: [.text("never valid json")],
                    model: "test-model"
                )
            },
            capabilities: jsonSchemaCapabilities()
        )

        await #expect(throws: AIError.self) {
            try await provider.generate(
                "test",
                schema: FlatStruct.self,
                model: AIModel("test"),
                maxRetries: 1
            )
        }
    }
}

// MARK: - Response Tests

@Suite("Structured Output - Response")
struct ResponseTests {

    @Test("20. AIStructuredResponse preserves raw AIResponse, warnings, and usage")
    func responsePreservation() async throws {
        let usage = AIUsage(inputTokens: 10, outputTokens: 20)
        let warning = AIProviderWarning(code: "test", message: "test warning", parameter: nil)

        let provider = MockProvider(
            completionHandler: { _ in
                AIResponse(
                    id: "test-id",
                    content: [.text(#"{"required": "value"}"#)],
                    model: "test-model",
                    usage: usage,
                    warnings: [warning]
                )
            },
            capabilities: jsonSchemaCapabilities()
        )

        let response = try await provider.generate(
            "test",
            schema: WithOptionals.self,
            model: AIModel("test")
        )

        #expect(response.response.id == "test-id")
        #expect(response.usage.inputTokens == 10)
        #expect(response.usage.outputTokens == 20)
        #expect(response.usage.totalTokens == 30)
        #expect(response.warnings.count == 1)
        #expect(response.warnings.first?.code == "test")
        #expect(response.attempts == 1)
    }

    @Test("21. Structured output aggregates usage and warnings across retries")
    func responseAggregationAcrossRetries() async throws {
        let counter = CallCounter()
        let firstWarning = AIProviderWarning(code: "first", message: "first warning")
        let secondWarning = AIProviderWarning(code: "second", message: "second warning")

        let provider = MockProvider(
            completionHandler: { _ in
                let count = await counter.increment()
                if count == 1 {
                    return AIResponse(
                        id: "attempt-1",
                        content: [.text("not json")],
                        model: "test-model",
                        usage: AIUsage(inputTokens: 10, outputTokens: 2),
                        warnings: [firstWarning]
                    )
                }

                return AIResponse(
                    id: "attempt-2",
                    content: [.text(#"{"required": "value"}"#)],
                    model: "test-model",
                    usage: AIUsage(inputTokens: 4, outputTokens: 3),
                    warnings: [secondWarning]
                )
            },
            capabilities: jsonSchemaCapabilities()
        )

        let response = try await provider.generate(
            "test",
            schema: WithOptionals.self,
            model: AIModel("test"),
            maxRetries: 1
        )

        #expect(response.response.id == "attempt-2")
        #expect(response.usage.inputTokens == 14)
        #expect(response.usage.outputTokens == 5)
        #expect(response.warnings == [firstWarning, secondWarning])
    }

    @Test("22. Structured output decodes ISO 8601 dates end to end")
    func structuredDateDecoding() async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expectedDate = try #require(formatter.date(from: "2025-03-11T10:21:00.123Z"))
        let provider = MockProvider(
            completionHandler: { _ in
                AIResponse(
                    id: "date-test",
                    content: [
                        .text(#"{"name":"release","createdAt":"2025-03-11T10:21:00.123Z"}"#)
                    ],
                    model: "test-model"
                )
            },
            capabilities: jsonSchemaCapabilities()
        )

        let response = try await provider.generate(
            "test",
            schema: WithDate.self,
            model: AIModel("test")
        )

        #expect(response.value.name == "release")
        #expect(response.value.createdAt == expectedDate)
    }

    @Test("23. JSON-mode-only providers require explicit JSON requests")
    func jsonModeOnlyProviderRequiresExplicitRequest() async throws {
        let recorder = MockProviderRecorder()
        let provider = MockProvider(
            completionHandler: { _ in
                AIResponse(
                    id: "json-mode",
                    content: [.text(#"{"required":"value"}"#)],
                    model: "test-model"
                )
            },
            capabilities: jsonModeCapabilities(),
            recorder: recorder
        )

        _ = try await provider.generate(
            "test",
            schema: WithOptionals.self,
            model: AIModel("test")
        )

        let implicitRequest = await recorder.completeCalls.last
        #expect(implicitRequest?.responseFormat == .text)
        #expect(implicitRequest?.systemPrompt?.contains("ONLY valid JSON matching this schema") == true)

        _ = try await provider.generate(
            AIRequest(
                model: AIModel("test"),
                messages: [.user("test")],
                responseFormat: .json
            ),
            schema: WithOptionals.self,
            maxRetries: 0
        )

        let calls = await recorder.completeCalls
        let explicitRequest = calls.last
        #expect(calls.count == 2)
        #expect(explicitRequest?.responseFormat == .json)
        #expect(explicitRequest?.systemPrompt == nil)
    }

    @Test("24. Structured output propagates schemaName into native schema requests")
    func structuredOutputPropagatesSchemaName() async throws {
        let recorder = MockProviderRecorder()
        let provider = MockProvider(
            completionHandler: { _ in
                AIResponse(
                    id: "named-schema",
                    content: [.text(#"{"required":"value"}"#)],
                    model: "test-model"
                )
            },
            capabilities: jsonSchemaCapabilities(),
            recorder: recorder
        )

        _ = try await provider.generate(
            "test",
            schema: NamedSchemaStruct.self,
            model: AIModel("test")
        )

        let request = await recorder.completeCalls.last
        #expect(
            request?.responseFormat
                == .jsonSchema(try NamedSchemaStruct.jsonSchema, name: NamedSchemaStruct.schemaName)
        )
    }
}

// MARK: - Cancellation Tests

@Suite("Structured Output - Cancellation")
struct CancellationTests {

    @Test("25. Cancellation during repair or retry aborts immediately with .cancelled")
    func cancellationAborts() async throws {
        let taskStarted = TaskStartSignal()

        let provider = MockProvider(
            completionHandler: { _ in
                await taskStarted.signal()
                try await Task.sleep(nanoseconds: 500_000_000)
                try Task.checkCancellation()
                return AIResponse(
                    id: "test",
                    content: [.text("not json")],
                    model: "test-model"
                )
            },
            capabilities: jsonSchemaCapabilities()
        )

        let task = Task {
            try await provider.generate(
                "test",
                schema: FlatStruct.self,
                model: AIModel("test"),
                maxRetries: 10
            )
        }

        await taskStarted.wait()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation error")
        } catch let error as AIError {
            switch error {
            case .cancelled:
                break
            default:
                Issue.record("Unexpected error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
