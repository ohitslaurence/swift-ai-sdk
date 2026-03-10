import AICore

extension AIModel {
    public enum Claude: Sendable {
        case sonnet45
        case haiku45
        case custom(String)

        public var model: AIModel {
            switch self {
            case .sonnet45:
                return AIModel("claude-sonnet-4-5", provider: "anthropic")
            case .haiku45:
                return AIModel("claude-haiku-4-5", provider: "anthropic")
            case .custom(let id):
                return AIModel(id, provider: "anthropic")
            }
        }
    }

    public static func claude(_ variant: Claude) -> AIModel {
        variant.model
    }
}
