# Structured Output

`AICore` supports schema-driven structured output through `AIProvider.generate(_:schema:model:...)` and `AIProvider.generate(_:schema:...)`.

- Strategy selection is capability-driven: native JSON Schema first, then native JSON mode, synthetic tool-call fallback, and finally prompt injection.
- Native JSON mode is only selected when a full `AIRequest` explicitly asks for `.json`; typed helper defaults never substitute JSON mode for schema mode.
- Returned text is still decoded and validated locally, even when the provider enforces a native schema.
- Structured-output decoding accepts ISO 8601 `date-time` values to match generated `Date` schemas.
- Native JSON Schema requests preserve `AIStructured.schemaName` when the downstream provider requires a stable schema identifier.
- Failed decodes go through built-in repair, optional custom repair, and corrective retry prompts before surfacing `AIError.decodingError`.
- `AIStructuredResponse.usage` and `AIStructuredResponse.warnings` reflect the full structured-output operation, not just the final attempt.
- Shipped native-schema providers currently include Anthropic Messages and OpenAI Chat Completions.
