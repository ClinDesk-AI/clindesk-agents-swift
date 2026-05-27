import Foundation

public enum ComputerEnvironment: String, Codable, Equatable, Sendable {
    case mac
    case windows
    case ubuntu
    case browser
}

public enum ComputerButton: String, Codable, Equatable, Sendable {
    case left
    case right
    case wheel
    case back
    case forward
}

public struct ComputerDimensions: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public protocol Computer: Sendable {
    var environment: ComputerEnvironment? { get }
    var dimensions: ComputerDimensions? { get }

    func screenshot() async throws -> String
    func click(x: Int, y: Int, button: ComputerButton, keys: [String]?) async throws
    func doubleClick(x: Int, y: Int, keys: [String]?) async throws
    func scroll(x: Int, y: Int, scrollX: Int, scrollY: Int, keys: [String]?) async throws
    func type(_ text: String) async throws
    func wait() async throws
    func move(x: Int, y: Int, keys: [String]?) async throws
    func keypress(_ keys: [String]) async throws
    func drag(path: [ComputerPoint], keys: [String]?) async throws
}

public extension Computer {
    var environment: ComputerEnvironment? { nil }
    var dimensions: ComputerDimensions? { nil }
}

public struct ComputerPoint: Codable, Equatable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct PendingComputerSafetyCheck: Codable, Equatable, Sendable {
    public var id: String
    public var code: String
    public var message: String

    public init(id: String, code: String, message: String) {
        self.id = id
        self.code = code
        self.message = message
    }
}

public struct ComputerAction: Codable, Equatable, Sendable {
    public var type: String
    public var x: Int?
    public var y: Int?
    public var button: ComputerButton?
    public var scrollX: Int?
    public var scrollY: Int?
    public var text: String?
    public var keys: [String]?
    public var path: [ComputerPoint]?

    public init(
        type: String,
        x: Int? = nil,
        y: Int? = nil,
        button: ComputerButton? = nil,
        scrollX: Int? = nil,
        scrollY: Int? = nil,
        text: String? = nil,
        keys: [String]? = nil,
        path: [ComputerPoint]? = nil
    ) {
        self.type = type
        self.x = x
        self.y = y
        self.button = button
        self.scrollX = scrollX
        self.scrollY = scrollY
        self.text = text
        self.keys = keys
        self.path = path
    }

    enum CodingKeys: String, CodingKey {
        case type
        case x
        case y
        case button
        case scrollX = "scroll_x"
        case scrollY = "scroll_y"
        case text
        case keys
        case path
    }
}

public struct ComputerCall: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var callID: String
    public var action: ComputerAction?
    public var actions: [ComputerAction]
    public var pendingSafetyChecks: [PendingComputerSafetyCheck]
    public var status: String?
    public var raw: JSONValue?

    public init(
        id: String = UUID().uuidString,
        callID: String = UUID().uuidString,
        action: ComputerAction? = nil,
        actions: [ComputerAction] = [],
        pendingSafetyChecks: [PendingComputerSafetyCheck] = [],
        status: String? = nil,
        raw: JSONValue? = nil
    ) {
        self.id = id
        self.callID = callID
        self.action = action
        self.actions = actions
        self.pendingSafetyChecks = pendingSafetyChecks
        self.status = status
        self.raw = raw
    }

    public var effectiveActions: [ComputerAction] {
        if !actions.isEmpty {
            return actions
        }
        return action.map { [$0] } ?? []
    }

    enum CodingKeys: String, CodingKey {
        case id
        case callID = "call_id"
        case action
        case actions
        case pendingSafetyChecks = "pending_safety_checks"
        case status
    }
}

public struct ComputerCallOutput: Codable, Equatable, Sendable {
    public var callID: String
    public var output: JSONValue
    public var acknowledgedSafetyChecks: [PendingComputerSafetyCheck]?

    public init(
        callID: String,
        output: JSONValue,
        acknowledgedSafetyChecks: [PendingComputerSafetyCheck]? = nil
    ) {
        self.callID = callID
        self.output = output
        self.acknowledgedSafetyChecks = acknowledgedSafetyChecks
    }

    enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case output
        case acknowledgedSafetyChecks = "acknowledged_safety_checks"
    }
}

public struct ComputerToolDescriptor: Codable, Equatable, Sendable {
    public var usePreview: Bool
    public var environment: ComputerEnvironment?
    public var dimensions: ComputerDimensions?

    public init(
        usePreview: Bool = false,
        environment: ComputerEnvironment? = nil,
        dimensions: ComputerDimensions? = nil
    ) {
        self.usePreview = usePreview
        self.environment = environment
        self.dimensions = dimensions
    }

    public var name: String {
        usePreview ? "computer_use_preview" : "computer"
    }
}

public struct ComputerToolSafetyCheckData<Context: Sendable>: Sendable {
    public var context: RunContext<Context>
    public var agent: Agent<Context>
    public var toolCall: ComputerCall
    public var safetyCheck: PendingComputerSafetyCheck

    public init(
        context: RunContext<Context>,
        agent: Agent<Context>,
        toolCall: ComputerCall,
        safetyCheck: PendingComputerSafetyCheck
    ) {
        self.context = context
        self.agent = agent
        self.toolCall = toolCall
        self.safetyCheck = safetyCheck
    }
}

public struct ComputerTool<Context: Sendable>: Sendable {
    public typealias SafetyCheck = @Sendable (
        ComputerToolSafetyCheckData<Context>
    ) async throws -> Bool

    public var computer: (any Computer)?
    public var descriptor: ComputerToolDescriptor
    public var onSafetyCheck: SafetyCheck?

    public init(
        computer: (any Computer)? = nil,
        descriptor: ComputerToolDescriptor = ComputerToolDescriptor(),
        onSafetyCheck: SafetyCheck? = nil
    ) {
        self.computer = computer
        self.descriptor = descriptor
        self.onSafetyCheck = onSafetyCheck
    }

    public var name: String {
        "computer_use_preview"
    }

    public var traceName: String {
        "computer"
    }

    public var modelDescriptor: ComputerToolDescriptor {
        guard descriptor.usePreview,
              let computer
        else {
            return descriptor
        }
        return ComputerToolDescriptor(
            usePreview: true,
            environment: descriptor.environment ?? computer.environment,
            dimensions: descriptor.dimensions ?? computer.dimensions
        )
    }
}
