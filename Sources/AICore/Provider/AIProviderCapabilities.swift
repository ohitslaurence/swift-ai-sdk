/// Provider-level capabilities used by higher-level AICore helpers.
public struct AIProviderCapabilities: Sendable, Equatable {
    public var instructions: AIInstructionCapabilities
    public var structuredOutput: AIStructuredOutputCapabilities
    public var inputs: AIInputCapabilities
    public var tools: AIToolCapabilities
    public var streaming: AIStreamingCapabilities
    public var embeddings: AIEmbeddingCapabilities

    public static let `default` = AIProviderCapabilities(
        instructions: .default,
        structuredOutput: .default,
        inputs: .default,
        tools: .default,
        streaming: .default,
        embeddings: .default
    )

    public init(
        instructions: AIInstructionCapabilities,
        structuredOutput: AIStructuredOutputCapabilities,
        inputs: AIInputCapabilities,
        tools: AIToolCapabilities,
        streaming: AIStreamingCapabilities,
        embeddings: AIEmbeddingCapabilities
    ) {
        self.instructions = instructions
        self.structuredOutput = structuredOutput
        self.inputs = inputs
        self.tools = tools
        self.streaming = streaming
        self.embeddings = embeddings
    }
}

/// Provider-level instruction handling behavior.
public struct AIInstructionCapabilities: Sendable, Equatable {
    public var defaultFormat: AIInstructionFormat
    public var reasoningModelFormatOverride: AIInstructionFormat?
    public var reasoningModelIDs: Set<AIModel>

    public static let `default` = AIInstructionCapabilities(
        defaultFormat: .message(role: .system),
        reasoningModelFormatOverride: nil,
        reasoningModelIDs: []
    )

    public init(
        defaultFormat: AIInstructionFormat,
        reasoningModelFormatOverride: AIInstructionFormat? = nil,
        reasoningModelIDs: Set<AIModel> = []
    ) {
        self.defaultFormat = defaultFormat
        self.reasoningModelFormatOverride = reasoningModelFormatOverride
        self.reasoningModelIDs = reasoningModelIDs
    }
}

/// The provider-specific format used to serialize top-level instructions.
public enum AIInstructionFormat: Sendable, Equatable {
    case topLevelSystemPrompt
    case message(role: AIInstructionRole)
}

/// The role used when serializing instructions as messages.
public enum AIInstructionRole: String, Sendable, Equatable, Codable {
    case system
    case developer
}

/// Structured-output support for a provider.
public struct AIStructuredOutputCapabilities: Sendable, Equatable {
    public var supportsJSONMode: Bool
    public var supportsJSONSchema: Bool
    public var defaultStrategy: AIStructuredOutputStrategy

    public static let `default` = AIStructuredOutputCapabilities(
        supportsJSONMode: false,
        supportsJSONSchema: false,
        defaultStrategy: .promptInjection
    )

    public init(
        supportsJSONMode: Bool,
        supportsJSONSchema: Bool,
        defaultStrategy: AIStructuredOutputStrategy
    ) {
        self.supportsJSONMode = supportsJSONMode
        self.supportsJSONSchema = supportsJSONSchema
        self.defaultStrategy = defaultStrategy
    }
}

/// The structured-output fallback strategy a provider prefers.
public enum AIStructuredOutputStrategy: Sendable, Equatable {
    case providerNative
    case toolCallFallback
    case promptInjection
}

/// Input media support advertised by a provider.
public struct AIInputCapabilities: Sendable, Equatable {
    public var supportsImages: Bool
    public var supportsDocuments: Bool
    public var supportedImageMediaTypes: Set<String>
    public var supportedDocumentMediaTypes: Set<String>

    public static let `default` = AIInputCapabilities(
        supportsImages: false,
        supportsDocuments: false,
        supportedImageMediaTypes: [],
        supportedDocumentMediaTypes: []
    )

    public init(
        supportsImages: Bool,
        supportsDocuments: Bool,
        supportedImageMediaTypes: Set<String> = [],
        supportedDocumentMediaTypes: Set<String> = []
    ) {
        self.supportsImages = supportsImages
        self.supportsDocuments = supportsDocuments
        self.supportedImageMediaTypes = supportedImageMediaTypes
        self.supportedDocumentMediaTypes = supportedDocumentMediaTypes
    }
}

/// Tool-use support advertised by a provider.
public struct AIToolCapabilities: Sendable, Equatable {
    public var supportsParallelCalls: Bool
    public var supportsForcedToolChoice: Bool

    public static let `default` = AIToolCapabilities(
        supportsParallelCalls: true,
        supportsForcedToolChoice: false
    )

    public init(supportsParallelCalls: Bool, supportsForcedToolChoice: Bool) {
        self.supportsParallelCalls = supportsParallelCalls
        self.supportsForcedToolChoice = supportsForcedToolChoice
    }
}

/// Streaming-specific provider behavior.
public struct AIStreamingCapabilities: Sendable, Equatable {
    public var includesUsageInStream: Bool

    public static let `default` = AIStreamingCapabilities(includesUsageInStream: false)

    public init(includesUsageInStream: Bool) {
        self.includesUsageInStream = includesUsageInStream
    }
}

/// Embedding-specific provider behavior.
public struct AIEmbeddingCapabilities: Sendable, Equatable {
    public var supportsEmbeddings: Bool
    public var supportedInputKinds: Set<AIEmbeddingInputKind>
    public var supportsBatchInputs: Bool
    public var supportsDimensionOverride: Bool
    public var maxInputsPerRequest: Int?

    public static let `default` = AIEmbeddingCapabilities(
        supportsEmbeddings: false,
        supportedInputKinds: [],
        supportsBatchInputs: false,
        supportsDimensionOverride: false,
        maxInputsPerRequest: nil
    )

    public init(
        supportsEmbeddings: Bool,
        supportedInputKinds: Set<AIEmbeddingInputKind>,
        supportsBatchInputs: Bool,
        supportsDimensionOverride: Bool,
        maxInputsPerRequest: Int? = nil
    ) {
        self.supportsEmbeddings = supportsEmbeddings
        self.supportedInputKinds = supportedInputKinds
        self.supportsBatchInputs = supportsBatchInputs
        self.supportsDimensionOverride = supportsDimensionOverride
        self.maxInputsPerRequest = maxInputsPerRequest
    }
}

/// The embedding input kinds supported by a provider.
public enum AIEmbeddingInputKind: String, Sendable, Hashable, Codable {
    case text
}
