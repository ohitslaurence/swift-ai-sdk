# Spec 06: SwiftUI Integration

> Property wrappers and views that make streaming AI responses feel native in SwiftUI.

## Goal

Provide SwiftUI-native tools so developers can add AI streaming to a view in a few lines of code. No manual `AsyncSequence` plumbing, no accidental off-main state mutation.

## Dependencies

- Spec 01 (AICore)
- Spec 05 (tool-stream integration)
- SwiftUI
- Observation framework

## Concurrency Rules

1. `AIStreamState` and `AIConversation` are `@MainActor` observable reference types.
2. They are **not** `Sendable`.
3. All UI-observable mutations happen on the main actor.
4. Long-running work happens in child `Task`s, but every state write hops back to the main actor.

## Public API

### AIStreamState

```swift
@MainActor
@Observable
public final class AIStreamState {
    public private(set) var text: String
    public private(set) var isStreaming: Bool
    public private(set) var error: AIError?
    public private(set) var usage: AIUsage?
    public private(set) var isComplete: Bool

    public var smoothStreaming: SmoothStreaming?

    public init(smoothStreaming: SmoothStreaming? = .default)

    public func stream(
        _ prompt: String,
        provider: any AIProvider,
        model: AIModel,
        systemPrompt: String? = nil,
        smooth: SmoothStreaming? = nil
    )

    public func stream(
        _ request: AIRequest,
        provider: any AIProvider,
        smooth: SmoothStreaming? = nil
    )

    public func cancel()
    public func reset()
}
```

### Usage in SwiftUI

```swift
struct ChatView: View {
    let provider: any AIProvider

    @State private var stream = AIStreamState()
    @State private var prompt = ""

    var body: some View {
        VStack {
            ScrollView {
                Text(stream.text)
                    .animation(.default, value: stream.text)
            }

            if stream.isStreaming {
                ProgressView()
            }

            if let error = stream.error {
                Text("Error: \(error.localizedDescription)")
                    .foregroundStyle(.red)
            }

            HStack {
                TextField("Ask something...", text: $prompt)
                Button("Send") {
                    stream.stream(prompt, provider: provider, model: .claude(.haiku4_5))
                    prompt = ""
                }
                .disabled(stream.isStreaming)
            }
        }
    }
}
```

### StreamingText View

```swift
public struct StreamingText: View {
    public let state: AIStreamState
    public var showCursor: Bool = true
    public var font: Font = .body

    public init(_ state: AIStreamState, showCursor: Bool = true, font: Font = .body)

    public var body: some View { ... }
}
```

### MessageList View

```swift
public struct AIMessageList: View {
    public let messages: [AIMessage]
    public var streamingText: String?

    public init(_ messages: [AIMessage], streamingText: String? = nil)

    public var body: some View { ... }
}
```

### Conversation Manager

```swift
public enum AIConversationSendPolicy: Sendable {
    case rejectWhileStreaming
    case cancelCurrentResponse
}

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

    public init(
        provider: any AIProvider,
        model: AIModel,
        systemPrompt: String? = nil,
        smoothStreaming: SmoothStreaming? = .default,
        sendPolicy: AIConversationSendPolicy = .rejectWhileStreaming,
        approvalHandler: (@Sendable (AIToolUse) async -> Bool)? = nil,
        toolCallRepairHandler: (@Sendable (AIToolUse, AIErrorContext) async -> Data?)? = nil
    )

    public func send(_ message: String)
    public func send(_ message: String, tools: [AITool])
    public func cancel()
    public func clear()
}
```

## Implementation Details

### AIStreamState Internals

- Hold a private `Task<Void, Never>?` for the current stream.
- Hold a private monotonically increasing generation token so cancelled detached tasks cannot write stale state back into a newer stream.
- `stream(...)` cancels any in-flight task before starting a new one.
- `cancel()` and `reset()` also advance that generation token.
- Iterate raw `AIStreamEvent`s so `usage` and `finish` can be captured without losing metadata.
- Apply `smooth(_:)` before iteration when smoothing is enabled.
- Treat both `CancellationError` and `AIError.cancelled` as a clean stop, not an error banner.
- If the stream is interrupted after partial text arrives, keep the accumulated `text`, set `error`, and leave `isComplete == false`.

Reference flow:

```swift
@MainActor
public func stream(_ request: AIRequest, provider: any AIProvider, smooth: SmoothStreaming? = nil) {
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
            // No-op: cancellation is user intent.
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
                self.error = .unknown(.init(message: String(describing: error), underlyingType: String(reflecting: type(of: error))))
            }
        }

        await MainActor.run {
            guard self.streamGeneration == generation else { return }
            self.isStreaming = false
        }
    }
}
```

### Smooth Streaming

```swift
public struct SmoothStreaming: Sendable {
    public enum ChunkMode: Sendable {
        case word
        case line
        case character
    }

    public var delay: TimeInterval
    public var mode: ChunkMode

    public static let `default` = SmoothStreaming(delay: 0.01, mode: .word)

    public init(delay: TimeInterval = 0.01, mode: ChunkMode = .word)
}

extension AIStream {
    public func smooth(_ config: SmoothStreaming = .default) -> AIStream
}
```

Rules:

- `smooth(_:)` consumes the original single-pass stream and returns a new single-pass stream.
- Buffering must stay bounded.
- Any buffered text flushes immediately on finish or cancellation.
- That cancellation flush is the permitted delivery of already-buffered derived text, not a new synthesized upstream stream event.
- Non-text events (`usage`, `finish`, `toolUseStart`) pass through without artificial delay.

### StreamingText Cursor

- Append a blinking `|` only while `state.isStreaming == true`.
- Cursor animation must stop immediately when the stream ends or is cancelled.

### AIMessageList Auto-Scroll

- Use `ScrollViewReader` with an anchor at the bottom.
- Auto-scroll only when the user is already near the bottom.
- Re-scroll when `streamingText` changes or a new message is appended.

### AIConversation Internals

- `messages` contains the committed provider-neutral transcript, including any intermediate tool replay messages from completed tool steps.
- `currentStreamText` holds the in-flight assistant text.
- `sendPolicy` controls what happens when `send()` is called during an active stream:
  - `.rejectWhileStreaming`: leave the current stream running and set `error = .invalidRequest("Cannot send while another response is streaming")`
  - `.cancelCurrentResponse`: cancel the current stream, then start the new one

Plain streaming flow:

1. Append `.user(message)`.
2. Start `provider.stream(...)`.
3. Accumulate text into `currentStreamText`.
4. When the stream finishes, append `.assistant(currentStreamText)` to `messages`.
5. Fold any final `usage` into `totalUsage`.
6. If the stream fails after partial text arrives, do not append an assistant message; leave `currentStreamText` available for UI recovery and set `error`.

Tool-stream flow:

1. Append `.user(message)`.
2. Start `provider.streamWithTools(...)`, forwarding `approvalHandler` and `toolCallRepairHandler`.
3. For `.streamEvent(.delta(.text))`, append to `currentStreamText`.
4. For `.toolApprovalRequired` / `.toolExecuting`, update `activeToolCalls`.
5. For `.toolResult`, append to `toolResults`.
6. For `.stepComplete`, append `step.appendedMessages` to `messages`, merge step usage into `totalUsage`, clear `currentStreamText`, and clear per-step tool UI state.
7. On final non-tool finish, append the terminal assistant message and clear transient state.
8. If the stitched tool stream ends because a stop condition fired immediately after `.stepComplete`, leave `messages` as the committed transcript from completed steps, keep `currentStreamText` empty, and clear transient tool UI state without appending an extra assistant turn.
9. If the stitched tool stream is interrupted mid-step, keep completed `messages` untouched, leave the in-flight partial assistant text uncommitted, and set `error`.

### Thread Safety & Cancellation

- Because `AIConversation` is `@MainActor`, concurrent `send()` calls serialize on the main actor.
- `cancel()` cancels the active task, clears `activeToolCalls`, and leaves committed `messages` untouched.
- `clear()` cancels any active task before emptying state.
- Stream interruption never rewrites or removes previously committed messages.

## File Layout

```
Sources/AISwiftUI/
├── AIStreamState.swift
├── AIConversation.swift
├── StreamingText.swift
├── AIMessageList.swift
├── MessageBubble.swift
└── Documentation.docc/
    └── AISwiftUI.md
```

`SmoothStreaming` and `AIStream.smooth(_:)` live in `Sources/AICore/Streaming/`; this spec defines how `AISwiftUI` consumes them, not where they are implemented.

## Tests

1. `AIStreamState` lifecycle: idle -> streaming -> complete.
2. `AIStreamState.cancel()` stops the active task without surfacing an error.
3. Stream errors map into `error`.
4. Starting a new stream cancels the previous one.
5. `reset()` clears text, usage, completion, and error state.
6. `AIStreamState` captures `usage` by iterating raw stream events.
7. All public state mutations compile under `@MainActor` isolation.
8. `SmoothStreaming.word` re-chunks text correctly.
9. `SmoothStreaming` flushes buffered text immediately on finish.
10. `SmoothStreaming` flushes buffered text immediately on cancellation.
11. `AIConversation.send()` appends the user message and commits the final assistant reply.
12. `AIConversation` preserves multi-turn history.
13. `clear()` empties history and cancels active work.
14. `sendPolicy.rejectWhileStreaming` leaves the current stream running and sets an error.
15. `sendPolicy.cancelCurrentResponse` cancels the old stream and starts the new one.
16. Tool streaming updates `activeToolCalls` and `toolResults`.
17. Tool-step completion appends `step.appendedMessages` into `messages`.
18. `approvalHandler` and `toolCallRepairHandler` are forwarded to `streamWithTools`.
19. `totalUsage` accumulates across multiple exchanges.
20. `StreamingText` builds without crashing.
21. `AIMessageList` auto-scroll logic does not force-scroll when the user is far from the bottom.
22. Interrupted plain streams keep partial text visible but do not commit an assistant message.
23. Interrupted tool streams keep completed step messages only and surface an error.

## Acceptance Criteria

- [ ] `AIStreamState` and `AIConversation` are `@MainActor @Observable` reference types.
- [ ] Neither type is declared `Sendable`.
- [ ] `AIStreamState` captures text, usage, completion, and errors from raw stream events.
- [ ] `AIStream.smooth()` remains a single-pass transform with immediate flush on finish/cancel.
- [ ] `AIConversation` defines explicit behavior for `send()` while another response is streaming.
- [ ] `AIConversation` preserves the committed tool transcript by appending `AIToolStep.appendedMessages`.
- [ ] `AIConversation` exposes approval and repair hooks for tool-stream UI flows.
- [ ] Tool-stream UI state (`activeToolCalls`, `toolResults`, `totalUsage`) is exposed and updated on the main actor.
- [ ] Stream cancellation works cleanly and does not corrupt conversation history.
- [ ] Stream interruption preserves partial UI state without committing incomplete transcript state.
- [ ] `AISwiftUI` stays buildable on non-Apple platforms through conditional compilation.
- [ ] All 23 test cases pass.
