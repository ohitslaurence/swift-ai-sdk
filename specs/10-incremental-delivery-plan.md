# Spec 10: Incremental Delivery Plan

> Land the new surface area in small slices that are easy to review, test, and revert if needed.

## Goal

Define the recommended implementation order for the additive work introduced by Specs 07, 08, and 09. This is a delivery checklist, not a new architecture spec.

## Dependencies

- Spec 01 (core protocols, capabilities, retry, middleware)
- Spec 03 (OpenAI provider support)
- Spec 07 (embeddings)
- Spec 08 (observability)
- Spec 09 (capability matrix)

## Delivery Rules

1. Each phase should leave the package building and tests green.
2. Land `AICore` contracts before provider implementations that depend on them.
3. Prefer one user-visible behavior family per PR: embeddings, telemetry core, or docs/testing.
4. Keep provider-specific behavior inside provider modules and capability declarations.
5. Do not block docs and examples on finishing every optional integration test.

## Recommended Phase Order

### Phase 1: Core Embeddings Foundation

- [ ] Add `AIEmbeddingRequest`, `AIEmbeddingResponse`, `AIEmbedding`, and `AIEmbeddingCapabilities` in `AICore`.
- [ ] Extend `AIProvider` and middleware surfaces for embeddings.
- [ ] Add `MockProviderRecorder.embedCalls` and embedding-focused core tests.
- [ ] Verify strict-concurrency correctness for all new public types.

Exit gate:

- `AICore` builds with embeddings APIs exposed.
- Providers that do nothing still compile through the default unsupported path.

### Phase 2: Embeddings Helpers and OpenAI Provider Support

- [ ] Implement `embed(_:)` and `embedMany(...)` helpers in `AICore`.
- [ ] Implement batching, aggregation, cancellation, and retry behavior.
- [ ] Add OpenAI embedding model IDs, request builder, response parser, and provider tests.
- [ ] Verify Anthropic remains explicitly unsupported for embeddings.

Exit gate:

- One shipped provider supports embeddings end to end.
- Unsupported providers fail deterministically before speculative transport work.

### Phase 3: Telemetry Core

- [ ] Add telemetry event, snapshot, metrics, redaction, and accounting types.
- [ ] Implement `withTelemetry(...)` wrapping for completion, stream, and embedding entry points.
- [ ] Add a recording sink for unit tests.
- [ ] Verify sink failures cannot fail the underlying AI operation.

Exit gate:

- Completion, streaming, and embedding operations can be observed through a stable redacted event stream.

### Phase 4: Higher-Level Instrumentation

- [ ] Instrument structured-output retries with child request events.
- [ ] Instrument tool-loop approval, execution, step-complete, and failure events.
- [ ] Verify cancellation and stream interruption surface the same terminal errors to telemetry and callers.
- [ ] Align `LoggingMiddleware` behavior with the new telemetry surface where appropriate.

Exit gate:

- Telemetry coverage spans the full high-level SDK flow, not just raw provider calls.

### Phase 5: Documentation and Example Pass

- [ ] Write `Embeddings.md`, `Observability.md`, and `CapabilityMatrix.md` DocC articles using the outlines in Specs 07-09.
- [ ] Ensure each article has at least one copy-pastable example.
- [ ] Update README / getting-started cross-links where these new surfaces materially affect discoverability.
- [ ] Keep the capability matrix aligned with shipped provider behavior.

Exit gate:

- A contributor can discover embeddings and telemetry through DocC without reading the spec set first.

### Phase 6: Opt-In Integration Tests

- [ ] Add env-gated live embeddings tests for OpenAI.
- [ ] Add env-gated telemetry integration tests for at least one completion path, one streaming path, and one embedding path.
- [ ] Make all live tests skip cleanly when required env vars are absent.
- [ ] Keep live tests out of default CI runs.

Exit gate:

- Real-provider smoke coverage exists for the new surfaces without making the default test suite flaky or expensive.

## Suggested PR Boundaries

1. Core embeddings contracts + tests.
2. OpenAI embeddings implementation + helper batching.
3. Telemetry core wrappers + unit tests.
4. Tool/structured-output telemetry instrumentation.
5. DocC/articles/examples.
6. Opt-in integration tests.

## Acceptance Criteria

- [ ] The rollout order is explicit and additive.
- [ ] Each phase can land independently while keeping the repo buildable.
- [ ] Embeddings work lands before embeddings-dependent docs and live tests.
- [ ] Telemetry core lands before tool-loop and structured-output instrumentation.
- [ ] The plan preserves the current architecture and does not introduce new cross-module dependencies.
