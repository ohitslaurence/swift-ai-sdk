import AICore
import Foundation

struct ScenarioResult: Sendable {
    let name: String
    let passed: Bool
    let message: String
}

/// Runs integration test scenarios against a provider and collects results.
struct TestRunner {
    let provider: any AIProvider
    let defaultModel: AIModel

    init(provider: any AIProvider, defaultModel: AIModel = AIModel("gpt-5-mini")) {
        self.provider = provider
        self.defaultModel = defaultModel
    }

    func runAll() async -> [ScenarioResult] {
        let scenarios: [(String, () async -> ScenarioResult)] = [
            ("Simple Completion", simpleCompletion),
            ("Streaming", streaming),
            ("System Prompt", systemPrompt),
            ("Reasoning Model System Prompt", reasoningModelSystemPrompt),
            ("JSON Mode", jsonMode),
            ("Tool Use", toolUse),
            ("Embeddings", embeddings),
            ("Batch Embeddings", batchEmbeddings),
            ("Streaming with Usage", streamingWithUsage),
            ("Error Handling", errorHandling),
        ]

        var results: [ScenarioResult] = []
        for (index, (name, scenario)) in scenarios.enumerated() {
            printScenarioHeader(index: index + 1, name: name, total: scenarios.count)
            let result = await scenario()
            results.append(result)
            printScenarioResult(result)
        }
        return results
    }

    // MARK: - Scenarios

    private func simpleCompletion() async -> ScenarioResult {
        do {
            let request = AIRequest(
                model: defaultModel,
                messages: [.user("Say hello in exactly 3 words")]
            )
            let response = try await provider.complete(request)
            let text = response.text
            let usage = response.usage
            let finish = response.finishReason
            print("  Response: \(text)")
            print("  Usage: \(usage.inputTokens) in / \(usage.outputTokens) out")
            print("  Finish reason: \(finish)")
            return ScenarioResult(name: "Simple Completion", passed: true, message: text)
        } catch {
            return ScenarioResult(name: "Simple Completion", passed: false, message: "\(error)")
        }
    }

    private func streaming() async -> ScenarioResult {
        do {
            let request = AIRequest(
                model: defaultModel,
                messages: [.user("Count from 1 to 5")]
            )
            let stream = provider.stream(request)

            print("  Deltas: ", terminator: "")
            var collectedText = ""
            for try await event in stream {
                if case .delta(.text(let text)) = event {
                    print(text, terminator: "")
                    collectedText += text
                }
            }
            print()
            print("  Collected: \(collectedText)")
            return ScenarioResult(name: "Streaming", passed: true, message: collectedText)
        } catch {
            return ScenarioResult(name: "Streaming", passed: false, message: "\(error)")
        }
    }

    private func systemPrompt() async -> ScenarioResult {
        do {
            let request = AIRequest(
                model: defaultModel,
                messages: [.user("Introduce yourself briefly")],
                systemPrompt: "You are a pirate"
            )
            let response = try await provider.complete(request)
            print("  Response: \(response.text)")
            print("  (Check logged request body for system message)")
            return ScenarioResult(name: "System Prompt", passed: true, message: response.text)
        } catch {
            return ScenarioResult(name: "System Prompt", passed: false, message: "\(error)")
        }
    }

    private func reasoningModelSystemPrompt() async -> ScenarioResult {
        do {
            let reasoningModel = AIModel("o3-mini")
            let request = AIRequest(
                model: reasoningModel,
                messages: [.user("Introduce yourself briefly")],
                systemPrompt: "You are a pirate"
            )
            let response = try await provider.complete(request)
            print("  Response: \(response.text)")
            print("  (Check logged request body for \"role\": \"developer\" instead of \"role\": \"system\")")
            return ScenarioResult(name: "Reasoning Model System Prompt", passed: true, message: response.text)
        } catch {
            return ScenarioResult(
                name: "Reasoning Model System Prompt", passed: false, message: "\(error)")
        }
    }

    private func jsonMode() async -> ScenarioResult {
        do {
            let request = AIRequest(
                model: defaultModel,
                messages: [.user("Return a JSON object with a key 'color' and value 'blue'")],
                responseFormat: .json
            )
            let response = try await provider.complete(request)
            let rawText = response.text
            print("  Raw response: \(rawText)")

            guard let data = rawText.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return ScenarioResult(name: "JSON Mode", passed: false, message: "Response is not valid JSON")
            }
            print("  Parsed JSON: \(json)")
            return ScenarioResult(name: "JSON Mode", passed: true, message: rawText)
        } catch {
            return ScenarioResult(name: "JSON Mode", passed: false, message: "\(error)")
        }
    }

    private func toolUse() async -> ScenarioResult {
        do {
            let weatherTool = AITool(
                name: "get_weather",
                description: "Get the current weather for a city",
                inputSchema: .object(
                    properties: [
                        "city": .string(description: "The city name")
                    ],
                    required: ["city"]
                ),
                handler: { _ in "sunny, 22C" }
            )
            let request = AIRequest(
                model: defaultModel,
                messages: [.user("What's the weather in London?")],
                tools: [weatherTool]
            )
            let response = try await provider.complete(request)
            print("  Finish reason: \(response.finishReason)")

            for content in response.content {
                if case .toolUse(let toolUse) = content {
                    print("  Tool call: \(toolUse.name)")
                    if let inputJSON = try? JSONSerialization.jsonObject(with: toolUse.input) {
                        print("  Tool input: \(inputJSON)")
                    }
                }
            }

            let hasToolUse = response.finishReason == .toolUse
            return ScenarioResult(
                name: "Tool Use",
                passed: hasToolUse,
                message: hasToolUse
                    ? "Tool call received"
                    : "Expected toolUse finish reason, got \(response.finishReason)"
            )
        } catch {
            return ScenarioResult(name: "Tool Use", passed: false, message: "\(error)")
        }
    }

    private func embeddings() async -> ScenarioResult {
        do {
            let embeddingModel = AIModel("text-embedding-3-small")
            let request = AIEmbeddingRequest(
                model: embeddingModel,
                inputs: [.text("hello world")]
            )
            let response = try await provider.embed(request)
            guard let embedding = response.embeddings.first else {
                return ScenarioResult(name: "Embeddings", passed: false, message: "No embedding returned")
            }
            print("  Vector length: \(embedding.dimensions)")
            let preview = embedding.vector.prefix(5).map { String(format: "%.6f", $0) }.joined(separator: ", ")
            print("  First 5 values: [\(preview)]")
            return ScenarioResult(name: "Embeddings", passed: true, message: "\(embedding.dimensions) dimensions")
        } catch {
            return ScenarioResult(name: "Embeddings", passed: false, message: "\(error)")
        }
    }

    private func batchEmbeddings() async -> ScenarioResult {
        do {
            let embeddingModel = AIModel("text-embedding-3-small")
            let request = AIEmbeddingRequest(
                model: embeddingModel,
                inputs: [.text("hello"), .text("world"), .text("test")]
            )
            let response = try await provider.embed(request)
            print("  Count: \(response.embeddings.count)")
            for embedding in response.embeddings {
                print("  Index \(embedding.index): \(embedding.dimensions) dimensions")
            }
            let passed = response.embeddings.count == 3
            return ScenarioResult(
                name: "Batch Embeddings",
                passed: passed,
                message: passed
                    ? "\(response.embeddings.count) embeddings"
                    : "Expected 3, got \(response.embeddings.count)"
            )
        } catch {
            return ScenarioResult(name: "Batch Embeddings", passed: false, message: "\(error)")
        }
    }

    private func streamingWithUsage() async -> ScenarioResult {
        do {
            let request = AIRequest(
                model: defaultModel,
                messages: [.user("Say hi")]
            )
            let stream = provider.stream(request)
            var gotUsage = false
            var usage: AIUsage?
            for try await event in stream {
                if case .usage(let u) = event {
                    gotUsage = true
                    usage = u
                }
            }
            if let usage {
                print("  Input tokens: \(usage.inputTokens)")
                print("  Output tokens: \(usage.outputTokens)")
                print("  Total tokens: \(usage.totalTokens)")
            }
            return ScenarioResult(
                name: "Streaming with Usage",
                passed: gotUsage,
                message: gotUsage ? "Usage event received" : "No usage event in stream"
            )
        } catch {
            return ScenarioResult(name: "Streaming with Usage", passed: false, message: "\(error)")
        }
    }

    private func errorHandling() async -> ScenarioResult {
        do {
            let request = AIRequest(
                model: AIModel("not-a-real-model-12345"),
                messages: [.user("Hello")]
            )
            let response = try await provider.complete(request)
            return ScenarioResult(
                name: "Error Handling",
                passed: false,
                message: "Expected error but got response: \(response.text)"
            )
        } catch let error as AIError {
            print("  Caught AIError: \(error)")
            return ScenarioResult(name: "Error Handling", passed: true, message: "AIError: \(error)")
        } catch {
            print("  Caught error: \(error)")
            return ScenarioResult(name: "Error Handling", passed: true, message: "Error: \(error)")
        }
    }

    // MARK: - Output Formatting

    private func printScenarioHeader(index: Int, name: String, total: Int) {
        print()
        let header = "[\(index)/\(total)] \(name)"
        print(String(repeating: "\u{2500}", count: 56))
        print(header)
        print(String(repeating: "\u{2500}", count: 56))
    }

    private func printScenarioResult(_ result: ScenarioResult) {
        let icon = result.passed ? "PASS" : "FAIL"
        print("  Result: \(icon)")
    }
}
