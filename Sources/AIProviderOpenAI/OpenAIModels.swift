import AICore

extension AIModel {
    public enum GPT: Sendable {
        case gpt4o
        case gpt4oMini
        case gpt41
        case gpt41Mini
        case gpt41Nano
        case gpt5
        case gpt5Mini
        case gpt5Nano
        case o3
        case o3Mini
        case o4Mini
        case custom(String)

        public static var gpt4_1: Self { .gpt41 }
        public static var gpt4_1Mini: Self { .gpt41Mini }
        public static var gpt4_1Nano: Self { .gpt41Nano }

        public var model: AIModel {
            switch self {
            case .gpt4o:
                return AIModel("gpt-4o", provider: "openai")
            case .gpt4oMini:
                return AIModel("gpt-4o-mini", provider: "openai")
            case .gpt41:
                return AIModel("gpt-4.1", provider: "openai")
            case .gpt41Mini:
                return AIModel("gpt-4.1-mini", provider: "openai")
            case .gpt41Nano:
                return AIModel("gpt-4.1-nano", provider: "openai")
            case .gpt5:
                return AIModel("gpt-5", provider: "openai")
            case .gpt5Mini:
                return AIModel("gpt-5-mini", provider: "openai")
            case .gpt5Nano:
                return AIModel("gpt-5-nano", provider: "openai")
            case .o3:
                return AIModel("o3", provider: "openai")
            case .o3Mini:
                return AIModel("o3-mini", provider: "openai")
            case .o4Mini:
                return AIModel("o4-mini", provider: "openai")
            case .custom(let id):
                return AIModel(id, provider: "openai")
            }
        }
    }

    public enum OpenAIEmbedding: Sendable {
        case textEmbedding3Small
        case textEmbedding3Large
        case custom(String)

        public var model: AIModel {
            switch self {
            case .textEmbedding3Small:
                return AIModel("text-embedding-3-small", provider: "openai")
            case .textEmbedding3Large:
                return AIModel("text-embedding-3-large", provider: "openai")
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
