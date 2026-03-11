import AICore

extension AIModel {
    public enum Claude: Sendable {
        case opus4
        case opus41
        case opus45
        case opus46
        case sonnet4
        case sonnet45
        case sonnet46
        case haiku45
        case custom(String)

        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static var opus4_1: Self { .opus41 }
        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static var opus4_5: Self { .opus45 }
        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static var opus4_6: Self { .opus46 }
        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static var sonnet4_5: Self { .sonnet45 }
        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static var sonnet4_6: Self { .sonnet46 }
        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static var haiku4_5: Self { .haiku45 }

        public var model: AIModel {
            switch self {
            case .opus4:
                return AIModel("claude-opus-4", provider: "anthropic")
            case .opus41:
                return AIModel("claude-opus-4-1", provider: "anthropic")
            case .opus45:
                return AIModel("claude-opus-4-5", provider: "anthropic")
            case .opus46:
                return AIModel("claude-opus-4-6", provider: "anthropic")
            case .sonnet4:
                return AIModel("claude-sonnet-4", provider: "anthropic")
            case .sonnet45:
                return AIModel("claude-sonnet-4-5", provider: "anthropic")
            case .sonnet46:
                return AIModel("claude-sonnet-4-6", provider: "anthropic")
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
