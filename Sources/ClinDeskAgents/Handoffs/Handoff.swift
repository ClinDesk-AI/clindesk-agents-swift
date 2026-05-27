import Foundation

public struct HandoffInputData<Context: Sendable>: Sendable {
    public var inputHistory: [ModelInputItem]
    public var preHandoffItems: [ModelInputItem]
    public var newItems: [ModelInputItem]
    public var runContext: RunContext<Context>?
    public var inputItems: [ModelInputItem]?

    public init(
        inputHistory: [ModelInputItem],
        preHandoffItems: [ModelInputItem],
        newItems: [ModelInputItem],
        runContext: RunContext<Context>? = nil,
        inputItems: [ModelInputItem]? = nil
    ) {
        self.inputHistory = inputHistory
        self.preHandoffItems = preHandoffItems
        self.newItems = newItems
        self.runContext = runContext
        self.inputItems = inputItems
    }

    public func clone(
        inputHistory: [ModelInputItem]? = nil,
        preHandoffItems: [ModelInputItem]? = nil,
        newItems: [ModelInputItem]? = nil,
        inputItems: [ModelInputItem]? = nil
    ) -> HandoffInputData {
        HandoffInputData(
            inputHistory: inputHistory ?? self.inputHistory,
            preHandoffItems: preHandoffItems ?? self.preHandoffItems,
            newItems: newItems ?? self.newItems,
            runContext: runContext,
            inputItems: inputItems ?? self.inputItems
        )
    }

    public var modelInputItems: [ModelInputItem] {
        inputHistory + preHandoffItems + (inputItems ?? newItems)
    }

    public var sessionItems: [ModelInputItem] {
        preHandoffItems + newItems
    }
}

public typealias HandoffInputFilter<Context: Sendable> = @Sendable (
    HandoffInputData<Context>
) async throws -> HandoffInputData<Context>
public typealias HandoffHistoryMapper = @Sendable ([ModelInputItem]) async throws -> [ModelInputItem]

public struct HandoffDescriptor: Codable, Equatable, Sendable {
    public var toolName: String
    public var description: String
    public var inputSchema: JSONValue

    public init(toolName: String, description: String, inputSchema: JSONValue = .emptyObject) {
        self.toolName = toolName
        self.description = description
        self.inputSchema = (try? StrictSchema.ensureStrictJSONSchema(inputSchema)) ?? inputSchema
    }
}

public struct Handoff<Context: Sendable>: Sendable {
    public typealias Enabled = @Sendable (RunContext<Context>) async -> Bool
    public typealias InputFilter = HandoffInputFilter<Context>
    public typealias OnHandoff = @Sendable (RunContext<Context>, JSONValue) async throws -> Void
    public typealias NoInputOnHandoff = @Sendable (RunContext<Context>) async throws -> Void

    public var descriptor: HandoffDescriptor
    public var isEnabled: Enabled
    public var inputFilter: InputFilter?
    public var nestHandoffHistory: Bool?
    private let resolveAgent: @Sendable () -> Agent<Context>
    private let invokeHandoff: @Sendable (RunContext<Context>, JSONValue) async throws -> Agent<Context>

    public var agent: Agent<Context> {
        resolveAgent()
    }

    public init(
        to agent: Agent<Context>,
        toolName: String? = nil,
        description: String? = nil,
        inputSchema: JSONValue = .emptyObject,
        isEnabled: @escaping Enabled = { _ in true },
        inputFilter: InputFilter? = nil,
        nestHandoffHistory: Bool? = nil,
        onHandoff: OnHandoff? = nil
    ) {
        self.descriptor = HandoffDescriptor(
            toolName: toolName ?? Self.defaultToolName(for: agent.name),
            description: description ?? Self.defaultToolDescription(for: agent),
            inputSchema: inputSchema
        )
        self.isEnabled = isEnabled
        self.inputFilter = inputFilter
        self.nestHandoffHistory = nestHandoffHistory
        self.resolveAgent = { agent }
        self.invokeHandoff = { context, arguments in
            try await onHandoff?(context, arguments)
            return agent
        }
    }

    public init(
        to agent: Agent<Context>,
        toolName: String? = nil,
        description: String? = nil,
        inputSchema: JSONValue = .emptyObject,
        isEnabled: @escaping Enabled = { _ in true },
        inputFilter: InputFilter? = nil,
        nestHandoffHistory: Bool? = nil,
        onHandoff: @escaping NoInputOnHandoff
    ) {
        self.init(
            to: agent,
            toolName: toolName,
            description: description,
            inputSchema: inputSchema,
            isEnabled: isEnabled,
            inputFilter: inputFilter,
            nestHandoffHistory: nestHandoffHistory,
            onHandoff: { context, _ in
                try await onHandoff(context)
            }
        )
    }

    public init<Input: Decodable & Sendable>(
        to agent: Agent<Context>,
        toolName: String? = nil,
        description: String? = nil,
        inputSchema: JSONValue,
        isEnabled: @escaping Enabled = { _ in true },
        inputFilter: InputFilter? = nil,
        nestHandoffHistory: Bool? = nil,
        onHandoff: @escaping @Sendable (RunContext<Context>, Input) async throws -> Void
    ) {
        self.init(
            to: agent,
            toolName: toolName,
            description: description,
            inputSchema: inputSchema,
            isEnabled: isEnabled,
            inputFilter: inputFilter,
            nestHandoffHistory: nestHandoffHistory,
            onHandoff: { context, arguments in
                let input = try arguments.decoded(Input.self)
                try await onHandoff(context, input)
            }
        )
    }

    public static func defaultToolName(for agentName: String) -> String {
        TransformUtils.transformStringFunctionStyle("transfer_to_\(agentName)")
    }

    public static func defaultToolDescription(for agent: Agent<Context>) -> String {
        "Handoff to the \(agent.name) agent to handle the request. \(agent.handoffDescription ?? "")"
    }

    public func transferMessage(for agent: Agent<Context>) -> String {
        let encodedName = JSONValue.string(agent.name).prettyPrinted()
        return #"{"assistant": \#(encodedName)}"#
    }

    public func invoke(context: RunContext<Context>, arguments: JSONValue) async throws -> Agent<Context> {
        try await invokeHandoff(context, arguments)
    }
}
