import AICore
import Foundation

struct AnthropicStreamParser {
    func parse(
        _ response: AIHTTPStreamResponse,
        model: AIModel,
        errorMapper: AnthropicErrorMapper,
        warnings: [AIProviderWarning] = []
    ) -> AIStream {
        AIStream(
            AsyncThrowingStream<AIStreamEvent, any Error>(AIStreamEvent.self, bufferingPolicy: .unbounded) {
                continuation in
                let task = Task {
                    var buffer = Data()
                    var currentEventName: String?
                    var currentDataLines: [String] = []
                    var state = AnthropicStreamState()

                    do {
                        for try await chunk in response.body {
                            buffer.append(chunk)

                            while let line = try consumeLine(from: &buffer) {
                                try process(
                                    line: line,
                                    currentEventName: &currentEventName,
                                    currentDataLines: &currentDataLines,
                                    state: &state,
                                    model: model,
                                    errorMapper: errorMapper,
                                    continuation: continuation
                                )
                            }
                        }

                        if !buffer.isEmpty {
                            let trailingLine = try decodeLine(buffer)
                            try process(
                                line: trailingLine,
                                currentEventName: &currentEventName,
                                currentDataLines: &currentDataLines,
                                state: &state,
                                model: model,
                                errorMapper: errorMapper,
                                continuation: continuation
                            )
                        }

                        if !currentDataLines.isEmpty {
                            try emitEvent(
                                named: currentEventName,
                                dataLines: currentDataLines,
                                state: &state,
                                model: model,
                                errorMapper: errorMapper,
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

    private func process(
        line: String,
        currentEventName: inout String?,
        currentDataLines: inout [String],
        state: inout AnthropicStreamState,
        model: AIModel,
        errorMapper: AnthropicErrorMapper,
        continuation: AsyncThrowingStream<AIStreamEvent, any Error>.Continuation
    ) throws {
        if line.isEmpty {
            if !currentDataLines.isEmpty {
                try emitEvent(
                    named: currentEventName,
                    dataLines: currentDataLines,
                    state: &state,
                    model: model,
                    errorMapper: errorMapper,
                    continuation: continuation
                )
            }

            currentEventName = nil
            currentDataLines.removeAll(keepingCapacity: true)
            return
        }

        if line.hasPrefix("event:") {
            currentEventName = trimmedValue(from: line, prefixLength: 6)
            return
        }

        if line.hasPrefix("data:") {
            currentDataLines.append(trimmedValue(from: line, prefixLength: 5))
        }
    }

    private func emitEvent(
        named eventName: String?,
        dataLines: [String],
        state: inout AnthropicStreamState,
        model: AIModel,
        errorMapper: AnthropicErrorMapper,
        continuation: AsyncThrowingStream<AIStreamEvent, any Error>.Continuation
    ) throws {
        guard let eventName else {
            return
        }

        let data = Data(dataLines.joined(separator: "\n").utf8)

        switch eventName {
        case "message_start":
            let event = try decode(AnthropicMessageStartEvent.self, from: data)
            state.inputUsage = event.message.usage
            continuation.yield(.start(id: event.message.id, model: event.message.model))
        case "content_block_start":
            let event = try decode(AnthropicContentBlockStartEvent.self, from: data)

            if event.contentBlock.type == "tool_use" {
                guard let id = event.contentBlock.id, let name = event.contentBlock.name else {
                    throw AIError.decodingError(
                        AIErrorContext(message: "Anthropic tool_use start events must include an id and name")
                    )
                }

                state.toolIDsByIndex[event.index] = id
                continuation.yield(.toolUseStart(id: id, name: name))
            }
        case "content_block_delta":
            let event = try decode(AnthropicContentBlockDeltaEvent.self, from: data)

            switch event.delta.type {
            case "text_delta":
                guard let text = event.delta.text else {
                    throw AIError.decodingError(
                        AIErrorContext(message: "Anthropic text deltas must include text")
                    )
                }

                continuation.yield(.delta(.text(text)))
            case "input_json_delta":
                guard let toolID = state.toolIDsByIndex[event.index], let jsonDelta = event.delta.partialJSON else {
                    throw AIError.decodingError(
                        AIErrorContext(message: "Anthropic tool input delta arrived before its tool_use start")
                    )
                }

                continuation.yield(.delta(.toolInput(id: toolID, jsonDelta: jsonDelta)))
            default:
                return
            }
        case "message_delta":
            let event = try decode(AnthropicMessageDeltaEvent.self, from: data)

            state.pendingFinishReason = AnthropicFinishReasonMapper.map(
                stopReason: event.delta.stopReason,
                stopSequence: event.delta.stopSequence
            )

            if let usage = event.usage {
                continuation.yield(
                    .usage(
                        usage.aiUsage(
                            defaultInputTokens: state.inputUsage?.inputTokens ?? 0,
                            defaultInputTokenDetails: state.inputUsage?.inputTokenDetails
                        )
                    )
                )
            }
        case "message_stop":
            state.didEmitFinish = true
            continuation.yield(.finish(state.pendingFinishReason ?? .stop))
        case "error":
            throw errorMapper.mapStreamError(body: data, model: model)
        default:
            return
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AIError.decodingError(AIErrorContext(error))
        }
    }

    private func consumeLine(from buffer: inout Data) throws -> String? {
        guard let lineFeedIndex = buffer.firstIndex(of: 0x0A) else {
            return nil
        }

        let line = try decodeLine(buffer[..<lineFeedIndex])
        buffer.removeSubrange(...lineFeedIndex)
        return line
    }

    private func decodeLine(_ lineData: some DataProtocol) throws -> String {
        let normalizedData = Data(lineData)
        let trimmedData = normalizedData.last == 0x0D ? normalizedData.dropLast() : normalizedData[...]

        guard let line = String(data: Data(trimmedData), encoding: .utf8) else {
            throw AIError.decodingError(AIErrorContext(message: "Anthropic SSE stream contained invalid UTF-8"))
        }

        return line
    }

    private func trimmedValue(from line: String, prefixLength: Int) -> String {
        let valueStart = line.index(line.startIndex, offsetBy: prefixLength)
        let value = line[valueStart...]
        return value.first == " " ? String(value.dropFirst()) : String(value)
    }
}

private struct AnthropicStreamState {
    var inputUsage: AnthropicUsagePayload?
    var pendingFinishReason: AIFinishReason?
    var toolIDsByIndex: [Int: String] = [:]
    var didEmitFinish = false
}

private struct AnthropicMessageStartEvent: Decodable {
    let message: Message

    struct Message: Decodable {
        let id: String
        let model: String
        let usage: AnthropicUsagePayload?
    }
}

private struct AnthropicContentBlockStartEvent: Decodable {
    let index: Int
    let contentBlock: ContentBlock

    enum CodingKeys: String, CodingKey {
        case index
        case contentBlock = "content_block"
    }

    struct ContentBlock: Decodable {
        let type: String
        let id: String?
        let name: String?
    }
}

private struct AnthropicContentBlockDeltaEvent: Decodable {
    let index: Int
    let delta: Delta

    struct Delta: Decodable {
        let type: String
        let text: String?
        let partialJSON: String?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case partialJSON = "partial_json"
        }
    }
}

private struct AnthropicMessageDeltaEvent: Decodable {
    let delta: Delta
    let usage: AnthropicUsagePayload?

    struct Delta: Decodable {
        let stopReason: String?
        let stopSequence: String?

        enum CodingKeys: String, CodingKey {
            case stopReason = "stop_reason"
            case stopSequence = "stop_sequence"
        }
    }
}
