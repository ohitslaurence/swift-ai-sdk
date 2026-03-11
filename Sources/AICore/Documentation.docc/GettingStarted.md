# Getting Started

Add the Swift AI SDK to your project and make your first provider call.

## Installation

Add the package dependency to your `Package.swift`:

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
        .product(name: "AI", package: "swift-ai-sdk")
    ]
)
```

Import `AI` for the full surface (providers, SwiftUI, core), or `AICore` for
just the provider-agnostic protocols.

## Create a provider

```swift
import AI

let openai = OpenAIProvider(apiKey: "sk-...")
let anthropic = AnthropicProvider(apiKey: "sk-ant-...")
```

Both conform to ``AIProvider``. All request and response types are shared — swap
the provider and everything else stays the same.

## Complete a request

```swift
let response = try await openai.complete(
    AIRequest(
        model: .gpt(.gpt5Mini),
        messages: [.user("What is Swift concurrency?")]
    )
)

print(response.text)
print("Tokens: \(response.usage.totalTokens)")
```

Or use the convenience overload for simple prompts:

```swift
let text = try await openai.complete(
    "What is Swift concurrency?",
    model: .gpt(.gpt5Mini)
)
```

## Stream a response

```swift
let stream = openai.stream(
    AIRequest(model: .gpt(.gpt5Mini), messages: [.user("Tell me a story")])
)

for try await event in stream {
    if case .delta(.text(let chunk)) = event {
        print(chunk, terminator: "")
    }
}
```

Use ``AIStream/textStream`` for a simpler text-only async sequence, or
``AIStream/collect()`` to aggregate the full stream into an ``AIResponse``.

## Structured output

Conform your type to ``AIStructured`` and call ``AIProvider/generate(_:schema:model:systemPrompt:maxRetries:repair:)``:

```swift
struct MovieReview: AIStructured {
    let title: String
    let rating: Int
    let summary: String
}

let result = try await openai.generate(
    "Review the movie Inception",
    schema: MovieReview.self,
    model: .gpt(.gpt5Mini)
)

print(result.value.title)
print(result.value.rating)
```

The SDK automatically selects provider-native JSON Schema enforcement when
available and retries with repair on decode failures.

## Use tools

Define tools and let the provider call them in a loop:

```swift
let weatherTool = AITool(
    name: "get_weather",
    description: "Get the current weather for a city",
    inputSchema: .object(
        properties: ["city": .string(description: "The city name")],
        required: ["city"]
    ),
    handler: { _ in "22°C, sunny" }
)

let result = try await openai.completeWithTools(
    AIRequest(
        model: .gpt(.gpt5Mini),
        messages: [.user("What's the weather in London?")],
        tools: [weatherTool]
    )
)

print(result.response.text)
```

Or wrap everything in an ``Agent`` for a reusable tool-calling unit:

```swift
let agent = Agent(
    provider: openai,
    model: .gpt(.gpt5Mini),
    tools: [weatherTool]
)

let result = try await agent.run("What's the weather in London?")
```

## Add middleware

Compose request/response transformations with ``withMiddleware(_:middleware:)``:

```swift
let provider = withMiddleware(openai, middleware: [
    DefaultSettingsMiddleware(maxTokens: 1000, temperature: 0.7),
    LoggingMiddleware { print($0) }
])
```

## Next steps

- <doc:StructuredOutput> — JSON Schema generation, repair, and retry
- <doc:ToolUse> — Multi-step tool loops, approval, and agents
- <doc:Embeddings> — Vector embeddings with batching
- <doc:Middleware> — Custom request/response middleware
- <doc:Observability> — Telemetry, metrics, and redaction
- <doc:CapabilityMatrix> — Provider feature comparison
