/// A provider-neutral tool choice directive.
public enum AIToolChoice: Sendable, Codable, Equatable {
    case auto
    case required
    case none
    case tool(String)
}

extension AIToolChoice {
    private enum CodingKeys: String, CodingKey {
        case kind
        case name
    }

    private enum Kind: String, Codable {
        case auto
        case required
        case none
        case tool
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .auto:
            self = .auto
        case .required:
            self = .required
        case .none:
            self = .none
        case .tool:
            self = .tool(try container.decode(String.self, forKey: .name))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .auto:
            try container.encode(Kind.auto, forKey: .kind)
        case .required:
            try container.encode(Kind.required, forKey: .kind)
        case .none:
            try container.encode(Kind.none, forKey: .kind)
        case .tool(let name):
            try container.encode(Kind.tool, forKey: .kind)
            try container.encode(name, forKey: .name)
        }
    }
}
