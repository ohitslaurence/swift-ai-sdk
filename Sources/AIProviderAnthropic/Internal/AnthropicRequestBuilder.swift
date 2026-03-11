import AICore
import Foundation

struct AnthropicRequestBuilder {
    private static let apiVersion = "2023-06-01"
    private static let defaultBaseURL: URL = {
        guard let url = URL(string: "https://api.anthropic.com") else {
            preconditionFailure("Anthropic base URL must be valid")
        }

        return url
    }()
    private static let defaultMaxTokens = 4_096

    private let apiKey: String
    private let configuration: AIProviderHTTPConfiguration

    init(apiKey: String, configuration: AIProviderHTTPConfiguration) {
        self.apiKey = apiKey
        self.configuration = configuration
    }

    func prepareRequest(for request: AIRequest, stream: Bool) throws -> AnthropicPreparedRequest {
        let normalizedResponseFormat = normalizedResponseFormat(for: request.responseFormat)
        let warnings = validationWarnings(for: request, normalizedResponseFormat: normalizedResponseFormat)
        let outputConfig = outputConfig(for: normalizedResponseFormat)
        let tools = request.tools.isEmpty ? nil : request.tools.map(toolPayload(from:))
        let toolChoice = try toolChoice(for: request)

        var urlRequest = URLRequest(url: endpointURL())
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = try JSONEncoder().encode(
            AnthropicRequestPayload(
                model: request.model.id,
                messages: try request.messages.map(messagePayload(from:)),
                system: request.systemPrompt,
                maxTokens: request.maxTokens ?? Self.defaultMaxTokens,
                temperature: request.temperature,
                topP: request.topP,
                stopSequences: request.stopSequences.isEmpty ? nil : request.stopSequences,
                metadata: request.metadata.isEmpty ? nil : request.metadata,
                stream: stream,
                tools: tools,
                toolChoice: toolChoice,
                outputConfig: outputConfig
            )
        )

        var headers = configuration.defaultHeaders
        headers.merge(request.headers) { _, new in new }
        headers["X-Api-Key"] = apiKey
        headers["anthropic-version"] = Self.apiVersion
        headers["content-type"] = "application/json"

        for (name, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        return AnthropicPreparedRequest(urlRequest: urlRequest, warnings: warnings)
    }

    private func endpointURL() -> URL {
        (configuration.baseURL ?? Self.defaultBaseURL).appending(path: "v1/messages")
    }

    private func normalizedResponseFormat(for responseFormat: AIResponseFormat) -> AIResponseFormat {
        switch responseFormat {
        case .json:
            return .jsonSchema(.anyJSON)
        case .text, .jsonSchema:
            return responseFormat
        }
    }

    private func outputConfig(for responseFormat: AIResponseFormat) -> AnthropicOutputConfig? {
        guard case .jsonSchema(let schema, _) = responseFormat else {
            return nil
        }

        return AnthropicOutputConfig(
            format: AnthropicOutputFormat(
                schema: schema
            )
        )
    }

    private func toolPayload(from tool: AITool) -> AnthropicRequestTool {
        AnthropicRequestTool(
            name: tool.name,
            description: tool.description,
            inputSchema: tool.inputSchema
        )
    }

    private func validationWarnings(
        for request: AIRequest,
        normalizedResponseFormat: AIResponseFormat
    ) -> [AIProviderWarning] {
        var warnings: [AIProviderWarning] = []

        if case .jsonSchema = normalizedResponseFormat {
            switch structuredOutputSupport(for: request.model) {
            case .supported:
                break
            case .unsupported:
                warnings.append(
                    AIProviderWarning(
                        code: "unsupported_model_structured_output",
                        message:
                            "Anthropic documents `output_config.format` support for Claude Opus 4.6/4.5, Claude Sonnet 4.6/4.5, and Claude Haiku 4.5; this model may reject structured output.",
                        parameter: "responseFormat"
                    )
                )
            case .unknown:
                warnings.append(
                    AIProviderWarning(
                        code: "custom_model_structured_output_unverified",
                        message:
                            "Structured output support is unverified for custom Anthropic-compatible model IDs; the request is forwarded unchanged.",
                        parameter: "responseFormat"
                    )
                )
            }
        }

        if request.allowParallelToolCalls != nil, request.toolChoice == .some(.none) {
            warnings.append(
                AIProviderWarning(
                    code: "ignored_parallel_tool_setting",
                    message: "Anthropic ignores `allowParallelToolCalls` when `toolChoice` is `.none`.",
                    parameter: "allowParallelToolCalls"
                )
            )
        }

        return warnings
    }

    private func structuredOutputSupport(for model: AIModel) -> AnthropicModelSupport {
        let structuredOutputSupportedPrefixes = [
            "claude-opus-4-6",
            "claude-sonnet-4-6",
            "claude-sonnet-4-5",
            "claude-opus-4-5",
            "claude-haiku-4-5",
        ]

        if structuredOutputSupportedPrefixes.contains(where: model.id.hasPrefix) {
            return .supported
        }

        if model.id.hasPrefix("claude-") {
            return .unsupported
        }

        return .unknown
    }

    private func toolChoice(for request: AIRequest) throws -> AnthropicRequestToolChoice? {
        guard !request.tools.isEmpty else {
            if request.toolChoice != nil {
                throw AIError.invalidRequest("Anthropic tool choice requires at least one tool definition")
            }

            if request.allowParallelToolCalls != nil {
                throw AIError.invalidRequest("Anthropic parallel tool settings require at least one tool definition")
            }

            return nil
        }

        let disableParallelToolUse = request.allowParallelToolCalls.map { !$0 }

        switch request.toolChoice {
        case .some(.none):
            return AnthropicRequestToolChoice.none
        case .some(.required):
            return .any(disableParallelToolUse: disableParallelToolUse)
        case .some(.tool(let name)):
            guard request.tools.contains(where: { $0.name == name }) else {
                throw AIError.invalidRequest("Anthropic tool choice references an unknown tool: \(name)")
            }

            return .tool(name: name, disableParallelToolUse: disableParallelToolUse)
        case .some(.auto):
            return .auto(disableParallelToolUse: disableParallelToolUse)
        case nil:
            guard let disableParallelToolUse else {
                return nil
            }

            return .auto(disableParallelToolUse: disableParallelToolUse)
        }
    }

    private func messagePayload(from message: AIMessage) throws -> AnthropicRequestMessage {
        if message.role == .tool {
            for content in message.content {
                guard case .toolResult = content else {
                    throw AIError.invalidRequest("Anthropic tool transcript messages must contain only tool results")
                }
            }
        }

        let role: String = message.role == .assistant ? "assistant" : "user"
        let content = try message.content.map(contentPayload(from:))

        return AnthropicRequestMessage(role: role, content: content)
    }

    private func contentPayload(from content: AIContent) throws -> AnthropicRequestContentBlock {
        switch content {
        case .text(let text):
            return .text(text)
        case .image(let image):
            return .image(
                mediaType: image.mediaType.rawValue,
                data: image.data.base64EncodedString()
            )
        case .document(let document):
            return .document(
                mediaType: document.mediaType.rawValue,
                data: document.data.base64EncodedString()
            )
        case .toolUse(let toolUse):
            let jsonObject: Any

            do {
                jsonObject = try JSONSerialization.jsonObject(with: toolUse.input)
            } catch {
                throw AIError.invalidRequest("Anthropic tool inputs must be valid JSON")
            }

            return .toolUse(
                id: toolUse.id,
                name: toolUse.name,
                input: try AnthropicJSONValue(any: jsonObject)
            )
        case .toolResult(let toolResult):
            return .toolResult(
                toolUseId: toolResult.toolUseId,
                content: toolResult.content,
                isError: toolResult.isError
            )
        }
    }
}

struct AnthropicPreparedRequest {
    let urlRequest: URLRequest
    let warnings: [AIProviderWarning]
}

private enum AnthropicModelSupport {
    case supported
    case unsupported
    case unknown
}

private struct AnthropicRequestPayload: Encodable {
    let model: String
    let messages: [AnthropicRequestMessage]
    let system: String?
    let maxTokens: Int
    let temperature: Double?
    let topP: Double?
    let stopSequences: [String]?
    let metadata: [String: String]?
    let stream: Bool
    let tools: [AnthropicRequestTool]?
    let toolChoice: AnthropicRequestToolChoice?
    let outputConfig: AnthropicOutputConfig?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case system
        case maxTokens = "max_tokens"
        case temperature
        case topP = "top_p"
        case stopSequences = "stop_sequences"
        case metadata
        case stream
        case tools
        case toolChoice = "tool_choice"
        case outputConfig = "output_config"
    }
}

private struct AnthropicRequestTool: Encodable {
    let name: String
    let description: String
    let inputSchema: AIJSONSchema

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }
}

private enum AnthropicRequestToolChoice: Encodable {
    case auto(disableParallelToolUse: Bool?)
    case any(disableParallelToolUse: Bool?)
    case tool(name: String, disableParallelToolUse: Bool?)
    case none

    enum CodingKeys: String, CodingKey {
        case type
        case name
        case disableParallelToolUse = "disable_parallel_tool_use"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .auto(let disableParallelToolUse):
            try container.encode("auto", forKey: .type)
            try container.encodeIfPresent(disableParallelToolUse, forKey: .disableParallelToolUse)
        case .any(let disableParallelToolUse):
            try container.encode("any", forKey: .type)
            try container.encodeIfPresent(disableParallelToolUse, forKey: .disableParallelToolUse)
        case .tool(let name, let disableParallelToolUse):
            try container.encode("tool", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(disableParallelToolUse, forKey: .disableParallelToolUse)
        case .none:
            try container.encode("none", forKey: .type)
        }
    }
}

private struct AnthropicOutputConfig: Encodable {
    let format: AnthropicOutputFormat
}

private struct AnthropicOutputFormat: Encodable {
    let schema: AIJSONSchema

    enum CodingKeys: String, CodingKey {
        case type
        case schema
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("json_schema", forKey: .type)
        try container.encode(schema, forKey: .schema)
    }
}

private struct AnthropicRequestMessage: Encodable {
    let role: String
    let content: [AnthropicRequestContentBlock]
}

private enum AnthropicRequestContentBlock: Encodable {
    case text(String)
    case image(mediaType: String, data: String)
    case document(mediaType: String, data: String)
    case toolUse(id: String, name: String, input: AnthropicJSONValue)
    case toolResult(toolUseId: String, content: String, isError: Bool)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
        case id
        case name
        case input
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
    }

    enum SourceCodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let mediaType, let data):
            try container.encode("image", forKey: .type)
            var sourceContainer = container.nestedContainer(keyedBy: SourceCodingKeys.self, forKey: .source)
            try sourceContainer.encode("base64", forKey: .type)
            try sourceContainer.encode(mediaType, forKey: .mediaType)
            try sourceContainer.encode(data, forKey: .data)
        case .document(let mediaType, let data):
            try container.encode("document", forKey: .type)
            var sourceContainer = container.nestedContainer(keyedBy: SourceCodingKeys.self, forKey: .source)
            try sourceContainer.encode("base64", forKey: .type)
            try sourceContainer.encode(mediaType, forKey: .mediaType)
            try sourceContainer.encode(data, forKey: .data)
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(let toolUseId, let content, let isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseId, forKey: .toolUseId)
            try container.encode(content, forKey: .content)
            try container.encode(isError, forKey: .isError)
        }
    }
}
