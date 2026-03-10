# Spec 07: Embeddings

> Text to vectors, without locking callers to one vendor's endpoint shape.

## Goal

Add provider-agnostic embeddings support to `AICore`. A developer should be able to request one embedding or many embeddings through one stable API, while providers advertise batching and dimension behavior through capabilities instead of custom cross-module hooks.

## Dependencies

- Spec 01 (core embeddings types, capabilities, retry, timeout, middleware)
- Spec 03 for shipped OpenAI embeddings support
- No dependency from `AICore` to provider modules

## Public API

The low-level protocol entry point lives in Spec 01:

```swift
public protocol AIProvider: Sendable {
    func embed(_ request: AIEmbeddingRequest) async throws -> AIEmbeddingResponse
}
```

This spec defines the higher-level convenience surface built on top of it:

```swift
extension AIProvider {
    public func embed(
        _ text: String,
        model: AIModel,
        dimensions: Int? = nil,
        retryPolicy: RetryPolicy = .default,
        timeout: AITimeout = .default,
        headers: [String: String] = [:]
    ) async throws -> AIEmbedding

    public func embedMany(
        _ texts: [String],
        model: AIModel,
        dimensions: Int? = nil,
        batchSize: Int? = nil,
        retryPolicy: RetryPolicy = .default,
        timeout: AITimeout = .default,
        headers: [String: String] = [:]
    ) async throws -> AIEmbeddingResponse
}
```

## Usage

```swift
let provider = OpenAIProvider(apiKey: "sk-...")

let queryVector = try await provider.embed(
    "swift concurrency",
    model: .openAIEmbedding(.textEmbedding3Small)
)

let documents = try await provider.embedMany(
    [
        "actors isolate mutable state",
        "AIStream is single-consumer",
        "system prompts live on AIRequest"
    ],
    model: .openAIEmbedding(.textEmbedding3Small),
    dimensions: 1024
)

print(queryVector.dimensions)
print(documents.embeddings.count)
print(documents.usage?.inputTokens ?? 0)
```

## Implementation Details

### Request Validation

- `AIEmbeddingRequest.inputs` must not be empty.
- `embedMany(_ texts: ...)` must reject an empty input array with `AIError.invalidRequest`.
- `batchSize`, when provided, must be greater than `0`.
- `dimensions`, when provided, must be greater than `0`.
- v1 supports only `AIEmbeddingInput.text`; providers must reject any future unsupported input kind explicitly rather than silently dropping it.

### Batching Rules

`embedMany(...)` is an `AICore` helper. It may satisfy one logical call through multiple provider calls.

Effective batch size:

1. Use the caller-supplied `batchSize` when present.
2. Else use `provider.capabilities.embeddings.maxInputsPerRequest` when present.
3. Else if `supportsBatchInputs == true`, send all inputs in one provider request.
4. Else fall back to one input per provider request.

Aggregation rules:

- Preserve the caller's original input order.
- Rewrite `AIEmbedding.index` values so they match the original logical input positions across the full `embedMany(...)` call, not per-batch local indexes.
- Aggregate `AIUsage` by summing `inputTokens`, keeping `outputTokens == 0`, and merging optional token detail fields when present.
- Concatenate warnings in batch order.
- All batches must target the same `AIModel`; if a backend reports inconsistent response model IDs across batches, keep the first model string and append an `AIProviderWarning`.

### Capabilities Contract

`AIProviderCapabilities.embeddings` drives helper behavior:

- `supportsEmbeddings == false` means `embed(_:)` uses the default unsupported path.
- `supportsBatchInputs == false` means `embedMany(...)` must split into single-input requests.
- `supportsDimensionOverride == true` means the provider supports a first-class dimension field for at least one model family. Model-level validation still decides whether a particular embedding model accepts it.
- `maxInputsPerRequest` is advisory. If `nil`, `AICore` does not apply any automatic provider-imposed split and may send all inputs in one request when batching is otherwise supported; callers may still choose an explicit `batchSize`.

### Retry and Cancellation Semantics

- Retry rules from Spec 01 apply per provider batch request.
- If one batch fails, `embedMany(...)` throws that error and does not return a partial aggregated response.
- Cancelling the parent task must cancel the active provider request, any pending retry backoff, and any remaining unsent batches.
- If callers need partial-progress semantics, they should batch manually rather than relying on `embedMany(...)`.

### Provider Mappings

#### OpenAI

OpenAI support is required for v1 through `POST /v1/embeddings`.

| AICore type | OpenAI Embeddings API |
|-------------|------------------------|
| `AIEmbeddingRequest.model` | `model` |
| `AIEmbeddingRequest.inputs` | `input` string or array of strings |
| `AIEmbeddingRequest.dimensions` | `dimensions` when supported by the selected model |
| `AIEmbeddingRequest.headers` | merged request headers |
| `AIEmbeddingResponse.embeddings` | `data[].embedding` |
| `AIEmbedding.index` | `data[].index` |
| `AIEmbeddingResponse.usage` | `usage.total_tokens -> inputTokens`, `outputTokens = 0` |

Rules:

- Use float vectors in v1. Do not expose provider-specific alternate encoding formats in the public API yet.
- Request builders must continue to validate model-specific `dimensions` support and emit warnings or `AIError.unsupportedFeature` rather than silently dropping the field.
- `availableModels` includes shipped embedding models alongside chat-completions models.

#### Anthropic

Anthropic does not have a shipped embeddings surface in the current spec set.

Rules:

- `AnthropicProvider.capabilities.embeddings` stays `.default`.
- `AnthropicProvider` uses the protocol's default `embed(_:)` implementation, which throws `AIError.unsupportedFeature`.
- Do not invent an Anthropic compatibility layer or speculative unofficial endpoint.

### Out of Scope for v1

- vector-store integrations
- nearest-neighbor search helpers
- cosine similarity or normalization utilities
- multimodal embeddings
- provider-managed caching semantics beyond surfaced warnings and usage

## File Layout

```
Sources/AICore/
└── Embeddings/
    ├── AIEmbedding.swift
    ├── AIEmbeddingRequest.swift
    └── AIEmbeddingResponse.swift

Sources/AIProviderOpenAI/Internal/
├── OpenAIEmbeddingRequestBuilder.swift
└── OpenAIEmbeddingResponseParser.swift
```

## DocC Article Outline

### `Embeddings.md`

Suggested sections:

1. What embeddings are and when to use them.
2. One-input `embed(_:)` example.
3. Batch `embedMany(...)` example.
4. Dimension overrides and batching behavior.
5. Provider support caveats and unsupported-provider behavior.

Starter examples:

```swift
let vector = try await provider.embed(
    "swift concurrency",
    model: .openAIEmbedding(.textEmbedding3Small)
)

print(vector.dimensions)
```

```swift
let response = try await provider.embedMany(
    ["actors", "streams", "system prompts"],
    model: .openAIEmbedding(.textEmbedding3Small),
    batchSize: 2
)

for embedding in response.embeddings {
    print(embedding.index, embedding.dimensions)
}
```

## Opt-In Integration Test Guidance

Recommended live-test placement:

- `Tests/AIProviderOpenAITests/Integration/OpenAIEmbeddingIntegrationTests.swift`

Rules:

- Gate every live test behind `AI_INTEGRATION_TESTS=1` and `OPENAI_API_KEY`.
- Gate every live test behind `AI_INTEGRATION_TESTS=1` and a non-empty `OPENAI_API_KEY`.
- Use the smallest practical embedding model for cost control.
- Assert vector count, index ordering, positive dimensions, and basic usage presence.
- Do not assert exact float values, exact token counts, or exact latency.
- Skip cleanly when environment variables are absent.

Suggested gate:

```swift
guard ProcessInfo.processInfo.environment["AI_INTEGRATION_TESTS"] == "1",
      let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
      !apiKey.isEmpty
else {
    throw XCTSkip("Embeddings integration tests require AI_INTEGRATION_TESTS=1 and OPENAI_API_KEY")
}
```

## Tests

1. `embed("...")` sends a single text input and returns the first embedding.
2. `embedMany(...)` preserves input order across multiple vectors.
3. `embedMany(...)` splits requests when `maxInputsPerRequest` is smaller than the input count.
4. `embedMany(...)` falls back to one provider request per input when `supportsBatchInputs == false`.
5. Empty embedding input arrays throw `AIError.invalidRequest`.
6. Invalid `batchSize` or `dimensions` values throw `AIError.invalidRequest`.
7. Aggregated batch responses rewrite embedding indexes to original logical positions.
8. Aggregated usage sums per-batch `inputTokens` and preserves `outputTokens == 0`.
9. Providers without embeddings support throw `AIError.unsupportedFeature` without making a transport call.
10. OpenAI request building maps single-input embeddings correctly.
11. OpenAI request building maps array-input embeddings correctly.
12. OpenAI request building forwards `dimensions` when supported.
13. Unsupported `dimensions` on a selected model warn or fail deterministically.
14. OpenAI response parsing decodes float vectors and indexes.
15. OpenAI embedding usage maps `total_tokens` into `AIUsage.inputTokens`.
16. Cancellation stops active embedding work and prevents unsent batches from starting.

## Acceptance Criteria

- [ ] `AICore` exposes a provider-agnostic embeddings API through `AIEmbeddingRequest`, `AIEmbeddingResponse`, `AIEmbedding`, `embed(_:)`, and `embedMany(...)`.
- [ ] Embedding behavior is capability-driven through `AIProviderCapabilities.embeddings`.
- [ ] `embedMany(...)` can batch or split requests without changing the caller-visible order contract.
- [ ] Aggregated embedding responses preserve warnings and summed usage.
- [ ] Cancellation and retry behavior are documented for multi-batch embedding calls.
- [ ] OpenAI provider support is specified through `/v1/embeddings`.
- [ ] Anthropic support is explicitly unsupported rather than ambiguous.
- [ ] The spec includes a DocC article outline and opt-in live-test guidance for embeddings.
- [ ] No provider-specific embedding behavior requires `AICore` to import a provider module.
- [ ] All 16 test cases pass.
