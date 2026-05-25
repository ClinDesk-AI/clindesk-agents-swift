import Foundation

public protocol Session: Sendable {
    var id: String { get }
    func getItems(limit: Int?) async throws -> [ModelInputItem]
    func addItems(_ items: [ModelInputItem]) async throws
    func popItem() async throws -> ModelInputItem?
    func clear() async throws
}

public extension Session {
    func getItems() async throws -> [ModelInputItem] {
        try await getItems(limit: nil)
    }
}

public actor MemorySession: Session {
    public let id: String
    private var items: [ModelInputItem]

    public init(id: String = UUID().uuidString, items: [ModelInputItem] = []) {
        self.id = id
        self.items = items
    }

    public func getItems(limit: Int? = nil) async throws -> [ModelInputItem] {
        guard let limit, limit >= 0 else {
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

    public func clear() async throws {
        items.removeAll()
    }
}
