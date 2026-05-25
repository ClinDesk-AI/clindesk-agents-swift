import Foundation

public struct RunContext<Context: Sendable>: Sendable {
    public var runID: String
    public var context: Context?
    public var metadata: [String: JSONValue]
    public var cancellation: @Sendable () -> Bool

    public init(
        runID: String = UUID().uuidString,
        context: Context? = nil,
        metadata: [String: JSONValue] = [:],
        cancellation: @escaping @Sendable () -> Bool = { false }
    ) {
        self.runID = runID
        self.context = context
        self.metadata = metadata
        self.cancellation = cancellation
    }

    public func throwingIfCancelled() throws {
        if cancellation() {
            throw AgentsError.cancelled
        }
    }
}
