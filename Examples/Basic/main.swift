import ClinDeskAgents
import ClinDeskAgentsOpenAI

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
    modelName: "gpt-5.4-mini"
)

let provider = OpenAIProvider()
let result = try await Runner.run(
    agent: agent,
    input: "When is the clinic open?",
    modelProvider: provider
)

print(result.finalOutput)
