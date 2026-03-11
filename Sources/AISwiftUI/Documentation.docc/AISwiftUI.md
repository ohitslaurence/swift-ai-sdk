# ``AISwiftUI``

Observable state types for building chat interfaces with SwiftUI.

## Overview

`AISwiftUI` provides `@Observable` types that bridge the async AI provider
surface into SwiftUI's reactive model. All state types are `@MainActor` and
drive UI updates automatically.

## AIConversation

``AIConversation`` manages a multi-turn chat with automatic streaming and tool
execution:

```swift
@State var conversation = AIConversation(
    provider: OpenAIProvider(apiKey: "sk-..."),
    model: .gpt(.gpt5Mini),
    systemPrompt: "You are a helpful assistant."
)

var body: some View {
    VStack {
        AIMessageList(conversation.messages,
                      streamingText: conversation.currentStreamText)

        Button("Send") {
            conversation.send("Hello!")
        }
        .disabled(conversation.isStreaming)
    }
}
```

### Tool support

Pass tools to `send` for tool-calling conversations:

```swift
conversation.send("What's the weather?", tools: [weatherTool])
```

Active tool calls and results are exposed via `activeToolCalls` and
`toolResults` for rendering in-progress tool execution.

### Send policies

Control behavior when a message is sent while streaming:

- `.rejectWhileStreaming` — Ignores the send (default).
- `.cancelCurrentResponse` — Cancels the current stream and starts a new one.

## AIStreamState

``AIStreamState`` provides standalone streaming state for single-request
scenarios:

```swift
@State var streamState = AIStreamState()

var body: some View {
    VStack {
        StreamingText(streamState)

        Button("Stream") {
            streamState.stream(
                "Explain quantum computing",
                provider: provider,
                model: .gpt(.gpt5Mini)
            )
        }
    }
}
```

## StreamingText

``StreamingText`` renders the current text from an ``AIStreamState`` with an
animated cursor:

```swift
StreamingText(streamState, showCursor: true, font: .body)
```

## AIMessageList

``AIMessageList`` displays a scrollable list of messages with automatic
scroll-to-bottom behavior during streaming:

```swift
AIMessageList(conversation.messages,
              streamingText: conversation.currentStreamText)
```

## Smooth streaming

Both ``AIConversation`` and ``AIStreamState`` support smooth streaming to
re-chunk text deltas for a more natural typing effect:

```swift
AIConversation(
    provider: provider,
    model: model,
    smoothStreaming: SmoothStreaming(delay: 0.01, mode: .word)
)
```
