import AICore
import AIProviderOpenAI
import XCTest

final class OpenAIProviderSmokeTests: XCTestCase {
    func test_capabilitiesAdvertiseOpenAIFeatureSurface() {
        let provider = OpenAIProvider(apiKey: "test")

        XCTAssertTrue(provider.availableModels.contains(where: { $0.id == "text-embedding-3-small" }))
        XCTAssertTrue(provider.availableModels.contains(.gpt(.gpt5)))
        XCTAssertTrue(provider.capabilities.structuredOutput.supportsJSONMode)
        XCTAssertTrue(provider.capabilities.structuredOutput.supportsJSONSchema)
        XCTAssertEqual(provider.capabilities.structuredOutput.defaultStrategy, .providerNative)
        XCTAssertTrue(provider.capabilities.tools.supportsParallelCalls)
        XCTAssertTrue(provider.capabilities.tools.supportsForcedToolChoice)
        XCTAssertTrue(provider.capabilities.streaming.includesUsageInStream)
        XCTAssertTrue(provider.capabilities.embeddings.supportsEmbeddings)
        XCTAssertEqual(provider.capabilities.embeddings.supportedInputKinds, [.text])
        XCTAssertTrue(provider.capabilities.embeddings.supportsBatchInputs)
        XCTAssertTrue(provider.capabilities.embeddings.supportsDimensionOverride)
        XCTAssertNil(provider.capabilities.embeddings.maxInputsPerRequest)
        XCTAssertEqual(provider.capabilities.instructions.reasoningModelFormatOverride, .message(role: .developer))
        XCTAssertTrue(provider.capabilities.instructions.reasoningModelIDs.contains(.gpt(.gpt5)))
        XCTAssertTrue(provider.capabilities.inputs.supportsImages)
        XCTAssertFalse(provider.capabilities.inputs.supportsDocuments)
        XCTAssertEqual(
            Set(provider.capabilities.inputs.supportedImageMediaTypes),
            ["image/gif", "image/jpeg", "image/png", "image/webp"]
        )
        XCTAssertTrue(provider.capabilities.inputs.supportedDocumentMediaTypes.isEmpty)
    }

    func test_gptModelAliasesResolveToCurrentIDs() {
        XCTAssertEqual(AIModel.gpt(.gpt4_1).id, "gpt-4.1")
        XCTAssertEqual(AIModel.gpt(.gpt4_1Mini).id, "gpt-4.1-mini")
        XCTAssertEqual(AIModel.gpt(.gpt4_1Nano).id, "gpt-4.1-nano")
    }
}
