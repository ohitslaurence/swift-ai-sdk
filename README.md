# Swift AI SDK

[![Swift 6](https://img.shields.io/badge/swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-macOS%2014%20|%20iOS%2017%20|%20tvOS%2017%20|%20watchOS%2010%20|%20visionOS%201-blue.svg)](#)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

A provider-agnostic Swift SDK for building AI-powered applications. Write your integration once against a unified protocol, then swap between OpenAI, Anthropic, and future providers with a single line change.

- **Provider-neutral core** — shared protocols for completions, streaming, embeddings, tools, and structured output
- **First-class streaming** — `AIStream` with async/await, text deltas, tool call events, and usage reporting
- **Structured output** — JSON Schema support with provider-native enforcement, auto-retry, and repair
- **Tool use and agents** — define tools once, run multi-step execution loops or reusable `Agent` instances
- **SwiftUI integration** — observable state types for building chat interfaces
- **Middleware and telemetry** — composable request/response transforms and structured observability
- **Swift 6 strict concurrency** — full `Sendable` compliance across all public types

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ohitslaurence/swift-ai-sdk", from: "0.1.0")
]
```

Then add the product to your target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "AI", package: "swift-ai-sdk")       // everything
    ]
)
```

You can also depend on individual modules if you don't need the full surface:

```swift
.product(name: "AICore", package: "swift-ai-sdk")             // core protocols only
.product(name: "AIProviderOpenAI", package: "swift-ai-sdk")   // OpenAI provider
.product(name: "AIProviderAnthropic", package: "swift-ai-sdk") // Anthropic provider
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
print("Tokens: \(response.usage.totalTokens)")
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
// Change the provider — everything else stays the same
let anthropic = AnthropicProvider(apiKey: "sk-ant-...")

let response = try await anthropic.complete(
    AIRequest(
        model: .claude(.sonnet4_6),
        messages: [.user("Hello")]
    )
)
```

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

let result = try await provider.completeWithTools(
    AIRequest(
        model: .gpt(.gpt5Mini),
        messages: [.user("What's the weather in London?")],
        tools: [weatherTool]
    )
)

print(result.response.text)
```

### Agents

```swift
let agent = Agent(
    provider: provider,
    model: .gpt(.gpt5Mini),
    systemPrompt: "You are a helpful assistant.",
    tools: [weatherTool]
)

let result = try await agent.run("What's the weather in London?")
print(result.response.text)
```

### Embeddings

```swift
let embedding = try await provider.embed(
    "swift concurrency",
    model: .openAIEmbedding(.textEmbedding3Small)
)

print("Dimensions: \(embedding.dimensions)")
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
            .disabled(conversation.isStreaming)
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

### Telemetry

```swift
struct MetricsSink: AITelemetrySink {
    func record(_ event: AITelemetryEvent) async {
        print("[\(event.operationKind)] \(event.kind)")
    }
}

let provider = withTelemetry(openai, configuration: AITelemetryConfiguration(
    sinks: [MetricsSink()],
    includeMetrics: true,
    includeUsage: true
))
```

## Modules

| Module | Description |
|--------|-------------|
| `AI` | Umbrella — re-exports all modules below |
| `AICore` | Provider-agnostic protocols, types, streaming, retry, timeout, middleware, telemetry |
| `AIProviderOpenAI` | OpenAI Chat Completions and Embeddings provider |
| `AIProviderAnthropic` | Anthropic Messages API provider |
| `AISwiftUI` | Observable state types for SwiftUI chat interfaces |

## Documentation

The package includes DocC documentation for every module:

- [Getting Started](Sources/AICore/Documentation.docc/GettingStarted.md)
- [Structured Output](Sources/AICore/Documentation.docc/StructuredOutput.md)
- [Tool Use](Sources/AICore/Documentation.docc/ToolUse.md)
- [Embeddings](Sources/AICore/Documentation.docc/Embeddings.md)
- [Middleware](Sources/AICore/Documentation.docc/Middleware.md)
- [Observability](Sources/AICore/Documentation.docc/Observability.md)
- [Capability Matrix](Sources/AICore/Documentation.docc/CapabilityMatrix.md)

## Local Development

```bash
swift build          # build all targets
swift test           # run unit tests
make format          # auto-format code
make format-check    # check formatting
make docs            # generate DocC documentation
```

## License

Apache License 2.0 — see [LICENSE](LICENSE) for details.
