# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **Tool execution loops** — Cancellation during approval waits or in-flight tool
  execution no longer commits partial steps or synthesizes transcript-visible
  cancellation results.
- **Tool call repair** — Repair now triggers only for typed input decode failures,
  preserving ordinary tool handler failures as transcript-visible error results
  without unnecessary repair attempts.
- **Streaming tool loops** — Stitched streams now preserve provider warnings,
  keep specific stream errors when available after partial output, and avoid
  silently dropping events under slow consumers.
- **Usage accounting** — `AIToolResponse.totalUsage` now preserves detailed token
  accounting across every completed tool step and the terminal response.
- **SwiftUI tool replay** — `AIConversation` no longer commits a duplicate
  assistant text turn before a tool-step transcript is appended.

## [0.1.2] — 2026-03-11

### Fixed

- **Anthropic model IDs** — `claude-opus-4` → `claude-opus-4-0` and
  `claude-sonnet-4` → `claude-sonnet-4-0` to match actual API aliases.

### Added

- **OpenAI models** — gpt-5-pro, gpt-5.4, gpt-5.4-pro, gpt-5.1-codex-max,
  gpt-5.3-codex, gpt-5.3-codex-spark, o1, o1-mini, o1-pro, o3-pro.
- **Model sync tooling** — `Tools/sync-models.sh` diffs local model constants
  against models.dev for verification.

## [0.1.1] — 2026-03-11

### Added

- **OpenAI models** — GPT-5.1, GPT-5.2, GPT-5.2 Pro, and Codex variants
  (gpt-5-codex, gpt-5.1-codex, gpt-5.1-codex-mini, gpt-5.2-codex).
- **Anthropic models** — Claude Opus 4, Opus 4.1, Opus 4.5, Sonnet 4.
- GPT-5.1, GPT-5.2, and GPT-5.2 Pro added to OpenAI reasoning model set
  for correct `developer` message handling.

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
