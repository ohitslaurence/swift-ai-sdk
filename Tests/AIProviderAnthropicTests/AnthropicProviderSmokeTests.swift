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

    func test_claudeModelVariantsResolveToCurrentIDs() {
        XCTAssertEqual(AIModel.claude(.haiku45), AIModel("claude-haiku-4-5", provider: "anthropic"))
        XCTAssertEqual(AIModel.claude(.sonnet45), AIModel("claude-sonnet-4-5", provider: "anthropic"))
        XCTAssertEqual(AIModel.claude(.sonnet46), AIModel("claude-sonnet-4-6", provider: "anthropic"))
        XCTAssertEqual(AIModel.claude(.opus46), AIModel("claude-opus-4-6", provider: "anthropic"))
        XCTAssertEqual(AIModel.claude(.haiku4_5), AIModel("claude-haiku-4-5", provider: "anthropic"))
        XCTAssertEqual(AIModel.claude(.sonnet4_5), AIModel("claude-sonnet-4-5", provider: "anthropic"))
        XCTAssertEqual(AIModel.claude(.sonnet4_6), AIModel("claude-sonnet-4-6", provider: "anthropic"))
        XCTAssertEqual(AIModel.claude(.opus4_6), AIModel("claude-opus-4-6", provider: "anthropic"))
        XCTAssertEqual(
            AIModel.claude(.custom("claude-custom-deployment")),
            AIModel("claude-custom-deployment", provider: "anthropic")
        )
    }
}
