# Structured Output

Get typed Swift values from AI providers using JSON Schema enforcement.

## Overview

`AICore` supports schema-driven structured output through
``AIProvider/generate(_:schema:model:systemPrompt:maxRetries:repair:)`` and
``AIProvider/generate(_:schema:maxRetries:repair:)``. Conform your type to
``AIStructured`` and the SDK handles schema generation, provider-native
enforcement, and decode validation.

## Basic usage

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

print(result.value.title)       // Typed access
print(result.value.rating)
print(result.usage.totalTokens) // Token usage across all attempts
print(result.attempts)          // 1 if first try succeeded
```

## Strategy selection

The SDK selects the best enforcement strategy based on
``AIStructuredOutputCapabilities``:

1. **Native JSON Schema** — preferred when ``AIStructuredOutputCapabilities/supportsJSONSchema`` is `true`.
2. **Native JSON mode** — only when a full ``AIRequest`` explicitly uses `.json`.
3. **Tool-call fallback** — wraps the schema as a synthetic tool definition.
4. **Prompt injection** — last resort, injects the schema into the system prompt.

Native JSON mode is never substituted for schema mode by the typed helpers.

## Decode validation and repair

Returned text is always decoded and validated locally, even when the provider
enforces a native schema. On decode failure:

1. Built-in repair strips Markdown fences and extracts JSON from prose.
2. An optional custom ``AIRepairHandler`` gets a chance to fix the text.
3. A corrective retry prompt is sent to the model with the error context.
4. After `maxRetries` exhausted, ``AIError/decodingError(_:)`` is thrown.

## Supported types

Schema generation works automatically for:

- Structs and nested structs with synthesized `Codable`
- `String`, `Int`, `Double`, `Bool`, `Decimal`, `Date`
- `Optional<T>` and `Array<T>` (nested inside keyed types)
- String-backed enums conforming to `CaseIterable`
- Custom `CodingKeys`

## Key behaviors

- ``AIStructured/schemaName`` is preserved when the downstream provider requires a stable schema identifier.
- Structured-output decoding accepts ISO 8601 `date-time` values to match generated `Date` schemas.
- ``AIStructuredResponse/usage`` and ``AIStructuredResponse/warnings`` reflect the full operation, not just the final attempt.
- Shipped native-schema providers include Anthropic Messages and OpenAI Chat Completions.
