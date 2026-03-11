# Swift AI SDK

> **Note:** `CLAUDE.md` is a symlink to this file (`AGENTS.md`). Edit `AGENTS.md` — it is the canonical source. Both Claude Code and other agents read the same file.

The role of this file is to describe common mistakes and confusion points that agents might encounter as they work in this project. If you ever encounter something in the project that surprises you, please alert the developer working with you and indicate that this is the case in this file to help prevent future agents from having the same issue.

## Philosophy

This codebase will outlive you. Every shortcut you take becomes
someone else's burden. Every hack compounds into technical debt
that slows the whole team down.

You are not just writing code. You are shaping the future of this
project. The patterns you establish will be copied. The corners
you cut will be cut again.

Fight entropy. Leave the codebase better than you found it.

## Workflow

- All changes to `main` must go through a pull request for review. Do not push directly to `main`.

## Releases

- The project uses [Semantic Versioning](https://semver.org/). While on `0.x`, minor bumps may include breaking changes.
- Update `CHANGELOG.md` with every user-facing change under an `[Unreleased]` section. Follow [Keep a Changelog](https://keepachangelog.com/) format.
- To cut a release: move the `[Unreleased]` entries into a new `[x.y.z]` section with the date, commit, tag, and push the tag. The `release.yml` GitHub Action builds, tests, and creates a GitHub Release with the changelog notes automatically.
- Do not tag a release without running `./Tools/release-preflight.sh` locally and confirming the same release-preflight workflow is green on the exact `main` commit being tagged.

## Model IDs — Verification Required

**Never invent, guess, or assume model IDs.** Every model constant in `OpenAIModels.swift` and `AnthropicModels.swift` must correspond to a real, verified API model ID. The source of truth is:

1. The provider's official documentation (Anthropic docs, OpenAI docs).
2. The [models.dev](https://models.dev) registry (`curl https://models.dev/api.json`) — use the `openai` and `anthropic` top-level provider keys, not third-party router entries.

When adding or updating models:
- Run `Tools/sync-models.sh` to see what models.dev lists for each provider.
- Cross-reference against the provider's official docs before adding any model constant.
- Never ship a model ID you haven't verified exists in at least one authoritative source.

## Reference Repos

- Vercel AI SDK: https://github.com/vercel/ai

Use these as implementation references when designing protocol handling, UX flows, and operational safeguards.

## Settled Decisions — Do Not Reopen

- `AIStream` and `AIHTTPStreamResponse.body` use `AsyncThrowingStream<..., any Error>` internally. This is a Swift stdlib/concurrency constraint, not a bug. All error paths normalize to `AIError` at runtime. Do not flag this as an issue, propose fixing it, or mention it in status reports. It will resolve naturally if Swift ships sendable typed-throw iterators in a future version.

## Notes From Spec Review

- `AIRequest.systemPrompt` is the canonical instruction channel. Do not model system turns as `AIMessage` values.
- `AIStream` is a single-pass, single-consumer stream. Helper streams like accumulated text consume the same underlying stream.
- Provider-specific higher-level behavior should flow through `AIProviderCapabilities`, not through cross-module imports from `AICore` into provider modules.
- `AISwiftUI` observable state types are `@MainActor` reference types and are intentionally not blanket `Sendable`.
- Swift 6 currently rejects racing `AsyncThrowingStream.Iterator.next()` inside a `@Sendable` timeout closure because the iterator is non-`Sendable`. Chunk-timeout enforcement needs a watchdog task/state approach instead of wrapping `next()` directly in `AITimeoutController.withTimeout(...)`.
- Anthropic `output_config.format` structured outputs are GA and no longer require a beta header, but Anthropic currently documents official support only for Claude Opus 4.6/4.5, Claude Sonnet 4.6/4.5, and Claude Haiku 4.5. Legacy official model IDs should warn rather than being treated as silently supported.
- `AITestSupport` is a regular SwiftPM target, not a test target. It is compiled during release builds, so it must not use `@testable import` or rely on test-only visibility from `AICore`.
