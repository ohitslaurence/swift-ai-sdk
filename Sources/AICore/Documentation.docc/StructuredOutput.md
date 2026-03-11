# Structured Output

`AICore` supports schema-driven structured output through `AIProvider.generate(_:schema:model:...)` and `AIProvider.generate(_:schema:...)`.

- Strategy selection is capability-driven: native JSON Schema first, then native JSON mode, synthetic tool-call fallback, and finally prompt injection.
- Returned text is still decoded and validated locally, even when the provider enforces a native schema.
- Failed decodes go through built-in repair, optional custom repair, and corrective retry prompts before surfacing `AIError.decodingError`.
- Shipped native-schema providers currently include Anthropic Messages and OpenAI Chat Completions.
