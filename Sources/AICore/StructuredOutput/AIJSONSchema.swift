/// A JSON Schema representation used for structured output and tool inputs.
public indirect enum AIJSONSchema: Sendable, Codable, Equatable {
    case string(description: String? = nil, enumValues: [String]? = nil, format: String? = nil)
    case number(description: String? = nil)
    case integer(description: String? = nil)
    case boolean(description: String? = nil)
    case object(
        properties: [String: AIJSONSchema],
        required: [String],
        additionalProperties: Bool = false,
        description: String? = nil
    )
    case array(items: AIJSONSchema, description: String? = nil)
    case oneOf([AIJSONSchema], description: String? = nil)
    case ref(String)
    case null

    public static var anyJSON: AIJSONSchema {
        .oneOf(
            [
                .string(),
                .number(),
                .integer(),
                .boolean(),
                .object(properties: [:], required: [], additionalProperties: true),
                .array(items: .ref("#")),
                .null,
            ]
        )
    }
}

extension AIJSONSchema {
    private enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
        case format
        case properties
        case required
        case additionalProperties
        case items
        case oneOf
        case ref = "$ref"
    }

    private enum SchemaType: String, Codable {
        case string
        case number
        case integer
        case boolean
        case object
        case array
        case null
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let ref = try container.decodeIfPresent(String.self, forKey: .ref) {
            self = .ref(ref)
            return
        }

        if let oneOf = try container.decodeIfPresent([AIJSONSchema].self, forKey: .oneOf) {
            self = .oneOf(oneOf, description: try container.decodeIfPresent(String.self, forKey: .description))
            return
        }

        let type = try container.decode(SchemaType.self, forKey: .type)
        switch type {
        case .string:
            self = .string(
                description: try container.decodeIfPresent(String.self, forKey: .description),
                enumValues: try container.decodeIfPresent([String].self, forKey: .enumValues),
                format: try container.decodeIfPresent(String.self, forKey: .format)
            )
        case .number:
            self = .number(description: try container.decodeIfPresent(String.self, forKey: .description))
        case .integer:
            self = .integer(description: try container.decodeIfPresent(String.self, forKey: .description))
        case .boolean:
            self = .boolean(description: try container.decodeIfPresent(String.self, forKey: .description))
        case .object:
            self = .object(
                properties: try container.decodeIfPresent([String: AIJSONSchema].self, forKey: .properties) ?? [:],
                required: try container.decodeIfPresent([String].self, forKey: .required) ?? [],
                additionalProperties: try container.decodeIfPresent(Bool.self, forKey: .additionalProperties) ?? false,
                description: try container.decodeIfPresent(String.self, forKey: .description)
            )
        case .array:
            self = .array(
                items: try container.decode(AIJSONSchema.self, forKey: .items),
                description: try container.decodeIfPresent(String.self, forKey: .description)
            )
        case .null:
            self = .null
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .string(let description, let enumValues, let format):
            try container.encode(SchemaType.string, forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encodeIfPresent(enumValues, forKey: .enumValues)
            try container.encodeIfPresent(format, forKey: .format)
        case .number(let description):
            try container.encode(SchemaType.number, forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
        case .integer(let description):
            try container.encode(SchemaType.integer, forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
        case .boolean(let description):
            try container.encode(SchemaType.boolean, forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
        case .object(let properties, let required, let additionalProperties, let description):
            try container.encode(SchemaType.object, forKey: .type)
            try container.encode(properties, forKey: .properties)
            try container.encode(required, forKey: .required)
            try container.encode(additionalProperties, forKey: .additionalProperties)
            try container.encodeIfPresent(description, forKey: .description)
        case .array(let items, let description):
            try container.encode(SchemaType.array, forKey: .type)
            try container.encode(items, forKey: .items)
            try container.encodeIfPresent(description, forKey: .description)
        case .oneOf(let schemas, let description):
            try container.encode(schemas, forKey: .oneOf)
            try container.encodeIfPresent(description, forKey: .description)
        case .ref(let ref):
            try container.encode(ref, forKey: .ref)
        case .null:
            try container.encode(SchemaType.null, forKey: .type)
        }
    }
}
