import Foundation

/// A provider-neutral message content block.
public enum AIContent: Sendable, Codable, Equatable {
    case text(String)
    case image(AIImage)
    case document(AIDocument)
    case toolUse(AIToolUse)
    case toolResult(AIToolResult)
}

extension AIContent {
    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case image
        case document
        case toolUse
        case toolResult
    }

    private enum Kind: String, Codable {
        case text
        case image
        case document
        case toolUse
        case toolResult
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)

        switch kind {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .image:
            self = .image(try container.decode(AIImage.self, forKey: .image))
        case .document:
            self = .document(try container.decode(AIDocument.self, forKey: .document))
        case .toolUse:
            self = .toolUse(try container.decode(AIToolUse.self, forKey: .toolUse))
        case .toolResult:
            self = .toolResult(try container.decode(AIToolResult.self, forKey: .toolResult))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let value):
            try container.encode(Kind.text, forKey: .type)
            try container.encode(value, forKey: .text)
        case .image(let image):
            try container.encode(Kind.image, forKey: .type)
            try container.encode(image, forKey: .image)
        case .document(let document):
            try container.encode(Kind.document, forKey: .type)
            try container.encode(document, forKey: .document)
        case .toolUse(let toolUse):
            try container.encode(Kind.toolUse, forKey: .type)
            try container.encode(toolUse, forKey: .toolUse)
        case .toolResult(let toolResult):
            try container.encode(Kind.toolResult, forKey: .type)
            try container.encode(toolResult, forKey: .toolResult)
        }
    }
}
