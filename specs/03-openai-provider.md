# Spec 03: OpenAI Provider

> Second provider. Stress-tests the abstraction - if two very different APIs both fit cleanly, the protocol is right.

## Review History

- 2026-03-10: Comprehensive implementation review completed; provider behavior, tests, and full-suite validation were brought back into alignment with this spec.

## Goal

Implement `OpenAIProvider` conforming to `AIProvider`, targeting the OpenAI Chat Completions API for generation plus the OpenAI Embeddings API for vector generation.

This spec is intentionally scoped to Chat Completions for generation. The OpenAI Responses API is a separate, future provider surface and must not be silently mixed into this implementation.

## Dependencies

- Spec 01 (AICore)
- Foundation `URLSession` only for the default transport

## Public API

```swift
public struct OpenAIProvider: AIProvider, Sendable {
    public init(
        apiKey: String,
        baseURL: URL? = nil,
        organization: String? = nil,
        transport: any AIHTTPTransport = URLSessionTransport(),
        defaultHeaders: [String: String] = [:]
    )

    public func complete(_ request: AIRequest) async throws -> AIResponse
    public func stream(_ request: AIRequest) -> AIStream
    public func embed(_ request: AIEmbeddingRequest) async throws -> AIEmbeddingResponse
    public var availableModels: [AIModel] { get }
    public var capabilities: AIProviderCapabilities { get }
}

extension AIModel {
    public enum GPT {
        case gpt4o
        case gpt4oMini
        case gpt4_1
        case gpt4_1Mini
        case gpt4_1Nano
        case gpt5
        case gpt5Mini
        case gpt5Nano
        case o3
        case o3Mini
        case o4Mini
        case custom(String)

        public var model: AIModel { get }
    }

    public static func gpt(_ variant: GPT) -> AIModel

    public enum OpenAIEmbedding {
        case textEmbedding3Small
        case textEmbedding3Large
        case custom(String)

        public var model: AIModel { get }
    }

    public static func openAIEmbedding(_ variant: OpenAIEmbedding) -> AIModel
}
```

### Usage

```swift
let provider = OpenAIProvider(apiKey: "sk-...")

let text = try await provider.complete("Hello", model: .gpt(.gpt4oMini))

let request = AIRequest(
    model: .gpt(.gpt4o),
    messages: [.user("List 3 colors as JSON")],
    responseFormat: .json
)
let response = try await provider.complete(request)

let vector = try await provider.embed(
    "swift concurrency",
    model: .openAIEmbedding(.textEmbedding3Small)
)
```

## Implementation Details

### Capabilities

`OpenAIProvider.capabilities` must report:

- `instructions.defaultFormat = .message(role: .system)`
- `instructions.reasoningModelFormatOverride = .message(role: .developer)`
- `instructions.reasoningModelIDs` includes the shipped reasoning families (`gpt5`, `gpt5Mini`, `gpt5Nano`, `o3`, `o3Mini`, `o4Mini`) plus any custom reasoning model IDs the provider ships
- `structuredOutput.supportsJSONMode = true`
- `structuredOutput.supportsJSONSchema = true`
- `structuredOutput.defaultStrategy = .providerNative`
- `inputs.supportsImages = true`
- `inputs.supportsDocuments = false` for this Chat Completions provider scope
- `inputs.supportedImageMediaTypes = ["image/jpeg", "image/png", "image/gif", "image/webp"]`
- `inputs.supportedDocumentMediaTypes = []`
- `tools.supportsParallelCalls = true`
- `tools.supportsForcedToolChoice = true`
- `streaming.includesUsageInStream = true`
- `embeddings.supportsEmbeddings = true`
- `embeddings.supportedInputKinds = [.text]`
- `embeddings.supportsBatchInputs = true`
- `embeddings.supportsDimensionOverride = true`
- `embeddings.maxInputsPerRequest = nil` unless the provider starts publishing a helper-level batch cap

### API Mapping

| AICore type | OpenAI Chat Completions |
|-------------|-------------------------|
| `AIRequest` | `POST /v1/chat/completions` body |
| `AIRequest.systemPrompt` | Leading `system` message for legacy chat models; leading `developer` message for `o`-series and GPT-5 reasoning models |
| `AIMessage(role: .user)` | `{"role": "user", ...}` |
| `AIMessage(role: .assistant)` | `{"role": "assistant", ...}` |
| `AIMessage(role: .tool)` | `{"role": "tool", "tool_call_id": ..., "content": ...}` |
| `AIContent.text` | `{"type": "text", "text": "..."}` |
| `AIContent.image` | `{"type": "image_url", "image_url": {"url": "data:...;base64,..."}}` |
| `AIContent.document` | Unsupported in this Chat Completions-backed provider version - emit warning or throw unsupported feature |
| `AIContent.toolUse` | Assistant `tool_calls[]` |
| `AITool` | `tools[]` with `type: "function"` |
| `AIToolChoice` | `tool_choice` |
| `allowParallelToolCalls` | `parallel_tool_calls` |
| `AIResponseFormat.json` | `response_format: {"type": "json_object"}` |
| `AIResponseFormat.jsonSchema` | `response_format: {"type": "json_schema", "json_schema": {...}}` |
| `maxTokens` | Prefer `max_completion_tokens`; only fall back to legacy `max_tokens` where required by custom compatible backends |
| `temperature` | `temperature` |
| `topP` | `top_p` |
| `stopSequences` | `stop` when the selected model supports it |
| `metadata` | `metadata` |

### Model-Family Rules

OpenAI's modern model surface is not uniform. The provider must normalize requests by model family.

Rules:

1. For `o`-series and GPT-5 reasoning models, serialize `systemPrompt` as a `developer` message.
2. For older chat models, serialize `systemPrompt` as a `system` message.
3. Prefer `max_completion_tokens` over `max_tokens`.
4. `stop` is not supported with the latest reasoning models `o3` and `o4-mini`; if requested, emit `AIProviderWarning` and drop it.
5. Model-specific incompatibilities (for example `topP` on reasoning models) must warn, never silently disappear.
6. Embedding models are validated separately and must not inherit Chat Completions-only request normalization.

### Structured Output

OpenAI supports native JSON mode and native schema-backed structured output.

Rules:

1. `AIResponseFormat.json` maps to `response_format: {"type": "json_object"}`.
2. `AIResponseFormat.jsonSchema` maps to `response_format: {"type": "json_schema", "json_schema": {"name": ..., "schema": ..., "strict": true}}`.
3. The provider must synthesize a stable schema name when the caller does not supply one through a higher-level helper.
4. The SDK still validates and decodes locally even when OpenAI enforces schema output.

### Embeddings

OpenAI embeddings support is required for v1 through `POST /v1/embeddings`.

| AICore type | OpenAI Embeddings API |
|-------------|------------------------|
| `AIEmbeddingRequest.model` | `model` |
| `AIEmbeddingRequest.inputs` | `input` string or array of strings |
| `AIEmbeddingRequest.dimensions` | `dimensions` when the selected model supports it |
| `AIEmbeddingRequest.headers` | merged request headers |
| `AIEmbeddingResponse.embeddings` | `data[].embedding` |
| `AIEmbedding.index` | `data[].index` |
| `AIEmbeddingResponse.usage` | `usage.total_tokens -> inputTokens`, `outputTokens = 0` |

Rules:

1. Use float vectors in v1; do not expose alternate provider-specific encoding formats yet.
2. `dimensions` must be forwarded only for embedding models that support it.
3. `availableModels` includes shipped embedding model IDs alongside chat-completions model IDs.

### Streaming (SSE)

| OpenAI SSE chunk | AIStreamEvent |
|------------------|---------------|
| first chunk with `id` / `model` | `.start(id:, model:)` |
| `choices[0].delta.content` | `.delta(.text(...))` |
| `choices[0].delta.tool_calls` | `.toolUseStart(id:, name:)` and `.delta(.toolInput(id:, jsonDelta:))` |
| final usage chunk with `stream_options.include_usage` | `.usage(...)` |
| `choices[0].finish_reason` | `.finish(...)` |
| `data: [DONE]` | stream ends |

Request rule:

- Streaming requests must include `stream_options: {"include_usage": true}` so `AIUsage` can be surfaced when the backend supports it.
- If the SSE connection drops after any streamed event and no terminal finish reason arrives, surface `AIError.streamInterrupted`.

### Finish Reason Mapping

| OpenAI finish reason | AIFinishReason |
|----------------------|----------------|
| `stop` | `.stop` |
| `length` | `.maxTokens` |
| `tool_calls` | `.toolUse` |
| `content_filter` | `.contentFilter` |
| anything else | `.unknown(...)` |

### Error Mapping

| HTTP Status | AIError |
|-------------|---------|
| 400 | `.invalidRequest(message)` |
| 401 | `.authenticationFailed` |
| 404 | `.modelNotFound(model)` |
| 429 | `.rateLimited(retryAfter:)` |
| 500+ | `.serverError(statusCode:, message:)` |
| transport failure | `.networkError(...)` |
| decode failure | `.decodingError(...)` |

### Headers

```
Authorization: Bearer {apiKey}
Content-Type: application/json
OpenAI-Organization: {organization}   // optional
```

### baseURL override

`baseURL` is intended for OpenAI-compatible Chat Completions and Embeddings endpoints that preserve the OpenAI wire contract.

Do not claim Azure OpenAI compatibility in this provider spec. Azure changes path and request-shape expectations enough that it should be a separate provider.

### Provider Configuration Knobs

- Stable cross-request knobs are `apiKey`, `baseURL`, `organization`, `transport`, and `defaultHeaders`.
- Model-specific experiments or compatible-backend quirks stay in headers or custom model IDs until they become stable enough for a first-class API.
- Do not widen the public initializer surface for Response API concepts in this Chat Completions-backed provider.

### Retry Integration

Same rules as Spec 01 and Anthropic:

- Provider maps failures, SDK handles retry.
- Parse `retry-after-ms` first, then `retry-after`.
- Never retry after the first streamed event has been emitted.
- Propagate cancellation through active transport work, pending retry backoff, and embedding requests.

### Usage Mapping

Map OpenAI usage to `AIUsage`:

Chat Completions:

```
prompt_tokens -> inputTokens
completion_tokens -> outputTokens
prompt_tokens_details.cached_tokens -> inputTokenDetails.cachedTokens
completion_tokens_details.reasoning_tokens -> outputTokenDetails.reasoningTokens
```

Embeddings:

```
total_tokens -> inputTokens
outputTokens -> 0
```

## File Layout

```
Sources/AIProviderOpenAI/
├── OpenAIProvider.swift
├── OpenAIModels.swift
├── Internal/
│   ├── OpenAIRequestBuilder.swift
│   ├── OpenAIEmbeddingRequestBuilder.swift
│   ├── OpenAIEmbeddingResponseParser.swift
│   ├── OpenAIResponseParser.swift
│   ├── OpenAIStreamParser.swift
│   └── OpenAIErrorMapper.swift
└── Documentation.docc/
    └── OpenAIProvider.md
```

## Tests

Use `MockTransport` by default.

1. Simple completion decodes into `AIResponse`.
2. Streaming SSE yields text deltas and finishes cleanly.
3. Legacy chat models serialize `systemPrompt` as a `system` message.
4. `o`-series / GPT-5 reasoning models serialize `systemPrompt` as a `developer` message.
5. Vision requests encode base64 image URLs correctly.
6. Tool definitions serialize as OpenAI `function` tools.
7. Tool-use responses decode from assistant `tool_calls`.
8. `.json` response format sets `json_object`.
9. `.jsonSchema` response format sets strict `json_schema` with a schema name.
10. `max_completion_tokens` is preferred over `max_tokens`.
11. Unsupported `stop` on `o3` / `o4-mini` emits a warning.
12. Unsupported document input for this provider scope warns or throws deterministically.
13. Streaming requests include `stream_options.include_usage`.
14. `baseURL` override rewrites request URLs.
15. 429 responses parse `retry-after-ms` correctly.
16. Detailed usage fields map into `AIUsage` token detail breakdowns.
17. Custom headers from `AIRequest.headers` are forwarded.
18. Stream cancellation stops transport work and does not retry.
19. `embed("...")` sends `/v1/embeddings` and decodes a vector response.
20. Batch embedding inputs serialize as OpenAI array `input` values.
21. Embedding `dimensions` is forwarded for models that support it.
22. Embedding usage maps `total_tokens` into `AIUsage.inputTokens` with `outputTokens == 0`.
23. `availableModels` includes shipped embedding model IDs.

## Acceptance Criteria

- [ ] `OpenAIProvider` conforms to `AIProvider` and publishes non-default capabilities.
- [ ] The provider is explicitly scoped to OpenAI Chat Completions, not the Responses API.
- [ ] Non-streaming completions work with text, vision, tool use, JSON mode, and strict JSON Schema mode.
- [ ] Streaming works with text deltas, tool-input deltas, usage, and finish reasons.
- [ ] `systemPrompt` is normalized to `system` vs `developer` message role by model family.
- [ ] `max_completion_tokens` is the preferred token-limit field.
- [ ] Unsupported `stop` on `o3` / `o4-mini` emits warnings instead of silently failing.
- [ ] `AIModel.gpt(...)` resolves to current model IDs and still allows `custom(String)`.
- [ ] `AIModel.openAIEmbedding(...)` resolves to shipped embedding model IDs and still allows `custom(String)`.
- [ ] Detailed token usage is parsed into `AIUsage` details.
- [ ] Embeddings are supported through `/v1/embeddings` with text input and optional `dimensions` forwarding.
- [ ] `baseURL`, custom headers, and custom transport are supported.
- [ ] Input capabilities advertise supported image MIME types and no document MIME types for this provider scope.
- [ ] All 23 test cases pass.
