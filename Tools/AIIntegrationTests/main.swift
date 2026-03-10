import AICore
import AIProviderOpenAI
import Foundation

guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty else {
    print("Usage: OPENAI_API_KEY=sk-... swift run AIIntegrationTests")
    print()
    print("Set the OPENAI_API_KEY environment variable to run integration tests.")
    exit(1)
}

let loggingTransport = LoggingTransport(wrapping: URLSessionTransport())
let provider = OpenAIProvider(apiKey: apiKey, transport: loggingTransport)

print("Swift AI SDK - Integration Tests")
print("Provider: OpenAI")
print("Default model: gpt-5-mini")
print(String(repeating: "=", count: 56))

let runner = TestRunner(provider: provider)
let results = await runner.runAll()

print()
print(String(repeating: "=", count: 56))
print("SUMMARY")
print(String(repeating: "=", count: 56))

let passed = results.filter(\.passed).count
let failed = results.filter { !$0.passed }.count

print("  Passed: \(passed)/\(results.count)")
print("  Failed: \(failed)/\(results.count)")

if failed > 0 {
    print()
    print("  Failures:")
    for result in results where !result.passed {
        print("    - \(result.name): \(result.message)")
    }
}

print()
exit(failed > 0 ? 1 : 0)
