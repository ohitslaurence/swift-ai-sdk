import AICore
import Foundation

struct AnthropicResponseParser {
    func parse(_ data: Data, warnings: [AIProviderWarning] = []) throws -> AIResponse {
        do {
            let response = try JSONDecoder().decode(AnthropicMessageResponse.self, from: data)

            return AIResponse(
                id: response.id,
                content: try response.content.map { try $0.aiContent() },
                model: response.model,
                usage: response.usage.aiUsage(),
                finishReason: AnthropicFinishReasonMapper.map(
                    stopReason: response.stopReason,
                    stopSequence: response.stopSequence
                ),
                warnings: warnings
            )
        } catch let error as AIError {
            throw error
        } catch {
            throw AIError.decodingError(AIErrorContext(error))
        }
    }
}

struct AnthropicUsagePayload: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }

    func aiUsage(
        defaultInputTokens: Int = 0,
        defaultInputTokenDetails: AIUsage.InputTokenDetails? = nil
    ) -> AIUsage {
        AIUsage(
            inputTokens: inputTokens ?? defaultInputTokens,
            outputTokens: outputTokens ?? 0,
            inputTokenDetails: inputTokenDetails ?? defaultInputTokenDetails
        )
    }

    var inputTokenDetails: AIUsage.InputTokenDetails? {
        guard cacheCreationInputTokens != nil || cacheReadInputTokens != nil else {
            return nil
        }

        return AIUsage.InputTokenDetails(
            cachedTokens: cacheReadInputTokens,
            cacheWriteTokens: cacheCreationInputTokens
        )
    }
}

enum AnthropicFinishReasonMapper {
    static func map(stopReason: String?, stopSequence: String?) -> AIFinishReason {
        switch stopReason {
        case nil, "end_turn":
            return .stop
        case "stop_sequence":
            return .stopSequence(stopSequence)
        case "max_tokens":
            return .maxTokens
        case "tool_use":
            return .toolUse
        case "pause_turn":
            return .pauseTurn
        case "refusal":
            return .refusal
        case let reason?:
            return .unknown(reason)
        }
    }
}

enum AnthropicJSONValue: Sendable, Codable {
    case string(String)
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case object([String: AnthropicJSONValue])
    case array([AnthropicJSONValue])
    case null

    init(any value: Any) throws {
        switch value {
        case let string as String:
            self = .string(string)
        case let bool as Bool:
            self = .bool(bool)
        case let int as Int:
            self = .integer(int)
        case let double as Double:
            self = .number(double)
        case let number as NSNumber:
            let doubleValue = number.doubleValue

            if doubleValue.rounded(.towardZero) == doubleValue {
                self = .integer(number.intValue)
            } else {
                self = .number(doubleValue)
            }
        case let object as [String: Any]:
            self = .object(try object.mapValues { try AnthropicJSONValue(any: $0) })
        case let array as [Any]:
            self = .array(try array.map { try AnthropicJSONValue(any: $0) })
        case _ as NSNull:
            self = .null
        default:
            throw AIError.invalidRequest("Anthropic JSON values must be valid JSON")
        }
    }

    func asData() throws -> Data {
        try JSONEncoder().encode(self)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: AnthropicJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([AnthropicJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported Anthropic JSON value")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

private struct AnthropicMessageResponse: Decodable {
    let id: String
    let model: String
    let content: [AnthropicResponseContentBlock]
    let stopReason: String?
    let stopSequence: String?
    let usage: AnthropicUsagePayload

    enum CodingKeys: String, CodingKey {
        case id
        case model
        case content
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
        case usage
    }
}

private struct AnthropicResponseContentBlock: Decodable {
    let type: String
    let text: String?
    let id: String?
    let name: String?
    let input: AnthropicJSONValue?

    func aiContent() throws -> AIContent {
        switch type {
        case "text":
            return .text(text ?? "")
        case "tool_use":
            guard let id, let name else {
                throw AIError.decodingError(
                    AIErrorContext(message: "Anthropic tool_use blocks must include an id and name")
                )
            }

            return .toolUse(
                AIToolUse(
                    id: id,
                    name: name,
                    input: try (input ?? .object([:])).asData()
                )
            )
        default:
            throw AIError.decodingError(
                AIErrorContext(message: "Unsupported Anthropic content block type: \(type)")
            )
        }
    }
}
