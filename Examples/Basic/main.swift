import ClinDeskAgents

struct LocalDemoModel: Model {
    func getResponse<Context: Sendable>(_ request: ModelRequest<Context>) async throws -> ModelResponse {
        if request.input.contains(where: isClinicLookupOutput) {
            return ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "The clinic is open Monday to Friday."))
            ])
        }
        return ModelResponse(output: [
            .functionCall(FunctionCall(
                callID: "call_clinic_lookup",
                name: "clinic_lookup",
                arguments: ["topic": "hours"]
            ))
        ])
    }

    private func isClinicLookupOutput(_ item: ModelInputItem) -> Bool {
        guard case .functionCallOutput(let output) = item else {
            return false
        }
        return output.callID == "call_clinic_lookup"
    }
}

struct ClinicLookupInput: Decodable, Sendable {
    let topic: String
}

let clinicLookup: FunctionTool<Void> = FunctionTool(
    name: "clinic_lookup",
    description: "Look up public clinic information.",
    parameters: [
        "type": "object",
        "properties": [
            "topic": ["type": "string"]
        ],
        "required": ["topic"],
        "additionalProperties": false
    ]
) { (_: ToolContext<Void>, input: ClinicLookupInput) in
    .json([
        "topic": .string(input.topic),
        "answer": "The clinic is open Monday to Friday."
    ])
}

let agent: Agent<Void> = Agent(
    name: "Clinic Assistant",
    instructions: .text("Answer briefly and use clinic_lookup for clinic facts."),
    tools: [clinicLookup],
    model: LocalDemoModel()
)

let result = try await Runner.run(
    agent: agent,
    input: "When is the clinic open?"
)

print(result.finalOutput)
