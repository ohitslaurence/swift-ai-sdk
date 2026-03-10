# Spec 00: Project Setup, Structure & Standards

> The foundation that makes everything else possible. Get this right and contributors will know exactly where things go, how to test, and what quality bar to hit.

## Goal

Set up a professional, open-source Swift package that a contributor can clone, build, and test in under 2 minutes. Establish the conventions that all subsequent specs follow.

## Package Identity

- **Name**: `swift-ai` (package), `AI` (primary module/import)
- **Repo**: `swift-ai-sdk` (GitHub)
- **License**: Apache 2.0 (same as Swift itself, Vapor, swift-argument-parser)
- **Minimum Swift**: 6.0
- **Platforms**: macOS 14+, iOS 17+, tvOS 17+, watchOS 10+, visionOS 1+, Linux

## Package.swift

```swift
// swift-tools-version: 6.0

import PackageDescription

var swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "swift-ai",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    products: [
        // Umbrella — re-exports AICore + shipped providers.
        // `AISwiftUI` is only re-exported from `Sources/AI/AI.swift` on Apple platforms.
        .library(name: "AI", targets: ["AI"]),

        // Individual modules for selective import
        .library(name: "AICore", targets: ["AICore"]),
        .library(name: "AIProviderAnthropic", targets: ["AIProviderAnthropic"]),
        .library(name: "AIProviderOpenAI", targets: ["AIProviderOpenAI"]),
        .library(name: "AISwiftUI", targets: ["AISwiftUI"]),
    ],
    targets: [
        // ── Core ──────────────────────────────────────
        .target(
            name: "AI",
            dependencies: [
                "AICore",
                "AIProviderAnthropic",
                "AIProviderOpenAI",
                "AISwiftUI",
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "AICore",
            swiftSettings: swiftSettings
        ),

        // ── Providers ─────────────────────────────────
        .target(
            name: "AIProviderAnthropic",
            dependencies: ["AICore"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "AIProviderOpenAI",
            dependencies: ["AICore"],
            swiftSettings: swiftSettings
        ),

        // ── SwiftUI ───────────────────────────────────
        .target(
            name: "AISwiftUI",
            dependencies: ["AICore"],
            swiftSettings: swiftSettings
        ),

        // ── Test Support ──────────────────────────────
        .target(
            name: "AITestSupport",
            dependencies: ["AICore"],
            path: "Tests/AITestSupport",
            swiftSettings: swiftSettings
        ),

        // ── Tests ─────────────────────────────────────
        .testTarget(
            name: "AICoreTests",
            dependencies: ["AICore", "AITestSupport"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AIProviderAnthropicTests",
            dependencies: ["AIProviderAnthropic", "AITestSupport"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AIProviderOpenAITests",
            dependencies: ["AIProviderOpenAI", "AITestSupport"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AISwiftUITests",
            dependencies: ["AISwiftUI", "AITestSupport"],
            swiftSettings: swiftSettings
        ),
    ]
)
```

### Why This Structure

- **Umbrella module (`AI`)**: `import AI` gets you AICore plus the shipped providers. On Apple platforms it also re-exports `AISwiftUI`; on Linux the umbrella remains buildable because SwiftUI exports are conditionally compiled.
- **Individual modules**: Power users import only `AICore` + one provider. Keeps binary size down and avoids pulling in SwiftUI when it is not needed.
- **`AITestSupport` is a regular target, not a test target**: Shared test utilities (mock provider, mock transport, fixtures, assertion helpers) are importable by all test targets.
- **Transport-first testing**: Provider tests use a mock transport by default. `URLProtocol` is optional for adapter-level smoke tests only.
- **Zero external dependencies**: Foundation + URLSession only. No Alamofire, no third-party JSON libraries.

### Platform Notes

- `AISwiftUI` source files and tests are wrapped in `#if canImport(SwiftUI)`.
- `Sources/AI/AI.swift` conditionally re-exports `AISwiftUI` only when SwiftUI is available.
- `swift build` and `swift test` must succeed on Linux without requiring SwiftUI.

## Directory Structure

```
swift-ai-sdk/
├── Package.swift
├── LICENSE
├── README.md
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── CHANGELOG.md
├── AGENTS.md                          # LLM/agent instructions
├── Makefile
├── .gitignore
├── .editorconfig
├── .swift-format
├── .spi.yml
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   └── feature_request.md
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── workflows/
│       ├── ci.yml                     # Build + test on PR
│       ├── format.yml                 # swift-format check on PR
│       └── docs.yml                   # DocC build validation
├── Sources/
│   ├── AI/
│   │   └── AI.swift                   # Conditionally re-exports AICore, providers, and AISwiftUI
│   ├── AICore/
│   │   ├── Provider/
│   │   │   ├── AIProvider.swift
│   │   │   └── AIProviderCapabilities.swift
│   │   ├── Request/
│   │   │   ├── AIRequest.swift
│   │   │   └── AIResponseFormat.swift
│   │   ├── Response/
│   │   │   ├── AIResponse.swift
│   │   │   ├── AIUsage.swift
│   │   │   └── AIProviderWarning.swift
│   │   ├── Messages/
│   │   │   ├── AIMessage.swift
│   │   │   ├── AIRole.swift
│   │   │   ├── AIContent.swift
│   │   │   ├── AIImage.swift
│   │   │   └── AIDocument.swift
│   │   ├── Models/
│   │   │   └── AIModel.swift
│   │   ├── Embeddings/
│   │   │   ├── AIEmbedding.swift
│   │   │   ├── AIEmbeddingRequest.swift
│   │   │   └── AIEmbeddingResponse.swift
│   │   ├── Streaming/
│   │   │   ├── AIStream.swift
│   │   │   ├── AIStreamEvent.swift
│   │   │   ├── AIStreamDelta.swift
│   │   │   └── SmoothStreaming.swift
│   │   ├── Tools/
│   │   │   ├── AITool.swift
│   │   │   ├── AIToolChoice.swift
│   │   │   ├── AIToolUse.swift
│   │   │   ├── AIToolResult.swift
│   │   │   ├── AIToolExecution.swift
│   │   │   ├── AIToolResponse.swift
│   │   │   ├── AIToolStream.swift
│   │   │   └── StopCondition.swift
│   │   ├── StructuredOutput/
│   │   │   ├── AIStructured.swift
│   │   │   ├── AIJSONSchema.swift
│   │   │   ├── AIStructuredResponse.swift
│   │   │   ├── AIJSONSchemaGenerator.swift
│   │   │   ├── StructuredOutputGenerator.swift
│   │   │   └── StructuredOutputRepair.swift
│   │   ├── Agent/
│   │   │   └── Agent.swift
│   │   ├── Retry/
│   │   │   ├── RetryPolicy.swift
│   │   │   └── RetryExecutor.swift
│   │   ├── Timeout/
│   │   │   └── AITimeout.swift
│   │   ├── Transport/
│   │   │   ├── AIHTTPTransport.swift
│   │   │   ├── URLSessionTransport.swift
│   │   │   └── AIProviderHTTPConfiguration.swift
│   │   ├── Middleware/
│   │   │   ├── AIMiddleware.swift
│   │   │   ├── MiddlewareProvider.swift
│   │   │   ├── LoggingMiddleware.swift
│   │   │   └── DefaultSettingsMiddleware.swift
│   │   ├── Observability/
│   │   │   ├── AIAccounting.swift
│   │   │   ├── AITelemetry.swift
│   │   │   ├── AITelemetryEvent.swift
│   │   │   ├── AITelemetryMetrics.swift
│   │   │   └── AITelemetryRedaction.swift
│   │   ├── Errors/
│   │   │   └── AIError.swift
│   │   └── Documentation.docc/
│   │       ├── AICore.md              # Landing page
│   │       ├── GettingStarted.md      # Tutorial
│   │       ├── CapabilityMatrix.md    # Provider support overview
│   │       ├── Embeddings.md          # Text embeddings and vector generation
│   │       ├── Observability.md       # Telemetry, logging, metrics, accounting
│   │       ├── Providers.md           # How to use/add providers
│   │       ├── StructuredOutput.md    # Codable → JSON schema
│   │       ├── ToolUse.md             # Tools and agentic loops
│   │       ├── Middleware.md          # Writing custom middleware
│   │       └── Resources/
│   ├── AIProviderAnthropic/
│   │   ├── AnthropicProvider.swift
│   │   ├── AnthropicModels.swift
│   │   ├── Internal/
│   │   │   ├── AnthropicRequestBuilder.swift
│   │   │   ├── AnthropicResponseParser.swift
│   │   │   ├── AnthropicStreamParser.swift
│   │   │   └── AnthropicErrorMapper.swift
│   │   └── Documentation.docc/
│   │       └── AnthropicProvider.md
│   ├── AIProviderOpenAI/
│   │   ├── OpenAIProvider.swift
│   │   ├── OpenAIModels.swift
│   │   ├── Internal/
│   │   │   ├── OpenAIRequestBuilder.swift
│   │   │   ├── OpenAIEmbeddingRequestBuilder.swift
│   │   │   ├── OpenAIEmbeddingResponseParser.swift
│   │   │   ├── OpenAIResponseParser.swift
│   │   │   ├── OpenAIStreamParser.swift
│   │   │   └── OpenAIErrorMapper.swift
│   │   └── Documentation.docc/
│   │       └── OpenAIProvider.md
│   └── AISwiftUI/
│       ├── AIStreamState.swift        # Wrapped in #if canImport(SwiftUI)
│       ├── AIConversation.swift       # Wrapped in #if canImport(SwiftUI)
│       ├── StreamingText.swift        # Wrapped in #if canImport(SwiftUI)
│       ├── AIMessageList.swift        # Wrapped in #if canImport(SwiftUI)
│       ├── MessageBubble.swift        # Wrapped in #if canImport(SwiftUI)
│       └── Documentation.docc/
│           └── AISwiftUI.md
├── Tests/
│   ├── AITestSupport/                 # Shared test utilities (regular target, not test target)
│   │   ├── MockProvider.swift
│   │   ├── MockTransport.swift        # Deterministic transport mocking
│   │   ├── MockURLProtocol.swift      # Optional URLSession adapter smoke tests only
│   │   ├── Fixtures/
│   │   │   ├── AnthropicFixtures.swift
│   │   │   └── OpenAIFixtures.swift
│   │   └── Assertions/
│   │       └── AIAssertions.swift     # Custom XCTest assertions
│   ├── AICoreTests/
│   │   ├── ProviderTests.swift
│   │   ├── MessageTests.swift
│   │   ├── EmbeddingTests.swift
│   │   ├── Integration/
│   │   │   └── TelemetryIntegrationTests.swift
│   │   ├── StreamTests.swift
│   │   ├── ToolTests.swift
│   │   ├── StructuredOutputTests.swift
│   │   ├── RetryTests.swift
│   │   ├── ObservabilityTests.swift
│   │   └── JSONSchemaTests.swift
│   ├── AIProviderAnthropicTests/
│   │   ├── AnthropicCompletionTests.swift
│   │   ├── Integration/
│   │   │   └── AnthropicTelemetryIntegrationTests.swift
│   │   ├── AnthropicStreamTests.swift
│   │   ├── AnthropicRequestTests.swift
│   │   └── AnthropicErrorTests.swift
│   ├── AIProviderOpenAITests/
│   │   ├── Integration/
│   │   │   ├── OpenAIEmbeddingIntegrationTests.swift
│   │   │   └── OpenAITelemetryIntegrationTests.swift
│   │   ├── OpenAIEmbeddingTests.swift
│   │   └── (otherwise mirrors Anthropic test structure)
│   └── AISwiftUITests/
│       ├── AIStreamStateTests.swift   # Wrapped in #if canImport(SwiftUI)
│       └── AIConversationTests.swift  # Wrapped in #if canImport(SwiftUI)
└── Examples/                          # Standalone example packages
    ├── BasicCompletion/
    │   ├── Package.swift
    │   └── Sources/main.swift
    ├── StreamingChat/
    │   ├── Package.swift
    │   └── Sources/main.swift
    ├── StructuredOutput/
    │   ├── Package.swift
    │   └── Sources/main.swift
    ├── Embeddings/
    │   ├── Package.swift
    │   └── Sources/main.swift
    └── ToolUse/
        ├── Package.swift
        └── Sources/main.swift
```

### Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Modules | PascalCase, `AI` prefix | `AICore`, `AIProviderAnthropic` |
| Source files | PascalCase, match type name | `AIProvider.swift` |
| Test files | PascalCase, suffix `Tests` | `AnthropicStreamTests.swift` |
| Internal directories | PascalCase by domain | `Messages/`, `Streaming/`, `Internal/` |
| Provider internals | `Internal/` subdirectory | Not exported, can change freely |

### Internal vs Public

Files in `Internal/` directories use `internal` access by default. Only files at the module root level are `public`. This keeps the public API surface intentional and reviewable.

## Code Quality

### swift-format

Use `swift-format` (Apple's official formatter), not SwiftLint. Config based on swift-argument-parser's standard:

```json
{
  "version": 1,
  "indentation": { "spaces": 4 },
  "lineLength": 120,
  "indentConditionalCompilationBlocks": true,
  "indentSwitchCaseLabels": false,
  "lineBreakBeforeControlFlowKeywords": false,
  "lineBreakBeforeEachArgument": false,
  "lineBreakBeforeEachGenericRequirement": false,
  "maximumBlankLines": 1,
  "respectsExistingLineBreaks": true,
  "prioritizeKeepingFunctionOutputTogether": false,
  "rules": {
    "AllPublicDeclarationsHaveDocumentation": false,
    "AlwaysUseLiteralForEmptyCollectionInit": false,
    "AlwaysUseLowerCamelCase": true,
    "FileScopedDeclarationPrivacy": true,
    "FullyIndirectEnum": true,
    "NeverForceUnwrap": true,
    "NeverUseForceTry": true,
    "NeverUseImplicitlyUnwrappedOptionals": true,
    "OrderedImports": true,
    "UseLetInEveryBoundCaseVariable": false,
    "ValidateDocumentationComments": true
  },
  "spacesAroundRangeFormationOperators": false
}
```

### .editorconfig

```ini
root = true

[*]
indent_style = space
indent_size = 4
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true

[*.md]
trim_trailing_whitespace = false

[*.yml]
indent_size = 2

[Makefile]
indent_style = tab
```

### .gitignore

```gitignore
.DS_Store
/.build
/Packages
xcuserdata/
DerivedData/
.swiftpm/
Package.resolved
*.xcodeproj
```

### .spi.yml

```yaml
version: 1
builder:
  configs:
    - documentation_targets: [AICore, AIProviderAnthropic, AIProviderOpenAI, AISwiftUI]
```

## Testing Strategy

### Test Categories

1. **Unit tests** (`*Tests/`): Fast, isolated, mock all external dependencies. Every PR must pass these.
2. **Integration tests** (opt-in): Real API calls, gated behind environment variables. Not run in CI by default.

### Opt-In Integration Test Conventions

Live tests are allowed for shipped providers, but they must stay deterministic enough to be useful and cheap enough to run manually.

Rules:

- Gate every live test behind `AI_INTEGRATION_TESTS=1`.
- Require non-empty provider credentials only for the provider under test, for example `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`.
- When required env vars are missing or empty, skip with `XCTSkip` rather than failing.
- Use the smallest practical models for live tests.
- Assert shape, event ordering, warning behavior, and presence/absence of usage or telemetry fields.
- Do not assert exact generated text, exact embedding float values, exact token counts, or latency.
- Embeddings live tests belong under provider test targets; telemetry live tests may live under `AICoreTests/Integration/` plus provider-specific integration folders when provider behavior matters.

Recommended commands:

- `AI_INTEGRATION_TESTS=1 OPENAI_API_KEY=... swift test --filter OpenAIEmbeddingIntegrationTests`
- `AI_INTEGRATION_TESTS=1 OPENAI_API_KEY=... swift test --filter OpenAITelemetryIntegrationTests`
- `AI_INTEGRATION_TESTS=1 ANTHROPIC_API_KEY=... swift test --filter AnthropicTelemetryIntegrationTests`
- `OPENAI_API_KEY=... ANTHROPIC_API_KEY=... make test-integration`

### Test Support Module (`AITestSupport`)

Shared utilities available to all test targets:

```swift
// MockProvider — configurable fake with actor-backed call recording
public actor MockProviderRecorder {
    public private(set) var completeCalls: [AIRequest] = []
    public private(set) var streamCalls: [AIRequest] = []
    public private(set) var embedCalls: [AIEmbeddingRequest] = []

    public func recordComplete(_ request: AIRequest)
    public func recordStream(_ request: AIRequest)
    public func recordEmbed(_ request: AIEmbeddingRequest)
}

public struct MockProvider: AIProvider, Sendable {
    public var completionHandler: @Sendable (AIRequest) async throws -> AIResponse
    public var streamHandler: @Sendable (AIRequest) -> AIStream
    public var embeddingHandler: @Sendable (AIEmbeddingRequest) async throws -> AIEmbeddingResponse
    public var availableModels: [AIModel]
    public var capabilities: AIProviderCapabilities
    public let recorder: MockProviderRecorder
}

// MockTransport — preferred provider test hook
public struct MockTransport: AIHTTPTransport, Sendable {
    public var dataHandler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    public var streamHandler: @Sendable (URLRequest) async throws -> AIHTTPStreamResponse
}

// MockURLProtocol — optional adapter smoke tests only
public final class MockURLProtocol: URLProtocol {
    public static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
}

// Fixture helpers
public enum AnthropicFixtures {
    public static var completionResponse: Data { ... }
    public static var streamChunks: [Data] { ... }
    public static var toolUseResponse: Data { ... }
    public static var errorResponse: (Int, Data) { ... }
}

// Custom assertions
public func assertAIResponse(
    _ response: AIResponse,
    containsText text: String,
    file: StaticString = #filePath,
    line: UInt = #line
)
```

### What Gets Tested

| Area | What to test | What NOT to test |
|------|-------------|-----------------|
| Core types | Construction, equality, Codable round-trips, Sendable | SwiftUI rendering |
| Provider request building | JSON output matches API spec exactly | Actual HTTP calls |
| Provider response parsing | Decodes real API response fixtures | API availability |
| Embeddings | Request shaping, batch splitting, usage aggregation | Vector quality |
| Streaming | Event ordering, accumulation, cancellation | Network timing |
| Structured output | Schema generation, retry logic, validation | LLM output quality |
| Tool execution | Loop mechanics, parallel execution, error handling | Tool business logic |
| Retry | Backoff timing, retry conditions, max retries | Real HTTP failures |
| Observability | Event ordering, redaction, metrics, accounting exposure | Log backend behavior |

### Test Naming Convention

```swift
func test_complete_withSystemPrompt_includesSystemInRequest() async throws { }
func test_stream_whenCancelled_stopsEmittingEvents() async throws { }
func test_retry_on429_retriesWithBackoff() async throws { }
```

Pattern: `test_<method>_<condition>_<expectation>`

## CI/CD

### GitHub Actions: `ci.yml`

```yaml
name: CI

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-and-test:
    strategy:
      matrix:
        os: [macos-15, ubuntu-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: swift-actions/setup-swift@v2
        with:
          swift-version: "6.0"
      - name: Build
        run: swift build
      - name: Test
        run: swift test

  format-check:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Check formatting
        run: |
          swift format lint --strict --recursive Sources/ Tests/
```

### Makefile

```makefile
.PHONY: build test test-integration format format-check lint docs clean

build:
	swift build

test:
	swift test

test-integration:
	AI_INTEGRATION_TESTS=1 OPENAI_API_KEY="$$OPENAI_API_KEY" ANTHROPIC_API_KEY="$$ANTHROPIC_API_KEY" swift test --filter "IntegrationTests"

test-core:
	swift test --filter AICoreTests

test-providers:
	swift test --filter "AIProvider.*Tests"

lint: format-check

format:
	swift format --recursive --in-place Sources/ Tests/

format-check:
	swift format lint --strict --recursive Sources/ Tests/

docs:
	swift package generate-documentation --target AICore

clean:
	swift package clean
	rm -rf .build
```

## Documentation

### DocC

Each module gets a `Documentation.docc/` directory with at minimum a landing page. `AICore` gets a full getting-started tutorial.

DocC articles for AICore:

| Article | Content |
|---------|---------|
| `AICore.md` | Overview, what this package does, module map |
| `GettingStarted.md` | Install via SPM, first completion, first stream |
| `CapabilityMatrix.md` | Cross-provider feature support matrix and caveats |
| `Embeddings.md` | Embedding requests, batching, vector handling |
| `Observability.md` | Telemetry sinks, logging hooks, metrics, accounting |
| `Providers.md` | How to use each provider, how to add your own |
| `StructuredOutput.md` | Codable → JSON schema, examples |
| `ToolUse.md` | Defining tools, agentic loops |
| `Middleware.md` | Writing custom middleware |

### Inline Documentation

Every public type and method gets a `///` doc comment. Follow this standard:

```swift
/// A request to send to an AI provider.
///
/// Construct a request with a model, messages, and optional configuration:
///
/// ```swift
/// let request = AIRequest(
///     model: .claude(.haiku4_5),
///     messages: [.user("Hello")],
///     maxTokens: 1024
/// )
/// ```
public struct AIRequest: Sendable {
    /// The model to use for this request.
    public var model: AIModel

    /// The conversation messages to send.
    public var messages: [AIMessage]

    /// Maximum tokens to generate. Provider-specific defaults apply if `nil`.
    public var maxTokens: Int?
}
```

Rules:
- Every `public` symbol gets a doc comment
- Include at least one code example for complex types
- `internal` symbols get doc comments only when the intent isn't obvious
- No doc comments on `private` symbols

## Examples

The `Examples/` directory contains standalone Swift example packages demonstrating common use cases. Each can be run with `swift run` from its example directory:

```
Examples/
├── BasicCompletion/
│   ├── Package.swift          # Depends on swift-ai (local path)
│   └── Sources/main.swift
├── StreamingChat/
│   ├── Package.swift
│   └── Sources/main.swift
├── StructuredOutput/
│   ├── Package.swift
│   └── Sources/main.swift
├── Embeddings/
│   ├── Package.swift
│   └── Sources/main.swift
└── ToolUse/
    ├── Package.swift
    └── Sources/main.swift
```

Examples serve as both documentation and integration smoke tests.

## Community Files

### CONTRIBUTING.md

Key sections:
1. **Getting started** — clone, `swift build`, `swift test`
2. **Development workflow** — branch from main, write tests, run `make format`
3. **Adding a new provider** — step-by-step guide (create module, implement protocol, add tests, add to umbrella)
4. **Code style** — link to `.swift-format`, explain conventions
5. **Pull request process** — what reviewers look for, CI must pass
6. **Reporting issues** — bug template, feature request template

### CODE_OF_CONDUCT.md

Use the Contributor Covenant v2.1 (industry standard).

### CHANGELOG.md

Follow [Keep a Changelog](https://keepachangelog.com/) format:

```markdown
# Changelog

## [Unreleased]

### Added
- Initial release with AICore, Anthropic, and OpenAI providers
```

### AGENTS.md

Instructions for AI agents working on this codebase:

```markdown
# AI Agent Instructions

## Project Overview
Swift AI SDK — a provider-agnostic AI integration library for Swift.

## Key Rules
- Public `AICore` and provider types that cross concurrency boundaries must be `Sendable`
- `AISwiftUI` state types use `@MainActor` rather than blanket `Sendable`
- Zero external dependencies in AICore
- Every provider uses Foundation URLSession only
- Provider tests use `MockTransport`; `MockURLProtocol` is only for URLSession adapter smoke tests
- Run `make format` before committing
- Run `make test` before declaring work complete

## Module Dependency Graph
AI (umbrella) → AICore, Anthropic, OpenAI, AISwiftUI
AIProviderAnthropic → AICore
AIProviderOpenAI → AICore
AISwiftUI → AICore
AITestSupport → AICore
*Tests → respective module + AITestSupport
```

## Acceptance Criteria

- [ ] `swift build` succeeds with zero warnings on macOS and Linux
- [ ] `swift test` runs (even if tests are placeholder) with zero failures
- [ ] `make build`, `make test`, `make test-integration`, `make format`, `make format-check` all work
- [ ] Package.swift declares all modules with correct dependency graph
- [ ] `.swift-format` config present and enforced
- [ ] `.editorconfig` present
- [ ] `.gitignore` covers Swift/SPM artifacts
- [ ] `.spi.yml` configured for doc generation
- [ ] `LICENSE` (Apache 2.0) present
- [ ] `README.md` with badges, install instructions, quick example
- [ ] `CONTRIBUTING.md` with development workflow
- [ ] `CODE_OF_CONDUCT.md` present
- [ ] `CHANGELOG.md` initialized
- [ ] `AGENTS.md` with agent instructions
- [ ] `AITestSupport` module with `MockProvider`, `MockTransport`, and optional `MockURLProtocol`
- [ ] Opt-in integration tests are documented, env-gated, and skip cleanly when credentials are absent
- [ ] GitHub Actions CI runs build + test on macOS and Linux
- [ ] `AISwiftUI` source and tests are conditionally compiled so Linux builds remain green
- [ ] All source files compile in Swift 6 language mode with strict concurrency
- [ ] DocC builds without errors for AICore
- [ ] At least one working example in `Examples/`
