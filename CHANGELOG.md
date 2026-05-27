# Changelog

All notable changes to this package are documented here.

This project follows Swift Package Manager tag-based releases. The `1.0.0` release is the first
local-model-only Swift parity release against OpenAI Agents SDK `v0.17.4`.

## 1.0.0 - 2026-05-27

### Added

- Added local-first Swift equivalents for the core Agents SDK runtime surface: agents, runner
  loops, model requests and responses, run results, streamed run results, run state snapshots,
  handoffs, guardrails, sessions, tracing, model settings, retry settings, and usage accounting.
- Added provider-neutral prompt definitions and dynamic prompt resolution on agents, with resolved
  prompt metadata passed to local `ModelRequest` values.
- Added a package-scoped `AgentsLogger` facade mirroring upstream's central logger concept through
  Apple's unified logging system.
- Added local-only `MultiProviderMap` and `MultiProvider` prefix routing for model providers,
  mirroring upstream provider-dispatch concepts without cloud-provider fallbacks.
- Added upstream-aligned local `ModelSettings` fields for store hints, prompt cache retention,
  response include hints, and context-management metadata without adding OpenAI API clients.
- Aligned direct `ModelSettings` `Codable` serialization with the upstream snake-case setting
  shape, matching `toJSONDictionary()`.
- Added public `Agent.getSystemPrompt(runContext:)` and `Agent.getPrompt(runContext:)` helpers
  matching the upstream agent prompt resolution surface.
- Added `ItemHelpers.extractLastContent(_:)` and `ItemHelpers.extractLastText(_:)` to mirror the
  upstream item helper surface.
- Added upstream-style item preparation helpers for run-item conversion, model-input
  normalization, orphan generated-tool-call pruning, stable item fingerprinting, and deduplication.
- Aligned raw reasoning item pruning with upstream so raw `reasoning` dictionaries are removed
  when their following generated tool call is pruned as orphaned.
- Aligned session model-input preparation with upstream local behavior by normalizing stored
  history, pruning orphan historical tool calls, stripping internal metadata, and deduplicating
  stable item IDs before model requests.
- Split prepared model input from session-persisted input so session callbacks can rewrite or
  filter history without re-persisting old history as fresh turn input.
- Aligned input-guardrail session behavior with upstream by running guardrails against the
  original turn input and persisting the prepared new-turn session items when a guardrail trips.
- Aligned max-turn session behavior with upstream by persisting prepared turn input and completed
  turn items before raising an unhandled max-turn error.
- Preserved input-guardrail results on streamed run objects when a tripwire throws, matching
  upstream streamed-result state behavior.
- Aligned streamed cancellation with upstream immediate-cancel behavior by wiring Swift task
  cancellation into the run-loop cancellation checks.
- Added local tool support for function tools, custom tools, computer actions, shell execution,
  apply-patch calls, tool approvals, tool guardrails, structured tool outputs, tool origins, tool
  namespaces, and tool-use final-output behavior.
- Added upstream-style `ToolIdentity` helpers for tool-call names, qualified names, trace names,
  dispatch names, lookup keys, and deferred top-level call normalization.
- Added upstream-style run lifecycle features including default agent runner overrides,
  max-turn handling, model refusal handlers, run error details, prompt cache grouping,
  model input filtering, session input callbacks, handoff history mapping, and serialized
  approval-resume state.
- Aligned reset-tool-choice tracking with upstream runtime semantics by tracking newly observed
  tool use per agent identity while preserving name-keyed serialized run-state hydration.
- Added upstream-style public-agent binding for execution-only clones so typed output schema runs
  send schema metadata to the model while hooks, dynamic prompts, errors, and results expose the
  original public agent.
- Updated function and custom tool contexts to expose the public agent during execution-only
  typed-output runs, matching upstream's public-agent tool execution behavior.
- Added upstream-style guardrail scheduling: non-parallel input guardrails run first, parallel
  input guardrails run concurrently, and output guardrails run concurrently.
- Added extension helpers for handoff prompts, handoff filters, tool-output trimming, string
  transforms, pretty printing, and DOT graph visualization.
- Added split test coverage across runner, tools, handoffs, memory, tracing, providers,
  extensions, local tools, and utility modules.
- Added local-only README examples and documentation for the supported runtime surface.

### Changed

- Reorganized the source layout to follow the upstream Agents SDK package structure more closely
  while keeping Swift naming and file conventions.
- Renamed response-specific public concepts to local provider-neutral terminology, including
  `modelResponses` and `ModelResponseStreamEvent`.
- Updated defaults for local model execution, including `CLINDESK_AGENTS_DEFAULT_MODEL` and
  local privacy/debug environment variables.
- Updated CI to build and test the remaining local-only `ClinDeskAgents` product.

### Removed

- Removed the `ClinDeskAgentsOpenAI` product and target.
- Removed OpenAI API provider/client configuration, Responses API model plumbing, server-managed
  conversation support, hosted tool surfaces, MCP surfaces, OpenAI tracing API-key export, and
  other cloud-provider-specific overhead.
- Removed public README guidance that implied OpenAI API configuration was part of this package.

### Verification

- Current local verification passes with `swift test` and the iOS simulator build for the
  `ClinDeskAgents` scheme.
- Repository residue scans exclude OpenAI API/provider-specific symbols from package sources,
  tests, examples, README, package manifest, and CI workflow files.

## 0.2.1 - 2025-05-25

### Added

- Added typed structured outputs through `Runner.run(..., outputType:)`.
- Added structured-output decoding and validation coverage.

## 0.2.0 - 2025-05-25

### Added

- Expanded the runner toward OpenAI Agents SDK concepts.
- Added run configuration, handoff, tool, and runner behavior coverage.
- Added initial CI workflow coverage for Apple platform checks.

### Changed

- Renamed the package to `clindesk-agents`.
- Updated README and package metadata for the renamed package.

## 0.1.0 - 2025-05-25

### Added

- Initial Swift agents SDK package.

### Fixed

- Fixed Linux `URLRequest` import handling.
