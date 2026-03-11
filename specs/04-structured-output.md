# Spec 04: Structured Output

> Turn a `Codable` type into a validated, retry-capable AI response. The killer feature for app developers.

## Review History

- 2026-03-11: Deep implementation audit completed. Tightened structured-output strategy selection so native JSON mode is only used for explicit `.json` requests, restored native-schema propagation of `AIStructured.schemaName`, aligned Date decoding with generated `date-time` schemas, normalized cancellation to `AIError.cancelled`, aggregated usage and warnings across retries, and expanded regression coverage.

## Goal

Let developers say `provider.generate(prompt, schema: MyType.self)` and get back a decoded Swift type - with JSON Schema generation, local validation, repair, and retry behavior that works across providers.

This spec must be implementable entirely from `AICore`. It may consult `AIProvider.capabilities`, but it must not depend on provider modules.

## Dependencies

- Spec 01 (AICore)

## Public API

```swift
extension AIProvider {
    /// Generate a structured response decoded into a Codable type.
    public func generate<T: AIStructured>(
        _ prompt: String,
        schema: T.Type,
        model: AIModel,
        systemPrompt: String? = nil,
        maxRetries: Int = 2,
        repair: AIRepairHandler? = nil
    ) async throws -> AIStructuredResponse<T>

    /// Generate from a full request.
    public func generate<T: AIStructured>(
        _ request: AIRequest,
        schema: T.Type,
        maxRetries: Int = 2,
        repair: AIRepairHandler? = nil
    ) async throws -> AIStructuredResponse<T>
}

public protocol AIStructured: Codable, Sendable {
    /// Stable schema name used by providers that require one.
    static var schemaName: String { get }

    /// JSON Schema for this type.
    ///
    /// The default implementation auto-generates a schema for supported Codable shapes.
    /// It may throw `AIError.unsupportedFeature` when the type cannot be safely reflected.
    static var jsonSchema: AIJSONSchema { get throws }
}

extension AIStructured {
    public static var schemaName: String { get }
    public static var jsonSchema: AIJSONSchema { get throws }
}

public struct AIStructuredResponse<T: Sendable>: Sendable {
    public let value: T
    public let response: AIResponse
    public let attempts: Int

    public init(
        value: T,
        response: AIResponse,
        attempts: Int,
        usage: AIUsage? = nil,
        warnings: [AIProviderWarning]? = nil
    )

    public var usage: AIUsage { get }
    public var warnings: [AIProviderWarning] { get }
}

public typealias AIRepairHandler = @Sendable (
    _ text: String,
    _ error: AIErrorContext
) async throws -> String?
```

### Usage

```swift
struct Recipe: AIStructured {
    let name: String
    let ingredients: [Ingredient]
    let steps: [String]
    let prepTimeMinutes: Int

    struct Ingredient: Codable, Sendable {
        let name: String
        let amount: String
    }
}

let response = try await provider.generate(
    "Give me a pasta carbonara recipe",
    schema: Recipe.self,
    model: .claude(.haiku4_5)
)

print(response.value.name)
print(response.usage.totalTokens)
print(response.attempts)
```

## Implementation Details

### Strategy Selection

`AICore` determines the structured-output strategy from `provider.capabilities.structuredOutput`.

| Capability | Strategy |
|------------|----------|
| `supportsJSONSchema == true` | set `request.responseFormat = .jsonSchema(schema, name: T.schemaName)` |
| `supportsJSONMode == true` and caller requested `.json` | set `request.responseFormat = .json` |
| `defaultStrategy == .toolCallFallback` | use synthetic tool-call extraction |
| `defaultStrategy == .promptInjection` | inject schema + JSON-only instructions into `systemPrompt` |

Rules:

1. Prefer provider-native JSON Schema whenever available.
2. Native JSON mode is acceptable only when the caller explicitly requested `.json`, never as a replacement for `.jsonSchema` in the typed helper's default path.
3. Typed structured-output helpers must preserve `T.schemaName` when they opt into native JSON Schema mode.
4. Tool-call fallback is only for providers without native schema mode.
5. Prompt injection is the last resort.

### JSON Schema Generation from Codable

The default `AIStructured.jsonSchema` implementation supports a documented subset of Swift types:

- structs and nested structs with synthesized keyed `Codable`
- `String`, `Int`, `Double`, `Bool`, `Decimal`, and `Date`
- `Optional<T>`
- `Array<T>`
- string-backed enums that also conform to `CaseIterable`
- `CodingKeys`

It must reject and throw `AIError.unsupportedFeature` for shapes that cannot be reflected safely, including:

- custom `init(from:)` / `encode(to:)` implementations that change the serialized shape
- recursive or self-referential object graphs
- associated-value enums
- single-value or unkeyed top-level decoding shapes that cannot be safely represented as keyed structured types
- property-wrapper-driven serialization that cannot be discovered reliably
- polymorphic / discriminator-based decoding

This is intentionally conservative. Evidence beats guesses: if the SDK cannot prove the schema, it must require a manual override.

### Generated Schema Rules

- `String` -> `.string()`
- `Int` -> `.integer()`
- `Double` / `Float` / `Decimal` -> `.number()`
- `Bool` -> `.boolean()`
- `Date` -> `.string(format: "date-time")`
- `Optional<T>` -> schema for `T`, omitted from the object's `required` list
- `Array<T>` -> `.array(items: schema(T))`
- string-backed `CaseIterable` enums -> `.string(enumValues: [...])`
- keyed structs -> `.object(properties: ..., required: ...)`
- `CodingKeys` define external field names
- local validation must decode `Date` values using an ISO 8601 date-time strategy compatible with the generated schema

### Repair + Retry Flow

When the model returns invalid JSON or JSON that does not decode into `T`:

1. Try direct JSON decode.
2. If decode fails, attempt built-in repair.
3. If built-in repair fails and a custom `repair` closure exists, call it with the raw text and an `AIErrorContext`.
4. Re-validate the repaired text.
5. If repair still fails and retries remain, re-run the request with corrective context appended to `systemPrompt`.
6. After `maxRetries` attempts, throw `AIError.decodingError(...)`.

Cancellation rule:

- Check for task cancellation before running repair work, before sleeping for retry backoff, and before issuing the next corrective retry request. If cancelled, throw `AIError.cancelled` immediately without appending more corrective context.
- Normalize `CancellationError` values thrown by provider calls or custom repair handlers into `AIError.cancelled`.

Built-in repairs, in order:

1. Strip Markdown fences.
2. Trim leading/trailing non-JSON characters.
3. Extract the outermost JSON object or array when the model wrapped JSON in prose.

The retry prompt must be explicit and stable:

> Your previous response was not valid JSON matching the schema. Error: {error}. Return only valid JSON that matches the schema exactly.

### Native Provider Behavior

- **OpenAI Chat Completions**: use native `response_format` JSON Schema support. Still decode locally because responses may still be incomplete, refused, or truncated.
- **Anthropic Messages**: use native `output_config.format` JSON Schema support. Unsupported official model IDs and custom Anthropic-compatible deployments currently surface warnings rather than automatically switching to a fallback strategy.
- **Other providers**: use capability-driven fallback (`toolCallFallback` or `promptInjection`).

### Synthetic Tool-Call Fallback

For providers whose capability strategy is `.toolCallFallback`:

1. Create a synthetic tool named `_structured_output`.
2. Use the target schema as the tool's `inputSchema`.
3. Force tool choice when the provider supports it; otherwise instruct the model to call the synthetic tool.
4. Parse the resulting tool input JSON into `T`.
5. Never execute a user-side tool handler for this synthetic tool.

Failure modes:

- provider ignores forced tool choice
- provider emits a normal text answer instead of a tool call
- tool input is incomplete / invalid JSON

All three must flow through the same repair + retry path.

### Response Accounting

- `AIStructuredResponse.response` preserves the final provider response from the successful attempt.
- `AIStructuredResponse.usage` and `AIStructuredResponse.warnings` aggregate across the full structured-output operation so retries are not silently dropped from accounting.

### AIJSONSchema Notes

`AIJSONSchema` is already defined in Spec 01 as an `indirect enum`. Do not reintroduce placeholder types like `Box<T>`.

Supported schema features for v1:

- `string`, `number`, `integer`, `boolean`, `object`, `array`, `null`
- `oneOf`
- `ref`
- `description`
- `format`
- `additionalProperties`

Deliberately out of scope for v1 auto-generation:

- arbitrary `allOf` / `anyOf` synthesis
- discriminator synthesis
- remote refs

## File Layout

```
Sources/AICore/
├── StructuredOutput/
│   ├── AIStructured.swift
│   ├── AIStructuredResponse.swift
│   ├── AIJSONSchema.swift
│   ├── AIJSONSchemaGenerator.swift
│   ├── StructuredOutputGenerator.swift
│   └── StructuredOutputRepair.swift
```

## Tests

1. Simple flat struct schema generation.
2. Nested struct schema generation.
3. String-backed enum schema generation.
4. Optional properties are excluded from `required`.
5. Array properties generate array schemas.
6. `CodingKeys` are respected.
7. `Date` fields generate string/date-time schemas.
8. Unsupported reflected shapes throw `AIError.unsupportedFeature`.
9. Manual schema overrides replace auto-generation.
10. OpenAI-capable providers choose native JSON Schema strategy.
11. Anthropic-capable providers choose native JSON Schema strategy.
12. Synthetic tool fallback is selected when provider capabilities require it.
13. Prompt-injection fallback is selected when provider capabilities require it.
14. Built-in repair strips Markdown fences.
15. Built-in repair extracts JSON from surrounding prose.
16. Custom repair receives `AIErrorContext` and can return repaired text.
17. Retry on invalid JSON succeeds on a later attempt.
18. Exhausted retries throw `.decodingError`.
19. `AIStructuredResponse` preserves the raw `AIResponse`, while usage and warnings aggregate across retries.
20. Cancellation during repair or retry aborts immediately with `AIError.cancelled`.
21. Date-typed structured outputs decode ISO 8601 `date-time` payloads end to end.
22. JSON-mode-only providers use prompt injection by default, but honor explicit `.json` requests.
23. Retry accounting preserves warnings from failed attempts.
24. `CancellationError` thrown from provider work is normalized to `AIError.cancelled`.

## Acceptance Criteria

- [ ] `AICore` structured output depends only on `AIProvider.capabilities`, not provider modules.
- [ ] `AIStructured` supports a throwing default `jsonSchema` implementation plus manual overrides.
- [ ] Auto-generation is documented as a supported subset, not a blanket promise for arbitrary `Codable` shapes.
- [ ] Unsupported reflected shapes fail deterministically with `AIError.unsupportedFeature`.
- [ ] Native JSON Schema output is preferred whenever the provider advertises support.
- [ ] Anthropic native structured output is the default path, not synthetic tool fallback.
- [ ] Built-in repair runs before retries.
- [ ] Custom repair uses `AIErrorContext`, not a non-`Sendable` plain `Error`.
- [ ] Cancellation stops repair and corrective retries immediately.
- [ ] `AIStructuredResponse` carries the decoded value plus the underlying final `AIResponse`, with operation-level usage and warnings.
- [ ] Regression coverage includes Date decoding, JSON-mode selection, retry accounting, and cancellation normalization.
- [ ] No external dependencies.
