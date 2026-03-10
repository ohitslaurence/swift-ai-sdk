# Spec 09: Provider Capability Matrix

> A documentation appendix for humans. Runtime behavior still comes from `AIProviderCapabilities` plus provider request builders.

## Goal

Document shipped-provider feature support in one place so contributors and users can quickly answer "does this provider support X?" without reverse-engineering multiple specs.

This appendix is descriptive, not authoritative executable logic. `AICore` helpers must continue to consult `AIProviderCapabilities` and provider/model validation at runtime.

## Scope

- `AnthropicProvider` from Spec 02
- `OpenAIProvider` from Spec 03
- OpenAI generation scope remains Chat Completions; embeddings use the separate `/v1/embeddings` endpoint described in Spec 07

## Matrix

| Capability | AnthropicProvider | OpenAIProvider | Notes |
|------------|-------------------|----------------|-------|
| Instruction format | Top-level `system` field | `system` or `developer` message by model family | See `AIInstructionCapabilities` |
| JSON mode | No dedicated JSON-object mode | Yes | Anthropic `.json` normalizes to schema mode |
| JSON Schema | Yes, native `output_config.format` | Yes, native `response_format.json_schema` | Native schema is the preferred structured-output path for both |
| Images | Yes | Yes | Both advertise provider-level image support |
| Documents | Yes | No for this Chat Completions provider scope | OpenAI Chat Completions document input stays unsupported in v1 |
| Tools | Yes | Yes | Both support parallel tool calls and forced tool choice |
| Streaming usage | Yes | Yes | OpenAI requires `stream_options.include_usage`; Anthropic emits usage in message deltas |
| Embeddings | No | Yes | Anthropic uses the default unsupported path; OpenAI uses `/v1/embeddings` |

## Provider Notes

### AnthropicProvider

- `AIRequest.systemPrompt` maps to the top-level `system` field.
- `.json` requests normalize to `.jsonSchema(.anyJSON)` before request serialization.
- Tool transcript replay uses `user` turns with `tool_result` content blocks because Anthropic has no `tool` role.
- Current spec set does not define Anthropic embeddings support.

### OpenAIProvider

- `AIRequest.systemPrompt` maps to `system` for legacy chat models and `developer` for reasoning-model families.
- JSON-object mode and strict JSON Schema mode are both supported natively.
- Document input is intentionally unsupported in this Chat Completions-backed provider surface.
- Embeddings are supported separately from generation through `/v1/embeddings`.

## DocC Article Outline

### `CapabilityMatrix.md`

Suggested sections:

1. How to read the matrix.
2. Provider-level capability defaults vs model-level validation.
3. Anthropic caveats.
4. OpenAI caveats.
5. How to inspect capabilities in code.

Starter example:

```swift
let capabilities = provider.capabilities

if capabilities.structuredOutput.supportsJSONSchema {
    print("Schema mode available")
}

if capabilities.embeddings.supportsEmbeddings {
    print("Embeddings available")
}
```

## Caveats

- Capability values are provider-level defaults, not a replacement for model-level validation.
- A matrix cell of "Yes" still allows model-specific warnings or `AIError.unsupportedFeature` for incompatible combinations.
- This appendix should be updated whenever a shipped provider adds or removes first-class support for a documented capability.

## Acceptance Criteria

- [ ] The shipped providers are documented side by side in one matrix.
- [ ] The matrix covers instruction format, JSON mode, JSON Schema, images, documents, tools, streaming usage, and embeddings.
- [ ] Anthropic and OpenAI notes match the behavior described in Specs 02, 03, and 07.
- [ ] The appendix includes a DocC article outline with an example of capability inspection in code.
- [ ] The appendix explicitly states that runtime behavior still comes from `AIProviderCapabilities` and provider/model validation.
