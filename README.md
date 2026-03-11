# Swift AI SDK

[![Swift 6](https://img.shields.io/badge/swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-macOS%2014%20|%20iOS%2017%20|%20tvOS%2017%20|%20watchOS%2010%20|%20visionOS%201-blue.svg)](#)

> **Work in progress** — This SDK is under active development and not yet ready for production use. APIs may change without notice. Contributions and feedback are welcome.

A provider-agnostic Swift SDK for building AI-powered applications. Write your integration once against a unified protocol, then swap between OpenAI, Anthropic, and future providers with a single line change.

- **Provider-neutral core** — `AICore` defines shared protocols for completions, streaming, embeddings, tools, and structured output with zero provider dependencies
- **First-class streaming** — `AIStream` with async/await, text deltas, tool call events, and usage reporting
- **Swift 6 strict concurrency** — Full `Sendable` compliance across all public types
- **SwiftUI integration** — Observable state types for building chat interfaces
- **Extensible transport** — Plug in custom HTTP transports, middleware, and telemetry
- **Structured output** — JSON mode and JSON Schema support with provider-native enforcement

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ohitslaurence/swift-ai-sdk", branch: "main")
]
```

Then depend on either the umbrella module or individual modules:

```swift
.product(name: "AI", package: "swift-ai-sdk")       // everything
.product(name: "AICore", package: "swift-ai-sdk")    // core protocols only
```

## Quick Start

### Completion

```swift
import AI

let provider = OpenAIProvider(apiKey: "sk-...")

let response = try await provider.complete(
    AIRequest(
        model: .gpt(.gpt5Mini),
        messages: [.user("Hello")]
    )
)

print(response.text)
print("Tokens: \(response.usage.inputTokens) in, \(response.usage.outputTokens) out")
```

### Streaming

```swift
let stream = provider.stream(
    AIRequest(model: .gpt(.gpt5Mini), messages: [.user("Tell me a story")])
)

for try await event in stream {
    if case .delta(.text(let chunk)) = event {
        print(chunk, terminator: "")
    }
}
```

### Swap Providers

```swift
// Just change the provider — everything else stays the same
let provider = AnthropicProvider(apiKey: "sk-ant-...")

let response = try await provider.complete(
    AIRequest(
        model: .claude(.sonnet4_6),
        messages: [.user("Hello")]
    )
)
```

### Embeddings

```swift
let embedding = try await provider.embed(
    "swift concurrency",
    model: .openAIEmbedding(.textEmbedding3Small)
)

print("Dimensions: \(embedding.dimensions)")
```

### Tool Use

```swift
let weatherTool = AITool(
    name: "get_weather",
    description: "Get the current weather for a city",
    inputSchema: .object(
        properties: ["city": .string(description: "The city name")],
        required: ["city"]
    ),
    handler: { input in "22°C, sunny" }
)

let response = try await provider.complete(
    AIRequest(
        model: .gpt(.gpt5Mini),
        messages: [.user("What's the weather in London?")],
        tools: [weatherTool]
    )
)
```

## Modules

| Module | Description |
|--------|-------------|
| `AI` | Umbrella — re-exports all modules |
| `AICore` | Provider-agnostic protocols, types, streaming, retry, timeout, transport |
| `AIProviderOpenAI` | OpenAI Chat Completions & Embeddings provider |
| `AIProviderAnthropic` | Anthropic Messages API provider |
| `AISwiftUI` | SwiftUI observable state types for chat interfaces |

### Structured Output

```swift
struct MovieReview: AIStructured {
    let title: String
    let rating: Int
    let summary: String
}

let result = try await provider.generate(
    "Review the movie Inception",
    schema: MovieReview.self,
    model: .gpt(.gpt5Mini)
)

print(result.value.title)   // "Inception"
print(result.value.rating)  // 9
```

### Agents

```swift
let agent = Agent(
    provider: provider,
    model: .gpt(.gpt5Mini),
    systemPrompt: "You are a helpful assistant.",
    tools: [weatherTool, searchTool]
)

let result = try await agent.run("What's the weather in London?")
print(result.response.text)
```

### SwiftUI

```swift
import AI

struct ChatView: View {
    @State var conversation = AIConversation(
        provider: OpenAIProvider(apiKey: "sk-..."),
        model: .gpt(.gpt5Mini)
    )

    var body: some View {
        VStack {
            AIMessageList(conversation.messages,
                          streamingText: conversation.currentStreamText)

            Button("Send") {
                conversation.send("Hello!")
            }
        }
    }
}
```

### Middleware

```swift
let provider = withMiddleware(
    OpenAIProvider(apiKey: "sk-..."),
    middleware: [
        DefaultSettingsMiddleware(maxTokens: 1000, temperature: 0.7),
        LoggingMiddleware { print($0) }
    ]
)
```

## Modules

| Module | Description |
|--------|-------------|
| `AI` | Umbrella — re-exports all modules |
| `AICore` | Provider-agnostic protocols, types, streaming, retry, timeout, transport |
| `AIProviderOpenAI` | OpenAI Chat Completions & Embeddings provider |
| `AIProviderAnthropic` | Anthropic Messages API provider |
| `AISwiftUI` | SwiftUI observable state types for chat interfaces |

## Local Development

```bash
swift build          # build all targets
swift test           # run unit tests
make format          # auto-format code
make format-check    # check formatting
```

## License

MIT
