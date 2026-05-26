# ClinDesk Agents SDK

🧑‍⚕️ **ClinDesk Agents SDK** is a Swift package inspired by OpenAI's Agents SDK and adapted for native Apple platforms. It mirrors the SDK's core concepts as closely as practical in Swift: agents, tools, handoffs, guardrails, sessions, tracing, model providers, and the runner loop.

ClinDesk is a **privacy-first clinic workspace** for macOS. This package extracts the reusable agent runtime shape behind that work into an open source Swift package that can also be used from iOS applications.

This project is open source, free to use, and MIT licensed.

> This package is not affiliated with or endorsed by OpenAI. OpenAI and the OpenAI Agents SDK are trademarks or projects of their respective owners.

## ✨ What It Includes

- 🤖 `Agent` definitions with instructions, tools, handoffs, guardrails, model settings, typed context, and tool-use behavior.
- 🏃 `Runner.run` and `Runner.runStream` for model turns, function tools, handoffs, sessions, tracing, and final output.
- 📋 Structured outputs with typed `Runner.run(..., outputType:)` results.
- 🧰 `FunctionTool` support with Swift `Codable` inputs, JSON schemas, enablement checks, approval callbacks, and tool guardrails.
- 🛡️ Input and output guardrails at both the agent and run-configuration levels.
- 🔁 Handoffs between agents, including input filters.
- 💬 `Session` and `MemorySession` for conversation history.
- 📡 `ClinDeskAgentsOpenAI`, an OpenAI Responses API model provider.
- 🧪 Provider-neutral protocols so apps can plug in OpenAI, local, or on-device models.

The current Swift API is aligned with the core public concepts in OpenAI Agents SDK `v0.17.3`, while leaving out Python-specific implementation details that do not translate cleanly to Swift.

## 📦 Installation

Add the package to your Swift Package Manager dependencies:

```swift
.package(
    name: "clindesk-agents",
    url: "https://github.com/ClinDesk-AI/clindesk-agents-swift.git",
    from: "0.2.1"
)
```

Then add one or both products to your target:

```swift
.product(name: "ClinDeskAgents", package: "clindesk-agents")
.product(name: "ClinDeskAgentsOpenAI", package: "clindesk-agents")
```

Supported platforms:

- macOS 13+
- iOS 16+
- tvOS 16+
- watchOS 9+

## 🚀 Quick Start

```swift
import ClinDeskAgents
import ClinDeskAgentsOpenAI

struct WeatherInput: Decodable, Sendable {
    let city: String
}

let weatherTool = FunctionTool<Void>(
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

let agent = Agent<Void>(
    name: "Clinic Assistant",
    instructions: .text("Answer briefly and use tools when useful."),
    tools: [weatherTool],
    modelName: "gpt-5.4-mini"
)

let result = try await Runner.run(
    agent: agent,
    input: "What is the weather in Cancun?",
    modelProvider: OpenAIProvider()
)

print(result.finalOutput)
```

Set `OPENAI_API_KEY` in the environment when using `ClinDeskAgentsOpenAI`.

## 🧠 Agents

Agents follow the same shape as the OpenAI Agents SDK: they carry instructions, tools, handoffs, optional model configuration, guardrails, and output behavior.

```swift
let agent = Agent<Void>(
    name: "Triage",
    handoffDescription: "Routes clinic requests to the right specialist agent.",
    instructions: .text("Triage the request and hand off when needed."),
    modelName: "gpt-5.4-mini"
)
```

Instructions can also be dynamic:

```swift
struct ClinicContext: Sendable {
    let clinicName: String
}

let agent = Agent<ClinicContext>(
    name: "Assistant",
    instructions: .dynamic { context, _ in
        "You are helping \(context.context?.clinicName ?? "the clinic")."
    }
)
```

## 🧰 Tools

Function tools use explicit names, descriptions, JSON schemas, and async Swift closures.

```swift
struct AppointmentLookup: Decodable, Sendable {
    let patientID: String
}

let lookupAppointment = FunctionTool<Void>(
    name: "lookup_appointment",
    description: "Look up the next appointment for a patient.",
    parameters: [
        "type": "object",
        "properties": [
            "patientID": ["type": "string"]
        ],
        "required": ["patientID"],
        "additionalProperties": false
    ]
) { (_: ToolContext<Void>, input: AppointmentLookup) in
    .json([
        "patientID": .string(input.patientID),
        "nextAppointment": "2026-06-01T09:00:00-05:00"
    ])
}
```

## 🔁 Handoffs

Handoffs expose another agent as a model-callable transfer tool.

```swift
let bookingAgent = Agent<Void>(
    name: "Booking",
    handoffDescription: "Books clinic appointments."
)

let triageAgent = Agent<Void>(
    name: "Triage",
    handoffs: [
        Handoff(to: bookingAgent, toolName: "transfer_to_booking")
    ]
)
```

## 🛡️ Guardrails

Guardrails can run before the model, after final output, or around tool execution.

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

## 💬 Sessions

Use `MemorySession` to keep conversation items across runs.

```swift
let session = MemorySession(id: "patient-thread")

let result = try await Runner.run(
    agent: agent,
    input: "Remember this for the next message.",
    modelProvider: OpenAIProvider(),
    session: session
)
```

Apps that need durable storage can implement the `Session` protocol.

## 📋 Structured Outputs

Use typed runs when an agent should return schema-constrained data instead of free text.

```swift
struct TriageFrame: Decodable, Sendable {
    let intent: String
}

let schema: JSONValue = [
    "type": "object",
    "additionalProperties": false,
    "properties": [
        "intent": ["type": "string"]
    ],
    "required": ["intent"]
]

let result = try await Runner.run(
    agent: agent,
    input: "Need an appointment tomorrow",
    outputType: TriageFrame.self,
    outputSchema: schema,
    modelProvider: OpenAIProvider()
)

print(result.finalOutput.intent)
```

## 📡 OpenAI Provider

`ClinDeskAgentsOpenAI` includes an adapter for the OpenAI Responses API.

```swift
let provider = OpenAIProvider(
    apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
)
```

When an agent or run config does not set a model name, `OpenAIProvider` follows the OpenAI Agents SDK default model behavior: it reads `OPENAI_DEFAULT_MODEL` and otherwise uses `gpt-5.4-mini`.

The core `ClinDeskAgents` target is provider-neutral. It only sends data where your configured `Model` sends it.

## 🍎 Apple Platform Use

This package is designed for Swift concurrency and works in macOS and iOS applications through Swift Package Manager.

In an app target, inject a provider and call the runner from an async context:

```swift
let result = try await Runner.run(
    agent: agent,
    input: userMessage,
    context: clinicContext,
    modelProvider: provider,
    runConfig: RunConfig(
        workflowName: "Clinic workspace",
        traceIncludeSensitiveData: false
    )
)
```

For privacy-sensitive workflows, keep the core runtime provider-neutral and choose the `Model` implementation that matches your deployment.

## 🧪 Development

```bash
swift test
```

The test suite uses fake models and injected OpenAI HTTP transports, so it does not require network access or an API key.

## 📄 License

MIT. See [LICENSE](LICENSE).

## 🙏 Acknowledgements

This project is inspired by the ideas and terminology in OpenAI's Agents SDK. The implementation is written in Swift for ClinDesk and native Apple applications while staying aligned with the upstream SDK's public concepts wherever practical.
