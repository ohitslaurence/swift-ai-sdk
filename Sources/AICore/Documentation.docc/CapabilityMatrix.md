# Capability Matrix

Every provider exposes an `AIProviderCapabilities` value so higher-level helpers can adapt behavior without hard-coding provider checks.

- `instructions` describes how top-level instructions are serialized.
- `structuredOutput` describes native JSON/JSON Schema support and fallback strategy.
- `inputs` advertises image and document support, including accepted MIME types.
- `tools`, `streaming`, and `embeddings` describe forced tool choice, streamed usage, and embedding features.

Current shipped providers use this surface to distinguish features such as Anthropic document support and OpenAI embeddings.
