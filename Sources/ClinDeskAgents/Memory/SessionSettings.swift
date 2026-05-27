public struct SessionSettings: Equatable, Sendable {
    public var limit: Int?

    public init(limit: Int? = nil) {
        self.limit = limit
    }

    public func resolve(_ override: SessionSettings?) -> SessionSettings {
        guard let override else {
            return self
        }
        return SessionSettings(limit: override.limit ?? limit)
    }

    public func toDictionary() -> [String: JSONValue] {
        [
            "limit": limit.map { .number(Double($0)) } ?? .null
        ]
    }

    public static func resolveLimit(
        explicitLimit: Int?,
        settings: SessionSettings?
    ) -> Int? {
        explicitLimit ?? settings?.limit
    }
}
