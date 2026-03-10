#if canImport(SwiftUI)
    import AICore
    import Observation
    import SwiftUI

    /// A lightweight SwiftUI conversation scaffold.
    @MainActor
    @Observable
    public final class AIConversation {
        public private(set) var messages: [AIMessage]
        public private(set) var isStreaming: Bool
        public private(set) var error: AIError?
        public private(set) var currentStreamText: String

        public let provider: any AIProvider
        public let model: AIModel
        public var systemPrompt: String?

        private var currentTask: Task<Void, Never>?

        public init(provider: any AIProvider, model: AIModel, systemPrompt: String? = nil) {
            self.messages = []
            self.isStreaming = false
            self.error = nil
            self.currentStreamText = ""
            self.provider = provider
            self.model = model
            self.systemPrompt = systemPrompt
        }

        public func send(_ message: String) {
            cancel()
            error = nil
            currentStreamText = ""
            messages.append(.user(message))
            isStreaming = true

            let request = AIRequest(model: model, messages: messages, systemPrompt: systemPrompt)
            currentTask = Task {
                do {
                    for try await event in provider.stream(request) {
                        switch event {
                        case .delta(.text(let delta)):
                            currentStreamText += delta
                        case .finish:
                            messages.append(.assistant(currentStreamText))
                            currentStreamText = ""
                        default:
                            break
                        }
                    }
                } catch is CancellationError {
                    return
                } catch let error as AIError {
                    if error != .cancelled {
                        self.error = error
                    }
                } catch {
                    self.error = .unknown(String(describing: error))
                }

                isStreaming = false
            }
        }

        public func cancel() {
            currentTask?.cancel()
            currentTask = nil
            isStreaming = false
        }

        public func clear() {
            cancel()
            messages = []
            currentStreamText = ""
            error = nil
        }
    }
#endif
