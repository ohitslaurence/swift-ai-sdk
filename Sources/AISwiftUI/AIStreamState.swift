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

        public var smoothStreaming: SmoothStreaming?

        private var currentTask: Task<Void, Never>?
        private var streamGeneration: UInt64 = 0

        public init(smoothStreaming: SmoothStreaming? = .default) {
            self.text = ""
            self.isStreaming = false
            self.error = nil
            self.usage = nil
            self.isComplete = false
            self.smoothStreaming = smoothStreaming
        }

        public func stream(
            _ prompt: String,
            provider: any AIProvider,
            model: AIModel,
            systemPrompt: String? = nil,
            smooth: SmoothStreaming? = nil
        ) {
            stream(
                AIRequest(model: model, messages: [.user(prompt)], systemPrompt: systemPrompt),
                provider: provider,
                smooth: smooth
            )
        }

        public func stream(
            _ request: AIRequest,
            provider: any AIProvider,
            smooth: SmoothStreaming? = nil
        ) {
            currentTask?.cancel()
            reset()
            isStreaming = true
            let smoothConfig = smooth ?? smoothStreaming
            streamGeneration &+= 1
            let generation = streamGeneration

            currentTask = Task.detached {
                do {
                    let source = provider.stream(request)
                    let stream = smoothConfig.map { source.smooth($0) } ?? source

                    for try await event in stream {
                        switch event {
                        case .delta(.text(let delta)):
                            await MainActor.run {
                                guard self.streamGeneration == generation else { return }
                                self.text += delta
                            }
                        case .usage(let usage):
                            await MainActor.run {
                                guard self.streamGeneration == generation else { return }
                                self.usage = usage
                            }
                        case .finish:
                            await MainActor.run {
                                guard self.streamGeneration == generation else { return }
                                self.isComplete = true
                            }
                        default:
                            break
                        }
                    }
                } catch is CancellationError {
                    // Clean stop — user intent.
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
            currentTask?.cancel()
            currentTask = nil
            streamGeneration &+= 1
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
