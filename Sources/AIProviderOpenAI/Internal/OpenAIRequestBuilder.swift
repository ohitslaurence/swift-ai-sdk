import AICore
import Foundation

struct OpenAIRequestBuilder {
    private static let defaultBaseURL: URL = {
        guard let url = URL(string: "https://api.openai.com") else {
            preconditionFailure("OpenAI base URL must be valid")
        }

        return url
    }()

    private static let reasoningModelPrefixes = [
        "o3",
        "o4",
        "gpt-5",
    ]

    private static let stopUnsupportedModelPrefixes = [
        "o3",
        "o4-mini",
    ]

    private let apiKey: String
    private let organization: String?
    private let configuration: AIProviderHTTPConfiguration

    init(apiKey: String, organization: String?, configuration: AIProviderHTTPConfiguration) {
        self.apiKey = apiKey
        self.organization = organization
        self.configuration = configuration
    }

    func prepareRequest(
        for request: AIRequest,
        stream: Bool,
        tokenLimitFieldStrategy: OpenAITokenLimitFieldStrategy = .maxCompletionTokens
    ) throws -> OpenAIPreparedRequest {
        var warnings: [AIProviderWarning] = []

        let isReasoning = isReasoningModel(request.model)
        let stopSequences = normalizedStopSequences(for: request, isReasoning: isReasoning, warnings: &warnings)
        checkReasoningModelWarnings(for: request, isReasoning: isReasoning, warnings: &warnings)

        if tokenLimitFieldStrategy == .maxTokens, request.maxTokens != nil {
            warnings.append(
                AIProviderWarning(
                    code: "legacy_max_tokens_fallback",
                    message:
                        "The compatible backend rejected `max_completion_tokens`; the request was retried with legacy `max_tokens`.",
                    parameter: "maxTokens"
                )
            )
        }

        let messages = try buildMessages(
            systemPrompt: request.systemPrompt,
            messages: request.messages,
            isReasoning: isReasoning
        )

        let responseFormat = openAIResponseFormat(for: request.responseFormat)
        let tools = request.tools.isEmpty ? nil : request.tools.map(toolPayload(from:))
        let toolChoice = try openAIToolChoice(for: request)
        let parallelToolCalls = request.allowParallelToolCalls

        var streamOptions: OpenAIStreamOptions?
        if stream {
            streamOptions = OpenAIStreamOptions(includeUsage: true)
        }

        var urlRequest = URLRequest(url: endpointURL())
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = try JSONEncoder().encode(
            OpenAIRequestPayload(
                model: request.model.id,
                messages: messages,
                maxCompletionTokens: tokenLimitFieldStrategy == .maxCompletionTokens ? request.maxTokens : nil,
                maxTokens: tokenLimitFieldStrategy == .maxTokens ? request.maxTokens : nil,
                temperature: request.temperature,
                topP: request.topP,
                stop: stopSequences,
                responseFormat: responseFormat,
                tools: tools,
                toolChoice: toolChoice,
                parallelToolCalls: parallelToolCalls,
                stream: stream ? true : nil,
                streamOptions: streamOptions,
                metadata: request.metadata.isEmpty ? nil : request.metadata
            )
        )

        var headers = configuration.defaultHeaders
        headers.merge(request.headers) { _, new in new }
        headers["Authorization"] = "Bearer \(apiKey)"
        headers["Content-Type"] = "application/json"

        if let organization {
            headers["OpenAI-Organization"] = organization
        }

        for (name, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        return OpenAIPreparedRequest(urlRequest: urlRequest, warnings: warnings)
    }

    private func endpointURL() -> URL {
        (configuration.baseURL ?? Self.defaultBaseURL).appending(path: "v1/chat/completions")
    }

    private func isReasoningModel(_ model: AIModel) -> Bool {
        Self.reasoningModelPrefixes.contains(where: { model.id.hasPrefix($0) })
    }

    func shouldFallbackToLegacyMaxTokens(for request: AIRequest, after error: AIError) -> Bool {
        guard request.maxTokens != nil, configuration.baseURL != nil, !isReasoningModel(request.model) else {
            return false
        }

        guard case .invalidRequest(let message) = error else {
            return false
        }

        return message.lowercased().contains("max_completion_tokens")
    }

    private func isStopUnsupported(_ model: AIModel) -> Bool {
        Self.stopUnsupportedModelPrefixes.contains(where: { model.id.hasPrefix($0) })
    }

    private func normalizedStopSequences(
        for request: AIRequest,
        isReasoning: Bool,
        warnings: inout [AIProviderWarning]
    ) -> [String]? {
        guard !request.stopSequences.isEmpty else {
            return nil
        }

        if isStopUnsupported(request.model) {
            warnings.append(
                AIProviderWarning(
                    code: "unsupported_stop_sequences",
                    message:
                        "The `stop` parameter is not supported for \(request.model.id); the setting has been dropped.",
                    parameter: "stopSequences"
                )
            )

            return nil
        }

        return request.stopSequences
    }

    private func checkReasoningModelWarnings(
        for request: AIRequest,
        isReasoning: Bool,
        warnings: inout [AIProviderWarning]
    ) {
        guard isReasoning else {
            return
        }

        if request.temperature != nil {
            warnings.append(
                AIProviderWarning(
                    code: "unsupported_temperature",
                    message:
                        "The `temperature` parameter may not be supported for reasoning model \(request.model.id).",
                    parameter: "temperature"
                )
            )
        }

        if request.topP != nil {
            warnings.append(
                AIProviderWarning(
                    code: "unsupported_top_p",
                    message: "The `topP` parameter may not be supported for reasoning model \(request.model.id).",
                    parameter: "topP"
                )
            )
        }
    }

    private func buildMessages(
        systemPrompt: String?,
        messages: [AIMessage],
        isReasoning: Bool
    ) throws -> [OpenAIRequestMessage] {
        var result: [OpenAIRequestMessage] = []

        if let systemPrompt {
            let role = isReasoning ? "developer" : "system"
            result.append(
                OpenAIRequestMessage(role: role, content: .text(systemPrompt), toolCallId: nil, toolCalls: nil))
        }

        for message in messages {
            result.append(try messagePayload(from: message))
        }

        return result
    }

    private func messagePayload(from message: AIMessage) throws -> OpenAIRequestMessage {
        switch message.role {
        case .user:
            let content = try userContent(from: message.content)
            return OpenAIRequestMessage(role: "user", content: content, toolCallId: nil, toolCalls: nil)
        case .assistant:
            return try assistantPayload(from: message)
        case .tool:
            return try toolResultPayload(from: message)
        }
    }

    private func userContent(from content: [AIContent]) throws -> OpenAIMessageContent {
        if content.count == 1, case .text(let text) = content[0] {
            return .text(text)
        }

        return .parts(try content.map { try userContentPart(from: $0) })
    }

    private func userContentPart(from content: AIContent) throws -> OpenAIContentPart {
        switch content {
        case .text(let text):
            return .text(text)
        case .image(let image):
            let base64 = image.data.base64EncodedString()
            let dataURL = "data:\(image.mediaType.rawValue);base64,\(base64)"
            return .imageURL(dataURL)
        case .document:
            throw AIError.unsupportedFeature(
                "Document inputs are not supported by the OpenAI Chat Completions provider")
        case .toolUse, .toolResult:
            throw AIError.invalidRequest("Tool content blocks are not valid in user messages for OpenAI")
        }
    }

    private func assistantPayload(from message: AIMessage) throws -> OpenAIRequestMessage {
        var textParts: [String] = []
        var toolCalls: [OpenAIRequestToolCall] = []

        for content in message.content {
            switch content {
            case .text(let text):
                textParts.append(text)
            case .toolUse(let toolUse):
                let inputString: String
                if toolUse.input.isEmpty {
                    inputString = "{}"
                } else {
                    guard let jsonString = String(data: toolUse.input, encoding: .utf8) else {
                        throw AIError.invalidRequest("OpenAI tool call arguments must be valid UTF-8")
                    }

                    inputString = jsonString
                }

                toolCalls.append(
                    OpenAIRequestToolCall(
                        id: toolUse.id,
                        function: OpenAIRequestFunction(
                            name: toolUse.name,
                            arguments: inputString
                        )
                    )
                )
            default:
                throw AIError.invalidRequest("Unsupported content type in assistant message for OpenAI")
            }
        }

        let content: OpenAIMessageContent? = textParts.isEmpty ? nil : .text(textParts.joined())

        return OpenAIRequestMessage(
            role: "assistant",
            content: content,
            toolCallId: nil,
            toolCalls: toolCalls.isEmpty ? nil : toolCalls
        )
    }

    private func toolResultPayload(from message: AIMessage) throws -> OpenAIRequestMessage {
        guard message.content.count == 1, case .toolResult(let result) = message.content[0] else {
            throw AIError.invalidRequest("OpenAI tool messages must contain exactly one tool result")
        }

        return OpenAIRequestMessage(
            role: "tool",
            content: .text(result.content),
            toolCallId: result.toolUseId,
            toolCalls: nil
        )
    }

    private func toolPayload(from tool: AITool) -> OpenAIRequestToolDefinition {
        OpenAIRequestToolDefinition(
            function: OpenAIFunctionDefinition(
                name: tool.name,
                description: tool.description,
                parameters: tool.inputSchema
            )
        )
    }

    private func openAIToolChoice(for request: AIRequest) throws -> OpenAIToolChoice? {
        guard !request.tools.isEmpty else {
            if request.toolChoice != nil {
                throw AIError.invalidRequest("OpenAI tool choice requires at least one tool definition")
            }

            return nil
        }

        switch request.toolChoice {
        case .some(.auto):
            return .string("auto")
        case .some(.required):
            return .string("required")
        case .some(.none):
            return .string("none")
        case .some(.tool(let name)):
            guard request.tools.contains(where: { $0.name == name }) else {
                throw AIError.invalidRequest("OpenAI tool choice references an unknown tool: \(name)")
            }

            return .function(name)
        case nil:
            return nil
        }
    }

    private func openAIResponseFormat(for format: AIResponseFormat) -> OpenAIResponseFormat? {
        switch format {
        case .text:
            return nil
        case .json:
            return .jsonObject
        case .jsonSchema(let schema):
            let name = schemaName(for: schema)
            return .jsonSchema(name: name, schema: schema)
        }
    }

    private func schemaName(for schema: AIJSONSchema) -> String {
        switch schema {
        case .object(let properties, _, _, _):
            let sortedKeys = properties.keys.sorted()
            if !sortedKeys.isEmpty {
                return sortedKeys.prefix(3).joined(separator: "_")
            }

            return "response"
        default:
            return "response"
        }
    }
}

struct OpenAIPreparedRequest {
    let urlRequest: URLRequest
    let warnings: [AIProviderWarning]
}

enum OpenAITokenLimitFieldStrategy {
    case maxCompletionTokens
    case maxTokens
}

private struct OpenAIRequestPayload: Encodable {
    let model: String
    let messages: [OpenAIRequestMessage]
    let maxCompletionTokens: Int?
    let maxTokens: Int?
    let temperature: Double?
    let topP: Double?
    let stop: [String]?
    let responseFormat: OpenAIResponseFormat?
    let tools: [OpenAIRequestToolDefinition]?
    let toolChoice: OpenAIToolChoice?
    let parallelToolCalls: Bool?
    let stream: Bool?
    let streamOptions: OpenAIStreamOptions?
    let metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxCompletionTokens = "max_completion_tokens"
        case maxTokens = "max_tokens"
        case temperature
        case topP = "top_p"
        case stop
        case responseFormat = "response_format"
        case tools
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
        case stream
        case streamOptions = "stream_options"
        case metadata
    }
}

struct OpenAIRequestMessage: Encodable {
    let role: String
    let content: OpenAIMessageContent?
    let toolCallId: String?
    let toolCalls: [OpenAIRequestToolCall]?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCallId = "tool_call_id"
        case toolCalls = "tool_calls"
    }
}

enum OpenAIMessageContent: Encodable {
    case text(String)
    case parts([OpenAIContentPart])

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .text(let text):
            try container.encode(text)
        case .parts(let parts):
            try container.encode(parts)
        }
    }
}

enum OpenAIContentPart: Encodable {
    case text(String)
    case imageURL(String)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageUrl = "image_url"
    }

    enum ImageURLCodingKeys: String, CodingKey {
        case url
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageURL(let url):
            try container.encode("image_url", forKey: .type)
            var imageContainer = container.nestedContainer(keyedBy: ImageURLCodingKeys.self, forKey: .imageUrl)
            try imageContainer.encode(url, forKey: .url)
        }
    }
}

struct OpenAIRequestToolCall: Encodable {
    let id: String
    let function: OpenAIRequestFunction

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case function
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode("function", forKey: .type)
        try container.encode(function, forKey: .function)
    }
}

struct OpenAIRequestFunction: Encodable {
    let name: String
    let arguments: String
}

private struct OpenAIRequestToolDefinition: Encodable {
    let function: OpenAIFunctionDefinition

    enum CodingKeys: String, CodingKey {
        case type
        case function
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("function", forKey: .type)
        try container.encode(function, forKey: .function)
    }
}

private struct OpenAIFunctionDefinition: Encodable {
    let name: String
    let description: String
    let parameters: AIJSONSchema
}

enum OpenAIToolChoice: Encodable {
    case string(String)
    case function(String)

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .function(let name):
            var container = encoder.container(keyedBy: FunctionCodingKeys.self)
            try container.encode("function", forKey: .type)
            try container.encode(FunctionName(name: name), forKey: .function)
        }
    }

    private enum FunctionCodingKeys: String, CodingKey {
        case type
        case function
    }

    private struct FunctionName: Encodable {
        let name: String
    }
}

enum OpenAIResponseFormat: Encodable {
    case jsonObject
    case jsonSchema(name: String, schema: AIJSONSchema)

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .jsonObject:
            try container.encode("json_object", forKey: .type)
        case .jsonSchema(let name, let schema):
            try container.encode("json_schema", forKey: .type)
            try container.encode(
                OpenAIJSONSchemaPayload(name: name, schema: schema, strict: true),
                forKey: .jsonSchema
            )
        }
    }
}

private struct OpenAIJSONSchemaPayload: Encodable {
    let name: String
    let schema: AIJSONSchema
    let strict: Bool
}

struct OpenAIStreamOptions: Encodable {
    let includeUsage: Bool

    enum CodingKeys: String, CodingKey {
        case includeUsage = "include_usage"
    }
}
