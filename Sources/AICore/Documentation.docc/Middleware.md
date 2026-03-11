# Middleware

Compose request/response transformations around any provider.

## Overview

``AIMiddleware`` lets you intercept and transform requests, responses, streams,
and embedding calls without modifying provider implementations. Middleware is
applied in array order using ``withMiddleware(_:middleware:)``.

## Applying middleware

```swift
let provider = withMiddleware(openai, middleware: [
    DefaultSettingsMiddleware(maxTokens: 1000, temperature: 0.7),
    LoggingMiddleware { print($0) }
])

// All calls through this provider now have defaults applied and are logged
let response = try await provider.complete(
    AIRequest(model: .gpt(.gpt5Mini), messages: [.user("Hello")])
)
```

Middleware wraps in array order: the first middleware is outermost, the last is
closest to the actual provider call.

## Built-in middleware

### DefaultSettingsMiddleware

Fills in missing request fields with configured defaults. Existing values are
never overwritten:

```swift
let defaults = DefaultSettingsMiddleware(
    maxTokens: 2000,
    temperature: 0.5,
    topP: 0.9
)
```

### LoggingMiddleware

Logs request/response lifecycle events through a configurable logger closure:

```swift
let logging = LoggingMiddleware { message in
    print(message)
}
```

## Writing custom middleware

Conform to ``AIMiddleware`` and override the methods you need. All methods have
default pass-through implementations:

```swift
struct AuthRefreshMiddleware: AIMiddleware {
    let tokenProvider: @Sendable () async throws -> String

    func transformRequest(_ request: AIRequest) async throws -> AIRequest {
        var request = request
        let token = try await tokenProvider()
        request.headers["Authorization"] = "Bearer \(token)"
        return request
    }
}
```

For response-level interception, use ``AIMiddleware/wrapGenerate(request:next:)``:

```swift
struct MetricsMiddleware: AIMiddleware {
    func wrapGenerate(
        request: AIRequest,
        next: @Sendable (AIRequest) async throws -> AIResponse
    ) async throws -> AIResponse {
        let start = ContinuousClock.now
        let response = try await next(request)
        let elapsed = ContinuousClock.now - start
        print("Completed in \(elapsed)")
        return response
    }
}
```
