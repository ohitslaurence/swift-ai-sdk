import AIProviderOpenAI
import XCTest

final class OpenAIProviderSmokeTests: XCTestCase {
    func test_availableModelsContainsEmbeddingModel() {
        let provider = OpenAIProvider(apiKey: "test")
        XCTAssertTrue(provider.availableModels.contains(where: { $0.id == "text-embedding-3-small" }))
    }
}
