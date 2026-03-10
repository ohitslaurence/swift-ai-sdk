import AICore
import AIProviderOpenAI
import XCTest

final class OpenAIProviderSmokeTests: XCTestCase {
    func test_capabilitiesAdvertiseOpenAIFeatureSurface() {
        let provider = OpenAIProvider(apiKey: "test")

        XCTAssertTrue(provider.availableModels.contains(where: { $0.id == "text-embedding-3-small" }))
        XCTAssertTrue(provider.availableModels.contains(.gpt(.gpt5)))
        XCTAssertTrue(provider.capabilities.embeddings.supportsEmbeddings)
        XCTAssertEqual(provider.capabilities.instructions.reasoningModelFormatOverride, .message(role: .developer))
        XCTAssertTrue(provider.capabilities.instructions.reasoningModelIDs.contains(.gpt(.gpt5)))
        XCTAssertFalse(provider.capabilities.inputs.supportsDocuments)
    }
}
