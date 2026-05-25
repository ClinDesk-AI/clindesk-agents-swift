# Repository Instructions

- Keep this Swift package aligned as closely as possible with OpenAI's Agents SDK. Do not invent new runtime features, abstractions, naming, behavior, or "improvements" unless they directly correspond to behavior in the upstream OpenAI Agents SDK and are adapted only as needed for Swift conventions.
- When changing public API or behavior, check the upstream `openai/openai-agents-python` repository first and mirror its concepts, defaults, and semantics wherever they make sense in Swift.
- Leave out Python-specific implementation details that do not translate cleanly to Swift, but do not replace them with unrelated Swift-only features.
