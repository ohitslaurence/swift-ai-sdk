import AIProviderAnthropic
import XCTest

final class AnthropicProviderSmokeTests: XCTestCase {
    func test_availableModelsIsNotEmpty() {
        let provider = AnthropicProvider(apiKey: "test")
        XCTAssertFalse(provider.availableModels.isEmpty)
    }
}
