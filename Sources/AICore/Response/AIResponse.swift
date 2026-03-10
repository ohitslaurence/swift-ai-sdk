import Foundation

/// A provider-neutral response.
public struct AIResponse: Sendable, Codable, Equatable {
    public let id: String
    public let content: [AIContent]
    public let model: String
    public let usage: AIUsage
    public let finishReason: AIFinishReason
    public let warnings: [AIProviderWarning]

    public init(
        id: String,
        content: [AIContent],
        model: String,
        usage: AIUsage = AIUsage(inputTokens: 0, outputTokens: 0),
        finishReason: AIFinishReason = .stop,
        warnings: [AIProviderWarning] = []
    ) {
        self.id = id
        self.content = content
        self.model = model
        self.usage = usage
        self.finishReason = finishReason
        self.warnings = warnings
    }

    public var text: String {
        content.compactMap {
            if case .text(let value) = $0 {
                return value
            }
            return nil
        }.joined()
    }
}

/// The reason a response stopped.
public enum AIFinishReason: Sendable, Codable, Equatable {
    case stop
    case stopSequence(String?)
    case maxTokens
    case toolUse
    case contentFilter
    case refusal
    case pauseTurn
    case unknown(String)
}

extension AIFinishReason {
    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private enum Kind: String, Codable {
        case stop
        case stopSequence
        case maxTokens
        case toolUse
        case contentFilter
        case refusal
        case pauseTurn
        case unknown
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .stop:
            self = .stop
        case .stopSequence:
            self = .stopSequence(try container.decodeIfPresent(String.self, forKey: .value))
        case .maxTokens:
            self = .maxTokens
        case .toolUse:
            self = .toolUse
        case .contentFilter:
            self = .contentFilter
        case .refusal:
            self = .refusal
        case .pauseTurn:
            self = .pauseTurn
        case .unknown:
            self = .unknown(try container.decode(String.self, forKey: .value))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .stop:
            try container.encode(Kind.stop, forKey: .kind)
        case .stopSequence(let sequence):
            try container.encode(Kind.stopSequence, forKey: .kind)
            try container.encodeIfPresent(sequence, forKey: .value)
        case .maxTokens:
            try container.encode(Kind.maxTokens, forKey: .kind)
        case .toolUse:
            try container.encode(Kind.toolUse, forKey: .kind)
        case .contentFilter:
            try container.encode(Kind.contentFilter, forKey: .kind)
        case .refusal:
            try container.encode(Kind.refusal, forKey: .kind)
        case .pauseTurn:
            try container.encode(Kind.pauseTurn, forKey: .kind)
        case .unknown(let value):
            try container.encode(Kind.unknown, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }
}
