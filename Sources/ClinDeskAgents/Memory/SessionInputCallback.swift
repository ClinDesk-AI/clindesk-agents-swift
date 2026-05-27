public typealias SessionInputCallback = @Sendable (
    _ history: [ModelInputItem],
    _ newInput: [ModelInputItem]
) async throws -> [ModelInputItem]
