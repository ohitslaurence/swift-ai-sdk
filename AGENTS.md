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

## Reference Repos

- Vercel AI SDK: https://github.com/vercel/ai

Use these as implementation references when designing protocol handling, UX flows, and operational safeguards.

## Notes From Spec Review

- `AIRequest.systemPrompt` is the canonical instruction channel. Do not model system turns as `AIMessage` values.
- `AIStream` is a single-pass, single-consumer stream. Helper streams like accumulated text consume the same underlying stream.
- Provider-specific higher-level behavior should flow through `AIProviderCapabilities`, not through cross-module imports from `AICore` into provider modules.
- `AISwiftUI` observable state types are `@MainActor` reference types and are intentionally not blanket `Sendable`.
- Swift 6 currently rejects racing `AsyncThrowingStream.Iterator.next()` inside a `@Sendable` timeout closure because the iterator is non-`Sendable`. Chunk-timeout enforcement needs a watchdog task/state approach instead of wrapping `next()` directly in `AITimeoutController.withTimeout(...)`.
- Anthropic `output_config.format` structured outputs are GA and no longer require a beta header, but Anthropic currently documents official support only for Claude Opus 4.6/4.5, Claude Sonnet 4.6/4.5, and Claude Haiku 4.5. Legacy official model IDs should warn rather than being treated as silently supported.
