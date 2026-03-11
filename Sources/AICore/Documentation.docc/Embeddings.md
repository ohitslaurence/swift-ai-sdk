# Embeddings

Generate vector embeddings for text using provider-neutral types.

## Overview

The SDK provides embedding support through the same ``AIProvider`` protocol used
for completions. Provider-level support is declared via
``AIEmbeddingCapabilities`` — currently OpenAI supports embeddings, while
Anthropic does not.

## Single embedding

```swift
let embedding = try await provider.embed(
    "swift concurrency",
    model: .openAIEmbedding(.textEmbedding3Small)
)

print("Dimensions: \(embedding.dimensions)")
print("Vector: \(embedding.vector.prefix(5))...")
```

## Batch embeddings

Use ``AIProvider/embedMany(_:model:batchSize:)`` to embed multiple texts with
automatic batching:

```swift
let texts = ["swift concurrency", "async await", "structured concurrency"]

let embeddings = try await provider.embedMany(
    texts,
    model: .openAIEmbedding(.textEmbedding3Small),
    batchSize: 100
)

for embedding in embeddings {
    print("[\(embedding.index)] \(embedding.dimensions) dimensions")
}
```

The SDK splits large input arrays into batches, sends them in sequence, and
reassembles results with correct indices. Cancellation is checked between
batches.

## Checking provider support

Not all providers support embeddings. Check capabilities before calling:

```swift
if provider.capabilities.embeddings.supportsEmbeddings {
    let embedding = try await provider.embed("hello", model: embeddingModel)
} else {
    // Falls through to AIError.unsupportedFeature
}
```

## Dimension override

Some models support reducing the output vector dimensions:

```swift
let request = AIEmbeddingRequest(
    model: .openAIEmbedding(.textEmbedding3Small),
    inputs: [.text("hello")],
    dimensions: 256
)

let response = try await provider.embed(request)
```

Check ``AIEmbeddingCapabilities/supportsDimensionOverride`` to verify provider
support.
