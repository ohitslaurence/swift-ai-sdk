# Swift AI SDK

[![Swift 6](https://img.shields.io/badge/swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-Apple%20%2B%20Linux-blue.svg)](#)

Provider-agnostic AI primitives for Swift.

This repository currently contains the initial package scaffold, module layout,
docs placeholders, test support, and example packages described in `specs/00-project-setup.md`.

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/example/swift-ai-sdk", branch: "main")
]
```

Then depend on either the umbrella module or individual modules:

```swift
.product(name: "AI", package: "swift-ai-sdk")
```

## Quick Example

```swift
import AI

let provider = OpenAIProvider(apiKey: "sk-...")
let request = AIRequest(
    model: .gpt(.gpt4oMini),
    messages: [.user("Hello")]
)

print(request.model.id)
print(provider.availableModels.map(\.id))
```

## Local Development

- `swift build`
- `swift test`
- `make format`

## Modules

- `AI` - umbrella module
- `AICore` - provider-agnostic core primitives
- `AIProviderAnthropic` - Anthropic provider scaffold
- `AIProviderOpenAI` - OpenAI provider scaffold
- `AISwiftUI` - SwiftUI integration scaffold
