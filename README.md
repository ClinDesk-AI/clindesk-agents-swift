# ClinDesk Agents Swift

ClinDesk Agents Swift is a lightweight agent runtime for Swift applications. It is inspired by OpenAI's Agents SDK concepts, but it is written from scratch for Swift, Swift concurrency, and the macOS ClinDesk application.

ClinDesk is a private WhatsApp assistant for doctors. It runs on the clinician's own Mac, with no SaaS requirement and with patient data kept on the computer by default. This package extracts the reusable agent runtime shape behind that work into an open source Swift package.

This project is open source, free to use, and MIT licensed.

> This package is not affiliated with or endorsed by OpenAI. OpenAI and the OpenAI Agents SDK are trademarks or projects of their respective owners.

## What It Includes

- Agents with instructions, tools, handoffs, guardrails, model settings, and typed context.
- A `Runner` loop that executes model turns, function tools, handoffs, sessions, tracing, and final output guardrails.
- Swift-native tool definitions using `Codable`, `Sendable`, async closures, and explicit JSON schemas.
- Session memory through `MemorySession`.
- Streaming run events through `AsyncThrowingStream`.
- An OpenAI Responses API adapter in `ClinDeskAgentsOpenAI`.
- Testable model/provider protocols so apps can plug in local or on-device models.

The first release focuses on core agent workflows. Sandbox agents, realtime voice agents, and richer hosted tools are roadmap items.

## Installation

Add the package to your Swift Package Manager dependencies:

```swift
.package(
    url: "https://github.com/ClinDesk-AI/clindesk-agents-swift.git",
    from: "0.1.0"
)
```

Then add one or both products to your target:

```swift
.product(name: "ClinDeskAgents", package: "clindesk-agents-swift")
.product(name: "ClinDeskAgentsOpenAI", package: "clindesk-agents-swift")
```

## Quick Start

```swift
import ClinDeskAgents
import ClinDeskAgentsOpenAI

struct WeatherInput: Decodable, Sendable {
    let city: String
}

let weatherTool: FunctionTool<Void> = FunctionTool(
    name: "weather",
    description: "Get a short weather summary for a city.",
    parameters: [
        "type": "object",
        "properties": [
            "city": ["type": "string"]
        ],
        "required": ["city"],
        "additionalProperties": false
    ]
) { (_: ToolContext<Void>, input: WeatherInput) in
    .json([
        "city": .string(input.city),
        "forecast": "sunny"
    ])
}

let agent: Agent<Void> = Agent(
    name: "Clinic Assistant",
    instructions: .text("Answer briefly and use tools when useful."),
    tools: [weatherTool],
    modelName: "gpt-5"
)

let provider = OpenAIProvider()

let result = try await Runner.run(
    agent: agent,
    input: "What is the weather in Cancun?",
    modelProvider: provider
)

print(result.finalOutput)
```

Set `OPENAI_API_KEY` in the environment when using `ClinDeskAgentsOpenAI`.

## Using a Local Model

ClinDesk can run with a local or on-device model by implementing `Model` directly:

```swift
import ClinDeskAgents

struct LocalModel: Model {
    func getResponse<Context: Sendable>(
        _ request: ModelRequest<Context>
    ) async throws -> ModelResponse {
        ModelResponse(output: [
            .message(.init(role: .assistant, content: "Local response"))
        ])
    }
}

let agent: Agent<Void> = Agent(
    name: "Local Assistant",
    instructions: .text("Keep all work on this Mac."),
    model: LocalModel()
)
```

The runtime does not require OpenAI. The OpenAI adapter is just one provider.

## Guardrails

Guardrails can stop a run before the model starts, after final output, or around tool execution:

```swift
let noEmptyInput = InputGuardrail<Void>(name: "no_empty_input") { _, _, input in
    let hasText = input.contains {
        if case .message(let message) = $0 {
            return !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    return GuardrailFunctionOutput(
        outputInfo: hasText ? "ok" : "empty input",
        tripwireTriggered: !hasText
    )
}
```

## Handoffs

Handoffs expose another agent as a model-callable transfer tool:

```swift
let bookingAgent: Agent<Void> = Agent(
    name: "Booking",
    handoffDescription: "Books clinic appointments."
)

let triageAgent: Agent<Void> = Agent(
    name: "Triage",
    handoffs: [
        Handoff(to: bookingAgent, toolName: "transfer_to_booking")
    ]
)
```

## Sessions

Use `MemorySession` to keep conversation items across runs:

```swift
let session = MemorySession(id: "patient-thread")

let result = try await Runner.run(
    agent: agent,
    input: "Remember this for the next message.",
    modelProvider: provider,
    runConfig: RunConfig(session: session)
)
```

Apps that need durable storage can implement the `Session` protocol.

## Privacy

The core runtime is provider-neutral. It only sends data where your configured `Model` sends it.

- `ClinDeskAgents` can be used entirely with local models.
- `ClinDeskAgentsOpenAI` sends requests to the configured OpenAI API endpoint.
- Tracing defaults to excluding sensitive data.

## Roadmap

- SQLite-backed session storage.
- MCP client integration for remote tools.
- OpenTelemetry trace export.
- Realtime and voice-oriented agent sessions.
- Sandbox-style long-running workspace agents.

## Development

```bash
swift test
```

The test suite uses fake models and an injected OpenAI HTTP transport, so it does not require network access or an API key.

## License

MIT. See [LICENSE](LICENSE).

## Acknowledgements

This project is inspired by the ideas and terminology in OpenAI's Agents SDK, especially agents, tools, handoffs, guardrails, sessions, and tracing. The Swift implementation is tailored for ClinDesk and native Swift applications.
