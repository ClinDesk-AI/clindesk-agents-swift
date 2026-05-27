import Testing
import ClinDeskAgents

@Suite
struct SQLiteSessionLimitTests {
    @Test
    func getItemsLimitReturnsLatestItemsChronologically() async throws {
        let temp = try SQLiteSessionTestSupport.temporaryDatabasePath("limit.db")
        defer { temp.cleanup() }
        let session = try SQLiteSession(sessionID: "limit_test", dbPath: temp.path)
        defer { session.close() }
        let items = (1...6).map { SQLiteSessionTestSupport.message(.user, "Message \($0)") }

        try await session.addItems(items)

        #expect(try await session.getItems() == items)
        #expect(try await session.getItems(limit: 2) == Array(items.suffix(2)))
        #expect(try await session.getItems(limit: 4) == Array(items.suffix(4)))
        #expect(try await session.getItems(limit: 10) == items)
        #expect(try await session.getItems(limit: 0) == [])
    }

    @Test
    func sessionSettingsLimitIsTheDefaultReadLimit() async throws {
        let temp = try SQLiteSessionTestSupport.temporaryDatabasePath("settings-limit.db")
        defer { temp.cleanup() }
        let session = try SQLiteSession(
            sessionID: "settings_limit",
            dbPath: temp.path,
            sessionSettings: SessionSettings(limit: 3)
        )
        defer { session.close() }
        let items = (0..<5).map { SQLiteSessionTestSupport.message(.user, "Message \($0)") }

        try await session.addItems(items)

        #expect(try await session.getItems() == Array(items.suffix(3)))
    }

    @Test
    func explicitLimitOverridesSessionSettingsLimit() async throws {
        let temp = try SQLiteSessionTestSupport.temporaryDatabasePath("override.db")
        defer { temp.cleanup() }
        let session = try SQLiteSession(
            sessionID: "override",
            dbPath: temp.path,
            sessionSettings: SessionSettings(limit: 5)
        )
        defer { session.close() }
        let items = (0..<10).map { SQLiteSessionTestSupport.message(.user, "Message \($0)") }

        try await session.addItems(items)

        #expect(try await session.getItems(limit: 2) == Array(items.suffix(2)))
    }

    @Test
    func constructorDefaultsMirrorUpstream() throws {
        let session = try SQLiteSession(sessionID: "default_settings")
        defer { session.close() }

        #expect(session.dbPath == ":memory:")
        #expect(session.sessionsTable == "agent_sessions")
        #expect(session.messagesTable == "agent_messages")
        #expect(session.sessionSettings == SessionSettings())
    }
}
