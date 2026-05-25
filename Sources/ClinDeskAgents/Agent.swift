import Foundation

public enum Instructions<Context: Sendable>: Sendable {
    public typealias Builder = @Sendable (RunContext<Context>, Agent<Context>) async throws -> String?

    case text(String)
    case dynamic(Builder)

    public func resolve(context: RunContext<Context>, agent: Agent<Context>) async throws -> String? {
        switch self {
        case .text(let value):
            return value
        case .dynamic(let builder):
            return try await builder(context, agent)
        }
    }
}

public struct Agent<Context: Sendable>: Sendable {
    public var name: String
    public var handoffDescription: String?
    public var instructions: Instructions<Context>?
    public var tools: [FunctionTool<Context>]
    public var handoffs: [Handoff<Context>]
    public var model: (any Model)?
    public var modelName: String?
    public var modelSettings: ModelSettings
    public var inputGuardrails: [InputGuardrail<Context>]
    public var outputGuardrails: [OutputGuardrail<Context>]
    public var outputSchema: JSONValue?
    public var toolUseBehavior: ToolUseBehavior<Context>
    public var resetToolChoice: Bool

    public init(
        name: String,
        handoffDescription: String? = nil,
        instructions: Instructions<Context>? = nil,
        tools: [FunctionTool<Context>] = [],
        handoffs: [Handoff<Context>] = [],
        model: (any Model)? = nil,
        modelName: String? = nil,
        modelSettings: ModelSettings = ModelSettings(),
        inputGuardrails: [InputGuardrail<Context>] = [],
        outputGuardrails: [OutputGuardrail<Context>] = [],
        outputSchema: JSONValue? = nil,
        toolUseBehavior: ToolUseBehavior<Context> = .runModelAgain,
        resetToolChoice: Bool = true
    ) {
        self.name = name
        self.handoffDescription = handoffDescription
        self.instructions = instructions
        self.tools = tools
        self.handoffs = handoffs
        self.model = model
        self.modelName = modelName
        self.modelSettings = modelSettings
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
        self.outputSchema = outputSchema
        self.toolUseBehavior = toolUseBehavior
        self.resetToolChoice = resetToolChoice
    }

    public func clone(
        name: String? = nil,
        handoffDescription: String? = nil,
        instructions: Instructions<Context>? = nil,
        tools: [FunctionTool<Context>]? = nil,
        handoffs: [Handoff<Context>]? = nil,
        model: (any Model)? = nil,
        modelName: String? = nil,
        modelSettings: ModelSettings? = nil,
        inputGuardrails: [InputGuardrail<Context>]? = nil,
        outputGuardrails: [OutputGuardrail<Context>]? = nil,
        outputSchema: JSONValue? = nil,
        toolUseBehavior: ToolUseBehavior<Context>? = nil,
        resetToolChoice: Bool? = nil
    ) -> Agent<Context> {
        Agent(
            name: name ?? self.name,
            handoffDescription: handoffDescription ?? self.handoffDescription,
            instructions: instructions ?? self.instructions,
            tools: tools ?? self.tools,
            handoffs: handoffs ?? self.handoffs,
            model: model ?? self.model,
            modelName: modelName ?? self.modelName,
            modelSettings: modelSettings ?? self.modelSettings,
            inputGuardrails: inputGuardrails ?? self.inputGuardrails,
            outputGuardrails: outputGuardrails ?? self.outputGuardrails,
            outputSchema: outputSchema ?? self.outputSchema,
            toolUseBehavior: toolUseBehavior ?? self.toolUseBehavior,
            resetToolChoice: resetToolChoice ?? self.resetToolChoice
        )
    }

    public func asTool(
        name: String? = nil,
        description: String? = nil,
        modelProvider: any ModelProvider,
        runConfig: RunConfig<Context> = RunConfig()
    ) -> FunctionTool<Context> {
        let toolName = name ?? Handoff<Context>.defaultToolName(for: self.name)
        return FunctionTool(
            name: toolName,
            description: description ?? handoffDescription ?? "Run \(self.name) as a tool.",
            parameters: [
                "type": "object",
                "additionalProperties": true
            ]
        ) { toolContext, arguments in
            let input = arguments["input"]?.stringValue ?? arguments.prettyPrinted()
            let result = try await Runner.run(
                agent: self,
                input: input,
                context: toolContext.runContext.context,
                modelProvider: modelProvider,
                runConfig: runConfig
            )
            return .text(result.finalOutput)
        }
    }
}
