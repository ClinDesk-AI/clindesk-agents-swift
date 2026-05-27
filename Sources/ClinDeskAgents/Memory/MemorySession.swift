import Foundation

public actor MemorySession: Session {
    public nonisolated let sessionID: String
    public nonisolated let sessionSettings: SessionSettings?
    private var items: [ModelInputItem]

    public init(
        sessionID: String = UUID().uuidString,
        items: [ModelInputItem] = [],
        sessionSettings: SessionSettings? = SessionSettings()
    ) {
        self.sessionID = sessionID
        self.sessionSettings = sessionSettings
        self.items = items
    }

    public func getItems(limit: Int? = nil) async throws -> [ModelInputItem] {
        guard let limit = SessionSettings.resolveLimit(
            explicitLimit: limit,
            settings: sessionSettings
        ), limit >= 0 else {
            return items
        }
        return Array(items.suffix(limit))
    }

    public func addItems(_ items: [ModelInputItem]) async throws {
        self.items.append(contentsOf: items)
    }

    public func popItem() async throws -> ModelInputItem? {
        items.popLast()
    }

    public func clearSession() async throws {
        items.removeAll()
    }
}
