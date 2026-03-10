# ``AICore``

Provider-agnostic core primitives for the Swift AI SDK.

`AICore` defines the shared provider protocol, request and response models, streaming primitives, middleware, retry, timeout, and transport abstractions used by higher-level provider modules.

## Stream typing note

The current implementation keeps `AIStream` and `AIHTTPStreamResponse.body` backed by `AsyncThrowingStream<..., any Error>` internally.

This is a deliberate compatibility exception for Swift 6-era concurrency limitations when composing stream wrappers and transport adapters. Public behavior still normalizes surfaced failures to `AIError` values through provider mapping and `AIStream` helper APIs.
