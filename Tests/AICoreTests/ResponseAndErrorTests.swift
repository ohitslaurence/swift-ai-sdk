import AICore
import Foundation
import XCTest

final class ResponseAndErrorTests: XCTestCase {
    func test_responseText_concatenatesOnlyTextBlocks() {
        let response = AIResponse(
            id: "resp_1",
            content: [
                .text("Hello"),
                .toolUse(AIToolUse(id: "tool-1", name: "weather", input: Data("{}".utf8))),
                .text(" world"),
            ],
            model: "gpt-4o",
            usage: AIUsage(inputTokens: 3, outputTokens: 2),
            finishReason: .toolUse
        )

        XCTAssertEqual(response.text, "Hello world")
    }

    func test_response_roundTripsWithDocumentWarningsAndFinishReason() throws {
        let document = AIDocument(data: Data("report".utf8), mediaType: .plainText, filename: "report.txt")
        let response = AIResponse(
            id: "resp_2",
            content: [
                .document(document),
                .text("done"),
                .toolResult(AIToolResult(toolUseId: "tool-1", content: "ok")),
            ],
            model: "claude-sonnet-4-5",
            usage: AIUsage(
                inputTokens: 10,
                outputTokens: 4,
                inputTokenDetails: AIUsage.InputTokenDetails(cachedTokens: 2, cacheWriteTokens: 1),
                outputTokenDetails: AIUsage.OutputTokenDetails(reasoningTokens: 3)
            ),
            finishReason: .stopSequence("END"),
            warnings: [
                AIProviderWarning(
                    code: "stop_unsupported", message: "Dropped stop sequence", parameter: "stopSequences")
            ]
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(AIResponse.self, from: data)

        XCTAssertEqual(decoded, response)
        XCTAssertEqual(decoded.usage.totalTokens, 14)
    }

    func test_aiErrorDescriptions_preserveAssociatedContext() {
        let networkError = AIError.networkError(
            AIErrorContext(message: "Socket closed", underlyingType: "URLError")
        )
        let timeout = AIError.timeout(.chunk)
        let retries = AIError.maxRetriesExceeded(
            attempts: 3,
            lastError: AIErrorContext(message: "Rate limited")
        )

        XCTAssertEqual(networkError.errorDescription, "Socket closed")
        XCTAssertEqual(timeout.errorDescription, "The operation exceeded the configured chunk timeout.")
        XCTAssertEqual(retries.errorDescription, "The operation failed after 3 attempt(s). Last error: Rate limited")
    }

    func test_model_hashability_distinguishesProvider() {
        let first = AIModel("same-id", provider: "openai")
        let second = AIModel("same-id", provider: "anthropic")
        let duplicate = AIModel("same-id", provider: "openai")
        let models: Set<AIModel> = [first, second, duplicate]

        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(first, duplicate)
        XCTAssertNotEqual(first, second)
    }
}
