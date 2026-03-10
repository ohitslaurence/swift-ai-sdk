# Spec 11: Usage & Token Reporting

> Every API call costs money. Users should never have to dig through source code to find out how many tokens they spent.

## Goal

Ensure that token usage is consistently surfaced, well-documented, and easy to access across all interaction patterns — completions, streaming, embeddings, and tool loops. The underlying types (`AIUsage`, `AIResponse.usage`, `AIStreamEvent.usage`) already exist. This spec codifies how they should be presented to users and fills the documentation gap.

## Dependencies

- Spec 01 (core protocols, `AIUsage`, `AIResponse`, `AIStream`)
- Spec 05 (tool loops — aggregate usage across steps)
- Spec 07 (embeddings — usage on embedding responses)
- Spec 08 (observability — `AIAccounting` wraps `AIUsage`)

## Design Rules

1. Every successful `AIResponse` must include a populated `AIUsage` with at least `inputTokens` and `outputTokens`. Providers must never return zeroed usage when the upstream API provides token counts.
2. Every `AIStream` must emit exactly one `.usage(AIUsage)` event before the terminal `.finish` event, when the upstream API provides usage data.
3. `AIStream.collect()` must propagate usage from the `.usage` event into the returned `AIResponse.usage`.
4. `AIEmbeddingResponse.usage` is optional because not all embedding APIs report token counts, but providers must populate it when available.
5. Tool loops that make multiple model calls should aggregate usage across all steps. The final response's `usage` should reflect total tokens consumed.
6. Usage values are provider-reported, not SDK-estimated. The SDK does not count tokens itself.

## User-Facing API Surface

### Completions

```swift
let response = try await provider.complete(request)

// Always available
print(response.usage.inputTokens)    // prompt tokens
print(response.usage.outputTokens)   // completion tokens
print(response.usage.totalTokens)    // computed: input + output

// Optional detail (provider-dependent)
print(response.usage.inputTokenDetails?.cachedTokens)
print(response.usage.outputTokenDetails?.reasoningTokens)
```

### Streaming — collected

```swift
let response = try await provider.stream(request).collect()

// Same usage API as completions
print(response.usage.inputTokens)
print(response.usage.outputTokens)
```

### Streaming — manual event handling

```swift
for try await event in provider.stream(request) {
    switch event {
    case .delta(.text(let chunk)):
        print(chunk, terminator: "")
    case .usage(let usage):
        print("Tokens: \(usage.inputTokens) in, \(usage.outputTokens) out")
    case .finish(let reason):
        print("Done: \(reason)")
    default:
        break
    }
}
```

### Embeddings

```swift
let response = try await provider.embed(request)

// Optional — not all providers report embedding token usage
if let usage = response.usage {
    print(usage.inputTokens)
}
```

## Documentation Requirements

The following DocC articles must include usage examples when they are fleshed out:

- **GettingStarted.md** — Show `response.usage` in the first completion example. Users should see token reporting before they finish the quickstart.
- **Providers.md** — Note that all providers populate `AIUsage` from upstream API data.
- **Embeddings.md** — Show `response.usage` access pattern, note it's optional.
- **Observability.md** — Reference `AIAccounting.usage` and how telemetry sinks receive usage data.

## Provider Implementation Checklist

Each provider must:

1. Map the upstream API's token count fields to `AIUsage` on every completion response.
2. Map the upstream API's streaming usage chunk (e.g., OpenAI's `usage` field in the final chunk, Anthropic's `message_delta` usage) to an `AIStreamEvent.usage` event.
3. Map embedding token usage to `AIEmbeddingResponse.usage` when the API provides it.
4. Populate `inputTokenDetails` and `outputTokenDetails` when the upstream API provides granular breakdowns (cached tokens, reasoning tokens, etc.).

## Tests

1. OpenAI completion response includes non-zero `inputTokens` and `outputTokens`.
2. OpenAI streaming emits a `.usage` event with non-zero token counts.
3. `AIStream.collect()` returns an `AIResponse` with usage matching the emitted `.usage` event.
4. OpenAI embedding response includes non-nil `usage`.
5. Anthropic completion response includes non-zero `inputTokens` and `outputTokens`.
6. Anthropic streaming emits a `.usage` event with non-zero token counts.
7. `AIUsage.totalTokens` equals `inputTokens + outputTokens`.
8. Provider does not return zeroed usage when upstream API provides counts.

## Acceptance Criteria

- [ ] All providers populate `AIUsage` on completion responses from upstream data.
- [ ] All providers emit `.usage` stream events when the upstream API reports usage.
- [ ] `AIStream.collect()` propagates usage into the returned `AIResponse`.
- [ ] `AIEmbeddingResponse.usage` is populated when available from the upstream API.
- [ ] DocC articles show usage access patterns in their code examples.
- [ ] All 8 test cases pass.
