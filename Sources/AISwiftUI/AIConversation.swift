#if canImport(SwiftUI)
    import AICore
    import Observation
    import SwiftUI

    /// Controls behavior when `send()` is called during an active stream.
    public enum AIConversationSendPolicy: Sendable {
        case rejectWhileStreaming
        case cancelCurrentResponse
    }

    /// A lightweight SwiftUI conversation scaffold.
    @MainActor
    @Observable
    public final class AIConversation {
        public private(set) var messages: [AIMessage]
        public private(set) var isStreaming: Bool
        public private(set) var error: AIError?
        public private(set) var currentStreamText: String
        public private(set) var activeToolCalls: [AIToolUse]
        public private(set) var toolResults: [AIToolResult]
        public private(set) var totalUsage: AIUsage

        public let provider: any AIProvider
        public let model: AIModel
        public var systemPrompt: String?
        public var smoothStreaming: SmoothStreaming?
        public var sendPolicy: AIConversationSendPolicy
        public var approvalHandler: (@Sendable (AIToolUse) async -> Bool)?
        public var toolCallRepairHandler: (@Sendable (AIToolUse, AIErrorContext) async -> Data?)?

        private var currentTask: Task<Void, Never>?
        private var streamGeneration: UInt64 = 0

        public init(
            provider: any AIProvider,
            model: AIModel,
            systemPrompt: String? = nil,
            smoothStreaming: SmoothStreaming? = .default,
            sendPolicy: AIConversationSendPolicy = .rejectWhileStreaming,
            approvalHandler: (@Sendable (AIToolUse) async -> Bool)? = nil,
            toolCallRepairHandler: (@Sendable (AIToolUse, AIErrorContext) async -> Data?)? = nil
        ) {
            self.messages = []
            self.isStreaming = false
            self.error = nil
            self.currentStreamText = ""
            self.activeToolCalls = []
            self.toolResults = []
            self.totalUsage = AIUsage(inputTokens: 0, outputTokens: 0)
            self.provider = provider
            self.model = model
            self.systemPrompt = systemPrompt
            self.smoothStreaming = smoothStreaming
            self.sendPolicy = sendPolicy
            self.approvalHandler = approvalHandler
            self.toolCallRepairHandler = toolCallRepairHandler
        }

        public func send(_ message: String) {
            if isStreaming {
                switch sendPolicy {
                case .rejectWhileStreaming:
                    error = .invalidRequest("Cannot send while another response is streaming")
                    return
                case .cancelCurrentResponse:
                    cancelInternal()
                }
            }

            error = nil
            currentStreamText = ""
            messages.append(.user(message))
            isStreaming = true
            streamGeneration &+= 1
            let generation = streamGeneration

            let request = AIRequest(
                model: model,
                messages: messages,
                systemPrompt: systemPrompt
            )
            let smoothConfig = smoothStreaming
            let prov = provider

            currentTask = Task.detached {
                var exchangeUsage: AIUsage?
                do {
                    let source = prov.stream(request)
                    let stream = smoothConfig.map { source.smooth($0) } ?? source

                    for try await event in stream {
                        switch event {
                        case .delta(.text(let delta)):
                            await MainActor.run {
                                guard self.streamGeneration == generation else { return }
                                self.currentStreamText += delta
                            }
                        case .finish:
                            let finalUsage = exchangeUsage
                            await MainActor.run {
                                guard self.streamGeneration == generation else { return }
                                self.messages.append(.assistant(self.currentStreamText))
                                self.currentStreamText = ""
                                if let finalUsage {
                                    self.totalUsage = self.mergeUsage(
                                        self.totalUsage, finalUsage
                                    )
                                }
                            }
                        case .usage(let usage):
                            exchangeUsage = usage
                        default:
                            break
                        }
                    }
                } catch is CancellationError {
                    // Clean stop.
                } catch let error as AIError {
                    switch error {
                    case .cancelled:
                        break
                    default:
                        await MainActor.run {
                            guard self.streamGeneration == generation else { return }
                            self.error = error
                        }
                    }
                } catch {
                    await MainActor.run {
                        guard self.streamGeneration == generation else { return }
                        self.error = .unknown(
                            AIErrorContext(
                                message: String(describing: error),
                                underlyingType: String(reflecting: type(of: error))
                            )
                        )
                    }
                }

                await MainActor.run {
                    guard self.streamGeneration == generation else { return }
                    self.isStreaming = false
                }
            }
        }

        public func send(_ message: String, tools: [AITool]) {
            if isStreaming {
                switch sendPolicy {
                case .rejectWhileStreaming:
                    error = .invalidRequest("Cannot send while another response is streaming")
                    return
                case .cancelCurrentResponse:
                    cancelInternal()
                }
            }

            error = nil
            currentStreamText = ""
            activeToolCalls = []
            toolResults = []
            messages.append(.user(message))
            isStreaming = true
            streamGeneration &+= 1
            let generation = streamGeneration

            let request = AIRequest(
                model: model,
                messages: messages,
                systemPrompt: systemPrompt,
                tools: tools
            )
            let approval = approvalHandler
            let repair = toolCallRepairHandler
            let prov = provider

            currentTask = Task.detached {
                var exchangeUsage: AIUsage?
                do {
                    let toolStream = prov.streamWithTools(
                        request,
                        approvalHandler: approval,
                        toolCallRepairHandler: repair
                    )

                    for try await event in toolStream {
                        switch event {
                        case .streamEvent(.delta(.text(let delta))):
                            await MainActor.run {
                                guard self.streamGeneration == generation else { return }
                                self.currentStreamText += delta
                            }
                        case .streamEvent(.usage(let usage)):
                            exchangeUsage = usage
                        case .streamEvent(.finish):
                            let finalUsage = exchangeUsage
                            exchangeUsage = nil
                            await MainActor.run {
                                guard self.streamGeneration == generation else { return }
                                if !self.currentStreamText.isEmpty {
                                    self.messages.append(
                                        .assistant(self.currentStreamText)
                                    )
                                    self.currentStreamText = ""
                                }
                                if let finalUsage {
                                    self.totalUsage = self.mergeUsage(
                                        self.totalUsage, finalUsage
                                    )
                                }
                            }
                        case .toolApprovalRequired(let toolUse),
                            .toolExecuting(let toolUse):
                            await MainActor.run {
                                guard self.streamGeneration == generation else { return }
                                if !self.activeToolCalls.contains(where: {
                                    $0.id == toolUse.id
                                }) {
                                    self.activeToolCalls.append(toolUse)
                                }
                            }
                        case .toolResult(let result):
                            await MainActor.run {
                                guard self.streamGeneration == generation else { return }
                                self.toolResults.append(result)
                            }
                        case .stepComplete(let step):
                            exchangeUsage = nil
                            await MainActor.run {
                                guard self.streamGeneration == generation else { return }
                                self.messages.append(contentsOf: step.appendedMessages)
                                self.totalUsage = self.mergeUsage(
                                    self.totalUsage, step.usage
                                )
                                self.currentStreamText = ""
                                self.activeToolCalls = []
                                self.toolResults = []
                            }
                        default:
                            break
                        }
                    }
                } catch is CancellationError {
                    // Clean stop.
                } catch let error as AIError {
                    switch error {
                    case .cancelled:
                        break
                    default:
                        await MainActor.run {
                            guard self.streamGeneration == generation else { return }
                            self.error = error
                        }
                    }
                } catch {
                    await MainActor.run {
                        guard self.streamGeneration == generation else { return }
                        self.error = .unknown(
                            AIErrorContext(
                                message: String(describing: error),
                                underlyingType: String(reflecting: type(of: error))
                            )
                        )
                    }
                }

                await MainActor.run {
                    guard self.streamGeneration == generation else { return }
                    self.isStreaming = false
                }
            }
        }

        public func cancel() {
            cancelInternal()
        }

        public func clear() {
            cancelInternal()
            messages = []
            currentStreamText = ""
            activeToolCalls = []
            toolResults = []
            error = nil
            totalUsage = AIUsage(inputTokens: 0, outputTokens: 0)
        }

        private func cancelInternal() {
            currentTask?.cancel()
            currentTask = nil
            streamGeneration &+= 1
            isStreaming = false
            activeToolCalls = []
        }

        private nonisolated func mergeUsage(_ a: AIUsage, _ b: AIUsage) -> AIUsage {
            AIUsage(
                inputTokens: a.inputTokens + b.inputTokens,
                outputTokens: a.outputTokens + b.outputTokens
            )
        }
    }
#endif
