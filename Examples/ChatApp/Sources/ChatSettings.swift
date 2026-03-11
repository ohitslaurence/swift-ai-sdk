import AICore
import AIProviderAnthropic
import AIProviderOpenAI
import AISwiftUI
import SwiftUI

enum ProviderOption: String, CaseIterable, Identifiable {
    case openai
    case anthropic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        }
    }

    var defaultModelID: String {
        switch self {
        case .openai: "gpt-4o"
        case .anthropic: "claude-sonnet-4-6"
        }
    }

    var chatModelIDs: [String] {
        switch self {
        case .openai:
            return [
                "gpt-4o",
                "gpt-4o-mini",
                "gpt-4.1",
                "gpt-4.1-mini",
                "gpt-4.1-nano",
                "o3-mini",
                "o4-mini",
            ]
        case .anthropic:
            return [
                "claude-sonnet-4-6",
                "claude-sonnet-4-5",
                "claude-haiku-4-5",
                "claude-opus-4-6",
            ]
        }
    }
}

@Observable
@MainActor
final class ChatSettings {
    var provider: ProviderOption = .anthropic
    var apiKey: String = ""
    var selectedModelID: String = ProviderOption.anthropic.defaultModelID

    var availableModelIDs: [String] { provider.chatModelIDs }

    func makeConversation() -> AIConversation {
        let aiProvider: any AIProvider = switch provider {
        case .openai:
            OpenAIProvider(apiKey: apiKey)
        case .anthropic:
            AnthropicProvider(apiKey: apiKey)
        }

        let model = AIModel(selectedModelID, provider: provider.rawValue)

        return AIConversation(
            provider: aiProvider,
            model: model,
            sendPolicy: .rejectWhileStreaming
        )
    }
}
