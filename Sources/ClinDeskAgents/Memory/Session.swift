public protocol Session: Sendable {
    var sessionID: String { get }
    var sessionSettings: SessionSettings? { get }
    func getItems(limit: Int?) async throws -> [ModelInputItem]
    func addItems(_ items: [ModelInputItem]) async throws
    func popItem() async throws -> ModelInputItem?
    func clearSession() async throws
}

public extension Session {
    var sessionSettings: SessionSettings? {
        nil
    }

    func getItems() async throws -> [ModelInputItem] {
        try await getItems(limit: nil)
    }
}
