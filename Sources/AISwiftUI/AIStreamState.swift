#if canImport(SwiftUI)
    import AICore
    import Observation
    import SwiftUI

    /// Observable stream state for SwiftUI.
    @MainActor
    @Observable
    public final class AIStreamState {
        public private(set) var text: String
        public private(set) var isStreaming: Bool
        public private(set) var error: AIError?
        public private(set) var usage: AIUsage?
        public private(set) var isComplete: Bool

        private var currentTask: Task<Void, Never>?

        public init() {
            self.text = ""
            self.isStreaming = false
            self.error = nil
            self.usage = nil
            self.isComplete = false
        }

        public func stream(_ prompt: String, provider: any AIProvider, model: AIModel, systemPrompt: String? = nil) {
            stream(
                AIRequest(model: model, messages: [.user(prompt)], systemPrompt: systemPrompt),
                provider: provider
            )
        }

        public func stream(_ request: AIRequest, provider: any AIProvider) {
            cancel()
            reset()
            isStreaming = true

            currentTask = Task {
                do {
                    for try await event in provider.stream(request) {
                        switch event {
                        case .delta(.text(let delta)):
                            text += delta
                        case .usage(let value):
                            usage = value
                        case .finish:
                            isComplete = true
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

        public func reset() {
            text = ""
            error = nil
            usage = nil
            isComplete = false
        }
    }
#endif
