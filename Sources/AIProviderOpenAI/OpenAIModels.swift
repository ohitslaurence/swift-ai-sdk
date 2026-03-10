import AICore

extension AIModel {
    public enum GPT: Sendable {
        case gpt4o
        case gpt4oMini
        case custom(String)

        public var model: AIModel {
            switch self {
            case .gpt4o:
                return AIModel("gpt-4o", provider: "openai")
            case .gpt4oMini:
                return AIModel("gpt-4o-mini", provider: "openai")
            case .custom(let id):
                return AIModel(id, provider: "openai")
            }
        }
    }

    public enum OpenAIEmbedding: Sendable {
        case textEmbedding3Small
        case custom(String)

        public var model: AIModel {
            switch self {
            case .textEmbedding3Small:
                return AIModel("text-embedding-3-small", provider: "openai")
            case .custom(let id):
                return AIModel(id, provider: "openai")
            }
        }
    }

    public static func gpt(_ variant: GPT) -> AIModel {
        variant.model
    }

    public static func openAIEmbedding(_ variant: OpenAIEmbedding) -> AIModel {
        variant.model
    }
}
