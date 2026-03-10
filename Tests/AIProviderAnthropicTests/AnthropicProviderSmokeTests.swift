import AICore
import AIProviderAnthropic
import XCTest

final class AnthropicProviderSmokeTests: XCTestCase {
    func test_capabilitiesAdvertiseAnthropicFeatureSurface() {
        let provider = AnthropicProvider(apiKey: "test")

        XCTAssertFalse(provider.availableModels.isEmpty)
        XCTAssertTrue(provider.capabilities.inputs.supportsImages)
        XCTAssertTrue(provider.capabilities.inputs.supportsDocuments)
        XCTAssertTrue(provider.capabilities.structuredOutput.supportsJSONSchema)
        XCTAssertEqual(provider.capabilities.instructions.defaultFormat, .topLevelSystemPrompt)
        XCTAssertFalse(provider.capabilities.embeddings.supportsEmbeddings)
    }
}
