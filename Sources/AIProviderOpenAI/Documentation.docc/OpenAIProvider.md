# ``OpenAIProvider``

OpenAI Chat Completions and Embeddings support for `AICore` requests, streaming, tool use, vision inputs, structured output, and token accounting.

`OpenAIProvider` keeps this surface intentionally scoped to Chat Completions for generation plus `/v1/embeddings` for vectors. It does not silently mix in the Responses API.

## Behavior Notes

- `AIRequest.systemPrompt` is serialized as a leading `system` message for legacy chat models and as a leading `developer` message for GPT-5 and `o`-series reasoning models.
- Streaming uses OpenAI SSE events and surfaces start, text deltas, tool-input deltas, usage updates, and a single terminal finish reason.
- `AIRequest.maxTokens` prefers `max_completion_tokens`, with a compatibility fallback to legacy `max_tokens` for custom OpenAI-compatible backends that reject the modern field.
- Document inputs remain unsupported for this provider surface; unsupported inputs fail deterministically instead of being dropped.

## Structured Output

- `AIResponseFormat.json` maps to OpenAI native JSON mode.
- `AIResponseFormat.jsonSchema` maps to strict native `json_schema` enforcement.
- Schema-backed responses still flow through the SDK's local decoding and validation pipeline.

## Embeddings

- `embed(_:)` and `embedMany(...)` target `/v1/embeddings`.
- Single embedding inputs serialize as a string; batch requests serialize as an array of strings.
- `dimensions` is forwarded for known dimension-configurable OpenAI embedding models and otherwise surfaces an `AIProviderWarning` when dropped.

## Usage and Errors

- Prompt/completion token accounting maps into `AIUsage`, including cached prompt tokens and reasoning output tokens when OpenAI returns detailed usage.
- HTTP, transport, streaming, and decode failures are normalized into `AIError` values before surfacing to callers.
- Provider `defaultHeaders` are merged first, then request-level headers, while auth and content-type remain provider-controlled.
- Request and compatibility warnings are preserved on collected `AIResponse` and `AIEmbeddingResponse` values.
