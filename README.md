# ClinDesk Agents SDK

🧑‍⚕️ **ClinDesk Agents SDK** is a local-first Swift agent runtime for native Apple platforms. It keeps the familiar Agents SDK shape: agents, tools, handoffs, guardrails, sessions, tracing, model providers, and the runner loop, while leaving model execution entirely to local, on-device, or application-supplied `Model` implementations.

ClinDesk is a privacy-first clinic workspace for macOS. This package extracts the reusable agent runtime behind that work into an open source Swift package that can also be used from iOS applications.

This project is open source, free to use, and MIT licensed.

> This package is not affiliated with or endorsed by OpenAI. OpenAI and the OpenAI Agents SDK are trademarks or projects of their respective owners.

## ✨ What It Includes

- 🤖 `Agent` definitions with instructions, tools, handoffs, guardrails, model settings, typed context, and tool-use behavior.
- 🏃 `Runner.run` and `Runner.runStream` for model turns, function tools, local tools, handoffs, sessions, tracing, and final output.
- 📋 Structured outputs with typed `Runner.run(..., outputType:)` results.
- 🧰 `FunctionTool` support with Swift `Codable` inputs, JSON schemas, enablement checks, approval callbacks, and tool guardrails.
- 🛡️ Input and output guardrails at both the agent and run-configuration levels.
- 🔁 Handoffs between agents, including input filters.
- 🗺️ Extension helpers for handoff prompts, handoff filters, tool-output trimming, and agent graph visualization.
- 💬 `Session` and `MemorySession` for conversation history.
- 🧪 Provider-neutral `Model` and `ModelProvider` protocols for local or on-device model backends.

The Swift API mirrors the core public agent-runtime concepts from OpenAI's Agents SDK where those concepts make sense in Swift, while omitting Python-specific and cloud-provider-specific implementation details.

## 📦 Installation

Add the package to your Swift Package Manager dependencies:

```swift
.package(
    name: "clindesk-agents",
    url: "https://github.com/ClinDesk-AI/clindesk-agents-swift.git",
    from: "1.0.0"
)
```

Then add the product to your target:

```swift
.product(name: "ClinDeskAgents", package: "clindesk-agents")
```

Supported platforms:

- macOS 13+
- iOS 16+
- tvOS 16+
- watchOS 9+

## 🚀 Quick Start

```swift
import ClinDeskAgents

struct LocalDemoModel: Model {
    func getResponse(request: ModelRequest) async throws -> ModelResponse {
        if request.input.contains(where: { item in
            if case .message(let message) = item {
                return message.content.localizedCaseInsensitiveContains("weather")
            }
            return false
        }) {
            return ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_weather",
                    name: "weather",
                    arguments: #"{"city":"Cancun"}"#
                ))
            ])
        }

        return ModelResponse(output: [
            .message(AgentMessage(role: .assistant, content: "It is sunny in Cancun."))
        ])
    }

    func streamResponse(request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(.completed(try await getResponse(request: request)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

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
    model: LocalDemoModel()
)

let result = try await Runner.run(
    agent: agent,
    input: "What is the weather in Cancun?"
)

print(result.finalOutput)
```

## 🧠 Agents

Agents carry instructions, tools, handoffs, optional model configuration, guardrails, and output behavior.

```swift
let agent = Agent<Void>(
    name: "Triage",
    handoffDescription: "Routes clinic requests to the right specialist agent.",
    instructions: .text("Triage the request and hand off when needed."),
    modelName: "local-triage"
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

The runtime also includes local tool surfaces such as computer, shell, apply-patch, and custom tools. Those tools execute only through code you provide or explicitly configure.

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
    outputSchema: schema
)

print(result.finalOutput.intent)
```

## 🖥️ Local Models

The core target is model-provider neutral. You can attach a concrete `Model` directly to an agent or provide a `ModelProvider` through `RunConfig`.

For multiple local backends, `MultiProvider` routes namespaced model IDs by prefix:

```swift
let provider = MultiProvider(
    providerMap: MultiProviderMap([
        "clinic": clinicProvider,
        "scribe": scribeProvider
    ])
)

let agent = Agent<Void>(name: "Triage", modelName: "clinic/triage")
```

```swift
let result = try await Runner.run(
    agent: agent,
    input: userMessage,
    context: clinicContext,
    runConfig: RunConfig(
        workflowName: "Clinic workspace",
        traceIncludeSensitiveData: false
    )
)
```

When no model name is configured, the package uses `CLINDESK_AGENTS_DEFAULT_MODEL` and otherwise falls back to `"local"` for provider lookup.

Models that return `true` from `supportsDefaultPromptCacheKey` receive a generated `prompt_cache_key` in `ModelSettings.extraArgs` unless the caller already supplied one. The key follows the upstream grouping order of session, trace group, then run, and remains stable across approval resume flows.

Sensitive model and tool payloads stay out of debug logs by default. Use `CLINDESK_AGENTS_DONT_LOG_MODEL_DATA` or `CLINDESK_AGENTS_DONT_LOG_TOOL_DATA` with `0`, `1`, `true`, or `false` to mirror the upstream debug toggles with local-only names.

Use `AgentsLogger.shared` for package-scoped diagnostics when integrating with Apple's unified logging system.

## 🧪 Development

```bash
swift test
```

The test suite uses fake and local models, so it does not require network access or API keys.

Release notes are tracked in [CHANGELOG.md](CHANGELOG.md). The current release is the
local-model-only `1.0.0` parity release.

## 📄 License

MIT. See [LICENSE](LICENSE).
