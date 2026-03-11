# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-03-11

Initial release of the Swift AI SDK.

### Added

- **Core protocols** — `AIProvider`, `AIRequest`, `AIResponse`, `AIStream`,
  `AIMessage`, `AIContent`, `AIModel`, `AIError`, and all supporting types.
- **Anthropic provider** — `AnthropicProvider` with Messages API support,
  top-level system prompt, document input, streaming with usage deltas, and
  structured output via native `output_config.format`.
- **OpenAI provider** — `OpenAIProvider` with Chat Completions API support,
  system/developer message by model family, JSON mode, JSON Schema structured
  output, and streaming with `stream_options.include_usage`.
- **Structured output** — `AIStructured` protocol with automatic JSON Schema
  generation, provider-native enforcement, built-in repair, and corrective
  retry. Supports structs, nested types, optionals, arrays, string-backed
  enums, and `Date` fields.
- **Tool use and agents** — `AITool` definition (raw and strongly-typed),
  `completeWithTools` and `streamWithTools` multi-step execution loops with
  configurable stop conditions, approval gates, and tool call repair. `Agent`
  type for reusable tool-calling units.
- **SwiftUI integration** — `AIConversation` for multi-turn chat state,
  `AIStreamState` for standalone streaming, `StreamingText` view with cursor
  animation, `AIMessageList` with auto-scroll, and smooth streaming support.
- **Embeddings** — `AIEmbeddingRequest`, `AIEmbeddingResponse`, `embed()` and
  `embedMany()` helpers with automatic batching, cancellation, and retry.
  OpenAI `/v1/embeddings` implementation with dimension override support.
- **Middleware** — `AIMiddleware` protocol with `withMiddleware()` provider
  wrapper. Built-in `DefaultSettingsMiddleware` and `LoggingMiddleware`.
- **Observability** — `AITelemetrySink` protocol with `withTelemetry()` provider
  wrapper. Structured events for completions, streams, embeddings, tool loops,
  and structured output retries. Privacy-aware redaction, metrics, and usage
  accounting.
- **Retry and timeout** — `RetryPolicy` with exponential backoff and
  server-directed delays. `AITimeout` with total, step, and chunk timeouts.
- **Usage reporting** — `AIUsage` with input/output tokens, cache tokens,
  reasoning tokens, and `totalTokens` computed property. Usage propagated
  through streams, tool loops, and structured output retries.
- **Provider capabilities** — `AIProviderCapabilities` matrix covering
  instruction format, structured output, input media, tools, streaming, and
  embeddings per provider.
- **Documentation** — DocC articles for Getting Started, Structured Output,
  Tool Use, Embeddings, Middleware, Observability, Capability Matrix, and
  provider-specific reference.
