import Foundation

/// A provider-neutral embeddings request.
public struct AIEmbeddingRequest: Sendable, Codable, Equatable {
    public var model: AIModel
    public var inputs: [AIEmbeddingInput]
    public var dimensions: Int?
    public var retryPolicy: RetryPolicy
    public var timeout: AITimeout
    public var headers: [String: String]

    public init(
        model: AIModel,
        inputs: [AIEmbeddingInput],
        dimensions: Int? = nil,
        retryPolicy: RetryPolicy = .default,
        timeout: AITimeout = .default,
        headers: [String: String] = [:]
    ) {
        self.model = model
        self.inputs = inputs
        self.dimensions = dimensions
        self.retryPolicy = retryPolicy
        self.timeout = timeout
        self.headers = headers
    }
}

/// A provider-neutral embedding input.
public enum AIEmbeddingInput: Sendable, Codable, Equatable {
    case text(String)
}

extension AIEmbeddingInput {
    private enum CodingKeys: String, CodingKey {
        case kind
        case text
    }

    private enum Kind: String, Codable {
        case text
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let value):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(value, forKey: .text)
        }
    }
}
