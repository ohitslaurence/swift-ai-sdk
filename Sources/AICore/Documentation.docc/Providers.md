# Providers

Shipped provider modules live alongside `AICore` and conform to `AIProvider`.

- `AIProviderAnthropic` implements the Anthropic Messages API with streaming, tools, images, documents, and native JSON Schema output.
- `AIProviderOpenAI` implements Chat Completions plus embeddings, streamed usage, image input, and native structured output.
- The `AI` umbrella module re-exports all shipped providers for convenience.
