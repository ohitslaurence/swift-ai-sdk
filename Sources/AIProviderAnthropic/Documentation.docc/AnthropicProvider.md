# ``AnthropicProvider``

Anthropic Messages API support for `AICore` requests, streaming, tools, vision, documents, and native JSON Schema output.

`AnthropicProvider` forwards `AIRequest.systemPrompt` through the top-level `system` field, adapts tool results into Anthropic `tool_result` blocks, and normalizes `.json` requests to native schema mode.

When a request relies on Anthropic features with model-specific support boundaries, the provider preserves those adaptations and surfaces compatibility warnings on the resulting `AIResponse` instead of silently dropping fields.

## Behavior Notes

- `AIRequest.messages` map onto the Anthropic Messages API, including assistant `tool_use` replay and tool-result adaptation through `user` turns.
- Streaming uses Anthropic SSE events and surfaces text deltas, tool-input deltas, usage updates, and a single terminal finish reason.
- `AIRequest.maxTokens` defaults to `4096` when omitted, matching the provider spec.
- `embed(_:)` stays on the protocol default unsupported path; this provider does not call unofficial Anthropic embedding endpoints.

## Structured Output

- `AIResponseFormat.jsonSchema` maps to Anthropic native `output_config.format`.
- `AIResponseFormat.json` is normalized to `.jsonSchema(.anyJSON)` before request serialization.
- Current Anthropic documentation officially lists native structured-output support for Claude Opus 4.6/4.5, Claude Sonnet 4.6/4.5, and Claude Haiku 4.5.
- Requests targeting legacy official model IDs or custom Anthropic-compatible deployment IDs still forward native structured-output fields, but surface `AIProviderWarning` values when support is unsupported or unverified.

## Usage and Errors

- Anthropic cache token usage maps into `AIUsage.inputTokenDetails`.
- HTTP, transport, streaming, and decode failures are normalized into `AIError` values before surfacing to callers.
- Provider `defaultHeaders` are merged first, then `AIRequest.headers`, while auth/version/content-type remain provider-controlled.
- Request and stream warning metadata is preserved through collected `AIResponse` values, including structured-output compatibility warnings.
