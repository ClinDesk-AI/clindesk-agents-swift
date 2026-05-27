import Foundation
import SQLite3
import Testing
import ClinDeskAgents

@Suite
struct SQLiteSessionStorageTests {
    @Test
    func storesRetrievesAndClearsItems() async throws {
        let temp = try SQLiteSessionTestSupport.temporaryDatabasePath("direct.db")
        defer { temp.cleanup() }
        let session = try SQLiteSession(sessionID: "direct_test", dbPath: temp.path)
        defer { session.close() }

        let items = [
            SQLiteSessionTestSupport.message(.user, "Hello"),
            SQLiteSessionTestSupport.message(.assistant, "Hi there!")
        ]

        try await session.addItems(items)
        #expect(try await session.getItems() == items)

        try await session.clearSession()
        #expect(try await session.getItems() == [])
    }

    @Test
    func popItemReturnsNewestItemsAndThenNil() async throws {
        let temp = try SQLiteSessionTestSupport.temporaryDatabasePath("pop.db")
        defer { temp.cleanup() }
        let session = try SQLiteSession(sessionID: "pop_test", dbPath: temp.path)
        defer { session.close() }
        let first = SQLiteSessionTestSupport.message(.user, "Hello")
        let second = SQLiteSessionTestSupport.message(.assistant, "Hi there!")
        let third = SQLiteSessionTestSupport.message(.user, "How are you?")

        #expect(try await session.popItem() == nil)

        try await session.addItems([first, second, third])

        #expect(try await session.popItem() == third)
        #expect(try await session.popItem() == second)
        #expect(try await session.popItem() == first)
        #expect(try await session.popItem() == nil)
        #expect(try await session.getItems() == [])
    }

    @Test
    func separateSessionIDsShareDatabaseWithoutSharingHistory() async throws {
        let temp = try SQLiteSessionTestSupport.temporaryDatabasePath("sessions.db")
        defer { temp.cleanup() }
        let session1 = try SQLiteSession(sessionID: "session_1", dbPath: temp.path)
        let session2 = try SQLiteSession(sessionID: "session_2", dbPath: temp.path)
        defer {
            session1.close()
            session2.close()
        }

        try await session1.addItems([SQLiteSessionTestSupport.message(.user, "Session 1")])
        try await session2.addItems([
            SQLiteSessionTestSupport.message(.user, "Session 2 message 1"),
            SQLiteSessionTestSupport.message(.user, "Session 2 message 2")
        ])

        #expect(try await session2.popItem()?.testMessageContent == "Session 2 message 2")
        #expect((try await session1.getItems()).map(\.testMessageContent) == ["Session 1"])
        #expect((try await session2.getItems()).map(\.testMessageContent) == ["Session 2 message 1"])
    }

    @Test
    func fileBackedSessionsPersistAcrossInstances() async throws {
        let temp = try SQLiteSessionTestSupport.temporaryDatabasePath("persistent.db")
        defer { temp.cleanup() }
        let item = SQLiteSessionTestSupport.message(.user, "Persist me")

        let first = try SQLiteSession(sessionID: "persistent", dbPath: temp.path)
        try await first.addItems([item])
        first.close()

        let second = try SQLiteSession(sessionID: "persistent", dbPath: temp.path)
        defer { second.close() }
        #expect(try await second.getItems() == [item])
    }

    @Test
    func unicodeAndSpecialCharactersRoundTrip() async throws {
        let temp = try SQLiteSessionTestSupport.temporaryDatabasePath("unicode.db")
        defer { temp.cleanup() }
        let session = try SQLiteSession(sessionID: "unicode", dbPath: temp.path)
        defer { session.close() }
        let items = [
            SQLiteSessionTestSupport.message(.user, "こんにちは"),
            SQLiteSessionTestSupport.message(.assistant, "O'Reilly"),
            SQLiteSessionTestSupport.message(.user, "\"SELECT * FROM users\""),
            SQLiteSessionTestSupport.message(.assistant, "Привет")
        ]

        try await session.addItems(items)

        #expect(try await session.getItems() == items)
    }

    @Test
    func corruptRowsAreSkippedOnReadAndDroppedOnPop() async throws {
        let temp = try SQLiteSessionTestSupport.temporaryDatabasePath("corrupt.db")
        defer { temp.cleanup() }
        let session = try SQLiteSession(sessionID: "corrupt", dbPath: temp.path)
        defer { session.close() }
        let valid = SQLiteSessionTestSupport.message(.user, "valid")

        try await session.addItems([valid])
        try insertRawMessage(
            dbPath: temp.path,
            sessionID: session.sessionID,
            tableName: session.messagesTable,
            rawJSON: "not valid json {{{"
        )

        #expect(try await session.getItems() == [valid])
        #expect(try await session.popItem() == valid)
        #expect(try await session.getItems() == [])
    }

    @Test
    func closedSessionRejectsFurtherOperations() async throws {
        let session = try SQLiteSession(sessionID: "closed")
        session.close()

        await #expect(throws: SQLiteSessionError("SQLiteSession is closed")) {
            _ = try await session.getItems()
        }
    }

    private func insertRawMessage(
        dbPath: String,
        sessionID: String,
        tableName: String,
        rawJSON: String
    ) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            dbPath,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database
        else {
            throw SQLiteSessionError("Unable to open SQLite database for test.")
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "INSERT INTO \(tableName) (session_id, message_data) VALUES (?, ?)",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement
        else {
            throw SQLiteSessionError(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let bindSessionID = sessionID.withCString {
            sqlite3_bind_text(statement, 1, $0, -1, transient)
        }
        let bindRawJSON = rawJSON.withCString {
            sqlite3_bind_text(statement, 2, $0, -1, transient)
        }
        guard bindSessionID == SQLITE_OK, bindRawJSON == SQLITE_OK else {
            throw SQLiteSessionError(String(cString: sqlite3_errmsg(database)))
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionError(String(cString: sqlite3_errmsg(database)))
        }
    }
}
