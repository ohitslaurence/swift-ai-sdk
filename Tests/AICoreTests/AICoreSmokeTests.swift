import AICore
import AITestSupport
import XCTest

final class AICoreSmokeTests: XCTestCase {
    func test_requestAndResponseCompile() async throws {
        let provider = MockProvider()
        let response = try await provider.complete(
            AIRequest(model: AIModel("mock"), messages: [.user("Hello")])
        )

        XCTAssertEqual(response.model, "mock")
    }

    func test_embeddingTypesCompile() async throws {
        let provider = MockProvider(
            capabilities: AIProviderCapabilities(supportsStreaming: true, supportsEmbeddings: true))
        let response = try await provider.embed(
            AIEmbeddingRequest(model: AIModel("embed"), inputs: [.text("swift")])
        )

        XCTAssertEqual(response.embeddings.count, 1)
    }
}
