# Capability Matrix

Every provider exposes an ``AIProviderCapabilities`` value so higher-level
helpers can adapt behavior without hard-coding provider checks. This article
documents shipped-provider feature support in one place.

> Important: This matrix is descriptive, not authoritative executable logic.
> Runtime behavior still comes from ``AIProviderCapabilities`` and
> provider/model validation — not from this document.

## How to read the matrix

Each row represents a feature area. "Yes" means the provider advertises
first-class support at the provider level. A "Yes" cell still allows
model-specific warnings or ``AIError/unsupportedFeature(_:)`` for
incompatible model/feature combinations.

Capability values are **provider-level defaults**, not a replacement for
model-level validation.

## Provider capability defaults vs model-level validation

``AIProviderCapabilities`` captures what a provider *generally* supports.
Individual models may not support every advertised capability. For example,
a provider may advertise image support, but a specific text-only model
within that provider could still reject image inputs at request time.

Higher-level helpers in `AICore` consult ``AIProviderCapabilities`` to
choose serialization strategies (e.g. native JSON Schema vs prompt
injection), but model-specific validation can still reject unsupported
combinations.

## Matrix

| Capability | AnthropicProvider | OpenAIProvider | Notes |
|---|---|---|---|
| Instruction format | Top-level `system` field | `system` or `developer` message by model family | See ``AIInstructionCapabilities`` |
| JSON mode | No | Yes | Anthropic `.json` normalizes to schema mode |
| JSON Schema | Yes | Yes | Native schema is the preferred structured-output path for both |
| Images | Yes | Yes | Both advertise provider-level image support |
| Documents | Yes | No | OpenAI Chat Completions document input is unsupported in v1 |
| Tools | Yes | Yes | Both support parallel tool calls and forced tool choice |
| Streaming usage | Yes | Yes | OpenAI requires `stream_options.include_usage`; Anthropic emits usage in message deltas |
| Embeddings | No | Yes | OpenAI uses `/v1/embeddings`; Anthropic uses the default unsupported path |

## Anthropic caveats

- ``AIRequest/systemPrompt`` maps to the top-level `system` field
  (``AIInstructionFormat/topLevelSystemPrompt``).
- `.json` structured-output requests normalize to `.jsonSchema(.anyJSON)`
  before request serialization — there is no dedicated JSON-object mode.
- Tool transcript replay uses `user` turns with `tool_result` content blocks
  because Anthropic has no `tool` role.
- The current spec set does not define Anthropic embeddings support.
  ``AIEmbeddingCapabilities/supportsEmbeddings`` is `false`.

## OpenAI caveats

- ``AIRequest/systemPrompt`` maps to a `system` message for standard chat
  models and a `developer` message for reasoning-model families (e.g.
  o3, o4-mini, GPT-5).
- Both JSON-object mode (``AIStructuredOutputCapabilities/supportsJSONMode``)
  and strict JSON Schema mode
  (``AIStructuredOutputCapabilities/supportsJSONSchema``) are natively
  supported.
- Document input is intentionally unsupported in this Chat
  Completions-backed provider surface.
- Embeddings are supported separately from generation through
  `/v1/embeddings`, with batch inputs and dimension override support.

## Inspecting capabilities in code

```swift
let capabilities = provider.capabilities

if capabilities.structuredOutput.supportsJSONSchema {
    print("Schema mode available")
}

if capabilities.embeddings.supportsEmbeddings {
    print("Embeddings available")
}

if capabilities.inputs.supportsDocuments {
    print("Document input supported")
}
```
