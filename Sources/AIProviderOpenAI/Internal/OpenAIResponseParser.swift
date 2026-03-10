import AICore
import Foundation

struct OpenAIResponseParser {
    func parse(_ data: Data, warnings: [AIProviderWarning] = []) throws -> AIResponse {
        do {
            let response = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
            let choice = response.choices.first

            return AIResponse(
                id: response.id,
                content: try contentFromChoice(choice),
                model: response.model,
                usage: response.usage?.aiUsage() ?? AIUsage(inputTokens: 0, outputTokens: 0),
                finishReason: mapFinishReason(choice?.finishReason),
                warnings: warnings
            )
        } catch let error as AIError {
            throw error
        } catch {
            throw AIError.decodingError(AIErrorContext(error))
        }
    }

    private func contentFromChoice(_ choice: OpenAIChatChoice?) throws -> [AIContent] {
        guard let choice else {
            return []
        }

        var content: [AIContent] = []

        if let text = choice.message.content, !text.isEmpty {
            content.append(.text(text))
        }

        if let toolCalls = choice.message.toolCalls {
            for toolCall in toolCalls {
                let input = Data(toolCall.function.arguments.utf8)

                content.append(
                    .toolUse(
                        AIToolUse(
                            id: toolCall.id,
                            name: toolCall.function.name,
                            input: input
                        )
                    )
                )
            }
        }

        return content
    }
}

enum OpenAIFinishReasonMapper {
    static func map(_ finishReason: String?) -> AIFinishReason {
        switch finishReason {
        case nil, "stop":
            return .stop
        case "length":
            return .maxTokens
        case "tool_calls":
            return .toolUse
        case "content_filter":
            return .contentFilter
        case let reason?:
            return .unknown(reason)
        }
    }
}

private func mapFinishReason(_ finishReason: String?) -> AIFinishReason {
    OpenAIFinishReasonMapper.map(finishReason)
}

struct OpenAIChatCompletionResponse: Decodable {
    let id: String
    let model: String
    let choices: [OpenAIChatChoice]
    let usage: OpenAIUsagePayload?
}

struct OpenAIChatChoice: Decodable {
    let message: OpenAIChatMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

struct OpenAIChatMessage: Decodable {
    let content: String?
    let toolCalls: [OpenAIToolCallPayload]?

    enum CodingKeys: String, CodingKey {
        case content
        case toolCalls = "tool_calls"
    }
}

struct OpenAIToolCallPayload: Decodable {
    let id: String
    let function: OpenAIFunctionPayload
}

struct OpenAIFunctionPayload: Decodable {
    let name: String
    let arguments: String
}

struct OpenAIUsagePayload: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let promptTokensDetails: PromptTokenDetails?
    let completionTokensDetails: CompletionTokenDetails?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case promptTokensDetails = "prompt_tokens_details"
        case completionTokensDetails = "completion_tokens_details"
    }

    struct PromptTokenDetails: Decodable {
        let cachedTokens: Int?

        enum CodingKeys: String, CodingKey {
            case cachedTokens = "cached_tokens"
        }
    }

    struct CompletionTokenDetails: Decodable {
        let reasoningTokens: Int?

        enum CodingKeys: String, CodingKey {
            case reasoningTokens = "reasoning_tokens"
        }
    }

    func aiUsage() -> AIUsage {
        let inputDetails: AIUsage.InputTokenDetails?
        if let cached = promptTokensDetails?.cachedTokens {
            inputDetails = AIUsage.InputTokenDetails(cachedTokens: cached)
        } else {
            inputDetails = nil
        }

        let outputDetails: AIUsage.OutputTokenDetails?
        if let reasoning = completionTokensDetails?.reasoningTokens {
            outputDetails = AIUsage.OutputTokenDetails(reasoningTokens: reasoning)
        } else {
            outputDetails = nil
        }

        return AIUsage(
            inputTokens: promptTokens ?? 0,
            outputTokens: completionTokens ?? 0,
            inputTokenDetails: inputDetails,
            outputTokenDetails: outputDetails
        )
    }
}
