import AICore
import Foundation

struct OpenAIStreamParser {
    func parse(_ response: AIHTTPStreamResponse, warnings: [AIProviderWarning] = []) -> AIStream {
        AIStream(
            AsyncThrowingStream<AIStreamEvent, any Error>(AIStreamEvent.self, bufferingPolicy: .unbounded) {
                continuation in
                let task = Task {
                    var buffer = Data()
                    var state = OpenAIStreamState()

                    do {
                        for try await chunk in response.body {
                            buffer.append(chunk)

                            while let line = consumeLine(from: &buffer) {
                                try processLine(
                                    line,
                                    state: &state,
                                    continuation: continuation
                                )
                            }
                        }

                        if !buffer.isEmpty, let trailingLine = decodeLine(buffer) {
                            try processLine(
                                trailingLine,
                                state: &state,
                                continuation: continuation
                            )
                        }

                        if !state.didEmitFinish {
                            throw AIError.streamInterrupted
                        }

                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish(throwing: AIError.cancelled)
                    } catch let error as AIError {
                        continuation.finish(throwing: error)
                    } catch {
                        continuation.finish(throwing: AIError.unknown(AIErrorContext(error)))
                    }
                }

                continuation.onTermination = { _ in
                    task.cancel()
                }
            },
            warnings: warnings
        )
    }

    private func processLine(
        _ line: String,
        state: inout OpenAIStreamState,
        continuation: AsyncThrowingStream<AIStreamEvent, any Error>.Continuation
    ) throws {
        if line.isEmpty || line.hasPrefix(":") {
            return
        }

        guard line.hasPrefix("data:") else {
            return
        }

        let dataValue = trimmedValue(from: line, prefixLength: 5)

        if dataValue == "[DONE]" {
            if !state.didEmitFinish {
                continuation.yield(.finish(state.pendingFinishReason ?? .stop))
                state.didEmitFinish = true
            }

            return
        }

        guard let data = dataValue.data(using: .utf8) else {
            return
        }

        let chunk: OpenAIStreamChunk
        do {
            chunk = try JSONDecoder().decode(OpenAIStreamChunk.self, from: data)
        } catch {
            throw AIError.decodingError(AIErrorContext(error))
        }

        if !state.didEmitStart {
            continuation.yield(.start(id: chunk.id, model: chunk.model ?? "unknown"))
            state.didEmitStart = true
        }

        if let usage = chunk.usage {
            continuation.yield(.usage(usage.aiUsage()))
        }

        guard let choice = chunk.choices?.first else {
            return
        }

        if let finishReason = choice.finishReason {
            state.pendingFinishReason = OpenAIFinishReasonMapper.map(finishReason)
        }

        guard let delta = choice.delta else {
            return
        }

        if let content = delta.content, !content.isEmpty {
            continuation.yield(.delta(.text(content)))
        }

        if let toolCalls = delta.toolCalls {
            for toolCall in toolCalls {
                let index = toolCall.index

                if let id = toolCall.id, let name = toolCall.function?.name {
                    state.toolIDsByIndex[index] = id
                    continuation.yield(.toolUseStart(id: id, name: name))
                }

                if let arguments = toolCall.function?.arguments, !arguments.isEmpty {
                    guard let toolID = state.toolIDsByIndex[index] else {
                        throw AIError.decodingError(
                            AIErrorContext(message: "OpenAI tool call delta arrived before its start event")
                        )
                    }

                    continuation.yield(.delta(.toolInput(id: toolID, jsonDelta: arguments)))
                }
            }
        }
    }

    private func consumeLine(from buffer: inout Data) -> String? {
        guard let lineFeedIndex = buffer.firstIndex(of: 0x0A) else {
            return nil
        }

        let lineData = buffer[..<lineFeedIndex]
        buffer.removeSubrange(...lineFeedIndex)
        return decodeLine(lineData)
    }

    private func decodeLine(_ lineData: some DataProtocol) -> String? {
        let normalizedData = Data(lineData)
        let trimmedData = normalizedData.last == 0x0D ? normalizedData.dropLast() : normalizedData[...]

        return String(data: Data(trimmedData), encoding: .utf8)
    }

    private func trimmedValue(from line: String, prefixLength: Int) -> String {
        let valueStart = line.index(line.startIndex, offsetBy: prefixLength)
        let value = line[valueStart...]
        return value.first == " " ? String(value.dropFirst()) : String(value)
    }
}

private struct OpenAIStreamState {
    var didEmitStart = false
    var didEmitFinish = false
    var pendingFinishReason: AIFinishReason?
    var toolIDsByIndex: [Int: String] = [:]
}

private struct OpenAIStreamChunk: Decodable {
    let id: String
    let model: String?
    let choices: [OpenAIStreamChoice]?
    let usage: OpenAIUsagePayload?
}

private struct OpenAIStreamChoice: Decodable {
    let delta: OpenAIStreamDelta?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
    }
}

private struct OpenAIStreamDelta: Decodable {
    let content: String?
    let toolCalls: [OpenAIStreamToolCall]?

    enum CodingKeys: String, CodingKey {
        case content
        case toolCalls = "tool_calls"
    }
}

private struct OpenAIStreamToolCall: Decodable {
    let index: Int
    let id: String?
    let function: OpenAIStreamToolFunction?
}

private struct OpenAIStreamToolFunction: Decodable {
    let name: String?
    let arguments: String?
}
