/// A provider-neutral response format request.
public enum AIResponseFormat: Sendable, Codable, Equatable {
    case text
    case json
    case jsonSchema(AIJSONSchema, name: String? = nil)
}

extension AIResponseFormat {
    private enum CodingKeys: String, CodingKey {
        case kind
        case schema
        case schemaName
    }

    private enum Kind: String, Codable {
        case text
        case json
        case jsonSchema
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .text:
            self = .text
        case .json:
            self = .json
        case .jsonSchema:
            self = .jsonSchema(
                try container.decode(AIJSONSchema.self, forKey: .schema),
                name: try container.decodeIfPresent(String.self, forKey: .schemaName)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text:
            try container.encode(Kind.text, forKey: .kind)
        case .json:
            try container.encode(Kind.json, forKey: .kind)
        case .jsonSchema(let schema, let name):
            try container.encode(Kind.jsonSchema, forKey: .kind)
            try container.encode(schema, forKey: .schema)
            try container.encodeIfPresent(name, forKey: .schemaName)
        }
    }
}
