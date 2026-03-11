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
        case gpt5Pro
        case gpt51
        case gpt52
        case gpt52Pro
        case gpt54
        case gpt54Pro
        case gpt5Codex
        case gpt51Codex
        case gpt51CodexMini
        case gpt51CodexMax
        case gpt52Codex
        case gpt53Codex
        case gpt53CodexSpark
        case o1
        case o1Mini
        case o1Pro
        case o3
        case o3Mini
        case o3Pro
        case o4Mini
        case custom(String)

        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static var gpt4_1: Self { .gpt41 }
        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static var gpt4_1Mini: Self { .gpt41Mini }
        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static var gpt4_1Nano: Self { .gpt41Nano }
        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static var gpt5_1: Self { .gpt51 }
        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static var gpt5_2: Self { .gpt52 }
        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static var gpt5_2Pro: Self { .gpt52Pro }
        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static var gpt5_4: Self { .gpt54 }
        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static var gpt5_4Pro: Self { .gpt54Pro }
        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static var gpt5_1Codex: Self { .gpt51Codex }
        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static var gpt5_1CodexMini: Self { .gpt51CodexMini }
        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static var gpt5_1CodexMax: Self { .gpt51CodexMax }
        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static var gpt5_2Codex: Self { .gpt52Codex }
        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static var gpt5_3Codex: Self { .gpt53Codex }
        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static var gpt5_3CodexSpark: Self { .gpt53CodexSpark }

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
            case .gpt5Pro:
                return AIModel("gpt-5-pro", provider: "openai")
            case .gpt51:
                return AIModel("gpt-5.1", provider: "openai")
            case .gpt52:
                return AIModel("gpt-5.2", provider: "openai")
            case .gpt52Pro:
                return AIModel("gpt-5.2-pro", provider: "openai")
            case .gpt54:
                return AIModel("gpt-5.4", provider: "openai")
            case .gpt54Pro:
                return AIModel("gpt-5.4-pro", provider: "openai")
            case .gpt5Codex:
                return AIModel("gpt-5-codex", provider: "openai")
            case .gpt51Codex:
                return AIModel("gpt-5.1-codex", provider: "openai")
            case .gpt51CodexMini:
                return AIModel("gpt-5.1-codex-mini", provider: "openai")
            case .gpt51CodexMax:
                return AIModel("gpt-5.1-codex-max", provider: "openai")
            case .gpt52Codex:
                return AIModel("gpt-5.2-codex", provider: "openai")
            case .gpt53Codex:
                return AIModel("gpt-5.3-codex", provider: "openai")
            case .gpt53CodexSpark:
                return AIModel("gpt-5.3-codex-spark", provider: "openai")
            case .o1:
                return AIModel("o1", provider: "openai")
            case .o1Mini:
                return AIModel("o1-mini", provider: "openai")
            case .o1Pro:
                return AIModel("o1-pro", provider: "openai")
            case .o3:
                return AIModel("o3", provider: "openai")
            case .o3Mini:
                return AIModel("o3-mini", provider: "openai")
            case .o3Pro:
                return AIModel("o3-pro", provider: "openai")
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
