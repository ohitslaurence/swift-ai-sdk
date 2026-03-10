# Contributing

Thanks for helping improve Swift AI SDK.

## Getting Started

1. Clone the repository.
2. Run `swift build`.
3. Run `swift test`.

## Development Workflow

1. Create a branch from `main`.
2. Make small, reviewable changes.
3. Run `make format`.
4. Run `make test`.

## Adding a Provider

1. Add a new provider target under `Sources/`.
2. Conform the provider to `AIProvider`.
3. Add tests in a matching `Tests/` target.
4. Re-export the provider from `Sources/AI/AI.swift` when it ships with the umbrella module.

## Code Style

- Use the repository `.swift-format` configuration.
- Prefer explicit, well-documented public APIs.
- Keep `AICore` free of third-party dependencies.

## Pull Requests

- Keep PRs scoped.
- Make sure CI passes.
- Include context for notable design decisions.

## Reporting Issues

- Use the bug report template for defects.
- Use the feature request template for enhancements.
