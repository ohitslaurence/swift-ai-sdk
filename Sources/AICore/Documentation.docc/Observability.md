# Observability

Instrument AI operations with telemetry events, metrics, and usage accounting.

## Overview

The observability layer wraps any ``AIProvider`` to emit structured telemetry
events for completions, streams, embeddings, tool loops, and structured output
retries. Events flow to configurable sinks with built-in privacy redaction.

## Adding telemetry

Wrap a provider with ``withTelemetry(_:configuration:)``:

```swift
let provider = withTelemetry(openai, configuration: AITelemetryConfiguration(
    sinks: [MyTelemetrySink()],
    redaction: .default,
    includeMetrics: true,
    includeUsage: true
))
```

All calls through the wrapped provider now emit ``AITelemetryEvent`` values to
the configured sinks.

## Writing a sink

Conform to ``AITelemetrySink`` and implement the single `record` method:

```swift
struct ConsoleSink: AITelemetrySink {
    func record(_ event: AITelemetryEvent) async {
        print("[\(event.operationKind)] \(event.kind)")
    }
}
```

Sink failures are isolated — a failing sink never causes the underlying AI
operation to fail.

## Event lifecycle

A typical completion emits:

1. ``AITelemetryEventKind/requestStarted(_:attempt:)`` — before the provider call
2. ``AITelemetryEventKind/responseReceived(_:)`` — on success
3. Or ``AITelemetryEventKind/requestFailed(error:attempt:metrics:)`` — on failure

Streaming adds ``AITelemetryEventKind/streamEvent(_:)`` for each chunk and
``AITelemetryEventKind/streamCompleted(finishReason:metrics:accounting:)`` at
the end.

Retries emit ``AITelemetryEventKind/retryScheduled(attempt:delay:error:)``
between attempts.

## Metrics and accounting

When `includeMetrics` is enabled, terminal events include
``AITelemetryMetrics`` with total duration, first-event latency, retry count,
stream event count, and tool call count.

When `includeUsage` is enabled, terminal events include ``AIAccounting`` with
token usage and optional provider-reported cost.

## Redaction

``AITelemetryRedaction`` controls what data appears in event snapshots:

```swift
let redaction = AITelemetryRedaction(
    prompts: .summary,           // Keep structure, redact content
    responses: .full,            // Preserve full response text
    toolArguments: .none,        // Remove entirely
    embeddingVectors: .none,     // Never expose vectors
    allowedHeaderNames: ["x-request-id"]
)
```

Each field supports three modes: `.none` (remove), `.summary` (structure only),
and `.full` (preserve as-is). The default redaction uses `.summary` for most
fields and `.none` for embedding vectors.
